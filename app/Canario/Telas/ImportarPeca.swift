import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

/// Entrada por arquivo: print, foto ou PDF (§28, com a revogação parcial do A7).
///
/// O desenho segue o v0 da §28 — **formulário primeiro**: o arquivo pré-preenche
/// os atributos e o usuário confirma ou corrige. É o humano no circuito que
/// derruba a exigência de acurácia da leitura, e por isso o app pode usar OCR e
/// medição de cor em vez de um modelo treinado.
///
/// **Três entradas, uma leitura (A12).** Arquivo, fototeca e câmera terminam no
/// mesmo `LeitorDeArquivo`: OCR do texto, cor do pixel, atributos marcados no
/// formulário. Câmera e fototeca entraram em 07/08, desfazendo o corte do A7.
///
/// A imagem original continua só em memória. A18 autoriza uma exceção explícita
/// e local: quando o usuário salva a peça no Closet, uma miniatura reamostrada,
/// sem metadados, pode ser persistida e é apagada com a peça.
struct ImportarPeca: View {
    let termos: [Termo]
    var aoSalvar: (() -> Void)? = nil

    /// A imagem da loja é acessória: os atributos já chegaram pelo painel. Um
    /// CDN lento não pode manter a tela inteira em espera pelo timeout padrão
    /// de um minuto da `URLSession.shared`.
    private static let sessaoDaImagemDoProduto: URLSession = {
        let configuracao = URLSessionConfiguration.ephemeral
        configuracao.timeoutIntervalForRequest = 10
        configuracao.waitsForConnectivity = false
        configuracao.requestCachePolicy = .returnCacheDataElseLoad
        configuracao.urlCache = URLCache(memoryCapacity: 4 << 20,
                                         diskCapacity: 24 << 20)
        return URLSession(configuration: configuracao)
    }()

    @State private var mostrandoSeletor = false
    @State private var mostrandoCamera = false
    @State private var daFototeca: PhotosPickerItem?
    @State private var lendo = false
    /// O que a espera atual está fazendo. Sem isto a tela era um spinner num
    /// fundo branco, igual para ler um arquivo e para esperar a análise visual
    /// -- que leva segundos de rede.
    @State private var esperaAtual = Espera.lendoArquivo
    /// Aviso de consumo, quando este aparelho se aproxima do teto da rede.
    /// `nil` na maior parte do tempo, de propósito -- ver `ContadorDeAnalises`.
    @State private var avisoDeUso: String?

    enum Espera {
        case lendoArquivo, lendoLink, separandoPeca, analisandoLocal, analisandoNaNuvem

        var mensagem: String {
            switch self {
            case .lendoArquivo:     return "Reading the file…"
            case .lendoLink:        return "Checking the product link…"
            case .separandoPeca:    return "Separating the garment…"
            case .analisandoLocal:  return "Reading the garment…"
            case .analisandoNaNuvem: return "Reading the garment…"
            }
        }

        /// Só quando a espera é longa por natureza. Aviso em espera curta vira
        /// ruído; ausência de aviso em espera longa parece travamento.
        var expectativa: String? {
            switch self {
            case .lendoArquivo, .lendoLink, .analisandoLocal: return nil
            case .separandoPeca:
                return "This happens on this iPhone."
            case .analisandoNaNuvem:
                return "The visual analysis runs on the server and usually takes a few seconds."
            }
        }
    }
    @State private var erro: String?
    @State private var detectados: Set<String> = []
    /// As três telas do fluxo de preenchimento, nomeadas. O resultado abre
    /// e termina aqui mesmo, com nome, atributos e Add to Closet. A antiga
    /// Clothing Details repetia o mesmo conteúdo e foi removida deste fluxo.
    ///
    /// Antes isto era um encadeado de booleanos -- `lendo`, `imagemPendente`,
    /// `confirmou` -- e a tela de atributos convivia com a de upload no mesmo
    /// `formulario`. A revisão de UX pediu para separar: escolher a foto,
    /// confirmar a peça, corrigir o que foi lido e ler o resultado são quatro
    /// momentos diferentes, e cada um pede a tela inteira.
    enum Etapa {
        /// Foto e preço. Nada de atributos: eles ainda não existem.
        case entrada
        /// Qual peça da foto é a que interessa.
        case confirmarAlvo
        /// O que o app leu, já marcado, para a pessoa corrigir.
        case atributos
    }

    /// Ver o comentário na tela de confirmação do alvo.
    static let mostraAlternativasDeAlvo = false

    @State private var etapa = Etapa.entrada
    @State private var nomeDoArquivo: String?
    @State private var procedencia: [String] = []
    @State private var precoDigitado = ""
    @State private var linkDigitado = ""
    @State private var miniaturaJPEG: Data?
    @State private var imagemPendente: CGImage?
    /// A foto como ela entrou, antes de qualquer recorte.
    ///
    /// O recorte confirmado SUBSTITUÍA `imagemPendente`, então abrir "Adjust" de
    /// novo recortava o recorte, e a foto escolhida não voltava mais: "se a
    /// gente se arrepender e quiser voltar ele não deixa resetar pra imagem
    /// original". Guardar a original custa uma referência e devolve o caminho
    /// de volta.
    @State private var imagemOriginal: CGImage?
    @State private var nomePendente: String?
    /// Há recorte a desfazer? `CGImage` é tipo de referência, então identidade
    /// basta: `prepararConfirmacao` guarda a mesma instância nos dois campos
    /// quando a foto entra inteira.
    private var fotoFoiRecortada: Bool {
        guard let atual = imagemPendente, let original = imagemOriginal
        else { return false }
        return atual !== original
    }
    @State private var opcoesDeAlvo: [MiniaturaLocal.OpcaoDeAlvo] = []
    @State private var alvoEscolhido: Int?
    @State private var descricaoDoAlvo = ""
    @State private var nomeDaPeca = ""
    @State private var salvandoNoCloset = false
    @State private var analiseConcluidaParaOAlvo = false
    @State private var mostrandoEditorDeRecorte = false
    @State private var pedindoConsentimentoDaNuvem = false
    @State private var imagemConfirmadaPendente: CGImage?
    @State private var dadosConfirmadosPendentes: Data?
    @State private var nomeConfirmadoPendente: String?
    @State private var descricaoConfirmadaPendente: String?
    @FocusState private var precoEmFoco: Bool
    @FocusState private var linkEmFoco: Bool
    @FocusState private var dicaDoAlvoEmFoco: Bool
    @FocusState private var nomeDaPecaEmFoco: Bool

    /// §29.5 — contexto condicional. Opcional de propósito: sem ele o relatório
    /// funciona igual, e com ele entra o percentil de preço que a §5 autoriza
    /// como substituto da previsão proibida.
    private var precoAlvo: Double? {
        let limpo = precoDigitado
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(limpo), v > 0 else { return nil }
        return v
    }

    @Environment(\.dismiss) private var dismiss

    /// Tipos aceitos, nomeados um a um.
    ///
    /// `.image` sozinho cobre JPG em tese, mas arquivo vindo de WhatsApp e de
    /// Arquivos às vezes chega declarado como tipo genérico, e aí o seletor
    /// deixava o item cinza. Nomear os tipos concretos resolve o caso real.
    private let tiposAceitos: [UTType] = [.pdf, .jpeg, .png, .heic, .heif, .tiff, .image]

    var body: some View {
        NavigationStack {
            Group {
                if lendo {
                    Carregando(mensagem: esperaAtual.mensagem,
                               expectativa: esperaAtual.expectativa)
                } else {
                    switch etapa {
                    case .entrada:       telaDeEntrada
                    case .confirmarAlvo: confirmacaoDoAlvo
                    case .atributos:     telaDeAtributos
                    }
                }
            }
            .navigationTitle(tituloDaEtapa)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Nas telas do meio, o canto esquerdo volta um passo. Só na
                    // primeira ele fecha tudo -- fechar de dentro do fluxo
                    // perderia o trabalho sem avisar.
                    if etapa == .entrada || lendo {
                        Button("Close") { dismiss() }
                    } else {
                        Button("Back") { voltarUmaEtapa() }
                    }
                }
            }
        }
        // Lido na abertura, para quem já estava perto do teto antes de começar.
        .task {
            avisoDeUso = await RegistroDeAnalises.shared.aviso()
            if ProcessInfo.processInfo.arguments.contains("-CanarioUITestDetalhes") {
                detectados = Set(["vestido", "preto"])
                procedencia = ["Offline interface test."]
                etapa = .atributos
            }
        }
        .fileImporter(
            isPresented: $mostrandoSeletor,
            allowedContentTypes: tiposAceitos,
            allowsMultipleSelection: false
        ) { resultado in
            Task { await processar(resultado) }
        }
        .fullScreenCover(isPresented: $mostrandoCamera) {
            CapturaDeCamera { imagem in
                mostrandoCamera = false
                guard let imagem else { return }   // cancelou
                Task { await prepararConfirmacao(imagem, nome: "camera photo") }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $mostrandoEditorDeRecorte) {
            if let imagem = imagemPendente {
                EditorDeRecorte(imagem: imagem) { recortada in
                    mostrandoEditorDeRecorte = false
                    let nome = nomePendente ?? "cropped image"
                    let original = imagemOriginal ?? imagem
                    Task {
                        await prepararConfirmacao(recortada, nome: nome,
                                                  recorteDe: original)
                    }
                }
            }
        }
        .onChange(of: daFototeca) { _, item in
            guard let item else { return }
            Task { await processarDaFototeca(item) }
        }
        .alert("Use cloud visual analysis?",
               isPresented: $pedindoConsentimentoDaNuvem) {
            Button("Analyze on this iPhone", role: .cancel) {
                Task {
                    await PreferenciasDaAnaliseVisual.shared.definir(.aparelho)
                    await analisarPendente(usandoNuvem: false)
                }
            }
            Button("Continue with visual analysis") {
                Task {
                    await PreferenciasDaAnaliseVisual.shared.definir(.nuvem)
                    await analisarPendente(usandoNuvem: true)
                }
            }
        } message: {
            Text("Recommended for more complete suggestions. DataDrobe analyzes only the reduced, metadata-free image you confirmed. The original is not uploaded, and you will review every attribute before saving. You can change this later in Settings; on-device analysis does not use the cloud-analysis limit.")
        }
    }

    // MARK: Formulário

    /// A câmera não sabe qual peça da cena interessa, e o segmentador do iOS
    /// sabe separar instâncias mas não sabe qual delas está à venda. Esta tela
    /// fecha as duas lacunas antes de qualquer atributo ser sugerido.
    private var confirmacaoDoAlvo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                    Text("Which item should I analyze?")
                        .font(Tokens.Fonte.titulo)
                    Text("Select the garment you meant to add. Category, color and attributes will be read only after you confirm it.")
                        .font(Tokens.Fonte.apoio)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }

                if let escolhida = opcaoEscolhida {
                    PreviaDoAlvo(dados: escolhida.dados, id: escolhida.id,
                                 altura: 320, selecionada: true)
                    // A frase antiga mandava "usar a foto completa quando as
                    // opções isoladas cortarem parte da peça" -- instrução para
                    // uma fileira de alternativas que não existe mais. Agora
                    // ela só diz o que aconteceu com a imagem que está à vista.
                    Text(escolhida.tipo == .fotoCompleta
                         ? "Whole photo: I could not isolate the garment here."
                         : "Background removed on this device.")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }

                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    Text("Optional target hint")
                        .font(Tokens.Fonte.secao)
                    TextField("e.g. the black half-zip jacket",
                              text: $descricaoDoAlvo,
                              axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .focused($dicaDoAlvoEmFoco)
                        .submitLabel(.done)
                        .onSubmit { dicaDoAlvoEmFoco = false }
                        .onChange(of: descricaoDoAlvo) { _, _ in
                            analiseConcluidaParaOAlvo = false
                        }
                    Text("Use this only when the photo contains more than one item. Visible pixels always take precedence.")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }

                HStack(spacing: Tokens.Espaco.s) {
                    Button {
                        mostrandoEditorDeRecorte = true
                    } label: {
                        // "Crop or zoom the photo" para dizer o que o ícone de
                        // recorte já diz. Uma palavra basta.
                        Label("Adjust", systemImage: "crop")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    // Só aparece quando há o que desfazer. Antes o recorte era
                    // caminho de mão única: ele substituía a foto pendente, e
                    // um segundo "Adjust" recortava o próprio recorte.
                    if fotoFoiRecortada {
                        Button {
                            guard let original = imagemOriginal else { return }
                            let nome = nomePendente ?? "photo"
                            Task {
                                await prepararConfirmacao(original, nome: nome)
                            }
                        } label: {
                            Label("Undo crop", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // A fileira de alternativas saiu. O recorte isolado é sempre
                // a versão melhor e menos poluída da foto, e quando ele não
                // existe o app já cai na foto completa sozinho -- sem pedir
                // que a pessoa escolha entre coisas que ela não pediu.
                //
                // Fica desligada por uma flag em vez de apagada: se o
                // isolamento voltar a errar, a saída manual existe e é uma
                // linha, em vez de um commit revertido.
                if Self.mostraAlternativasDeAlvo, opcoesDeAlvo.count > 1 {
                    VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                        Text("Other targets")
                            .font(Tokens.Fonte.secao)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Tokens.Espaco.s) {
                                ForEach(opcoesDeAlvo) { opcao in
                                    Button {
                                        if alvoEscolhido != opcao.id {
                                            analiseConcluidaParaOAlvo = false
                                        }
                                        alvoEscolhido = opcao.id
                                    } label: {
                                        VStack(spacing: Tokens.Espaco.xs) {
                                            PreviaDoAlvo(dados: opcao.dados, id: opcao.id,
                                                         altura: 112,
                                                         selecionada: alvoEscolhido == opcao.id)
                                            Text(opcao.rotulo)
                                                .font(Tokens.Fonte.miudo)
                                                .foregroundStyle(Tokens.Cor.tinta)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Select \(opcao.rotulo.lowercased())")
                                }
                            }
                        }
                    }
                }

                // O aviso mora aqui, e não na tela de resultado: este é o
                // botão que gasta a próxima análise, e aviso depois do gasto
                // não é aviso, é relatório.
                if let avisoDeUso {
                    LinhaInsumo(texto: avisoDeUso)
                }

                Button {
                    Task { await confirmarAlvo() }
                } label: {
                    Label("Analyze this item", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(opcaoEscolhida == nil)

                // "Choose another photo" saiu do corpo: trocar de foto é
                // voltar, e voltar já tem um lugar -- a barra de navegação.
                // Botão de desfazer com o mesmo peso do botão de seguir divide
                // a atenção no momento em que ela deveria ser uma só.
            }
            .padding(Tokens.Espaco.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dicaDoAlvoEmFoco = false }
            }
        }
    }

    private var opcaoEscolhida: MiniaturaLocal.OpcaoDeAlvo? {
        opcoesDeAlvo.first { $0.id == alvoEscolhido }
    }

    /// Tela 1: a foto e o preço. Os atributos saíram daqui -- antes da leitura
    /// eles seriam uma lista vazia pedindo trabalho manual, e depois dela vêm
    /// preenchidos, que é outra tela.
    private var telaDeEntrada: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                importador
                precoOpcional
            }
            .padding(Tokens.Espaco.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    precoEmFoco = false
                    linkEmFoco = false
                    dicaDoAlvoEmFoco = false
                    nomeDaPecaEmFoco = false
                }
            }
        }
    }

    /// Tela 3: o que o app leu, já marcado, para a pessoa corrigir.
    ///
    /// A leitura vem antes dos chips de propósito: a pergunta desta tela é
    /// "está certo?", e para responder é preciso ver primeiro o que foi lido.
    private var telaDeAtributos: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if let miniaturaJPEG {
                    PreviaDoAlvo(dados: miniaturaJPEG,
                                 id: miniaturaJPEG.count,
                                 altura: 220,
                                 selecionada: true)
                        .accessibilityLabel("Item being described")
                }
                if let erro {
                    // O título dizia "I could not tell which category this is"
                    // em TODA falha -- inclusive quando o motivo era o teto
                    // diário, a rede ou o arquivo. Ou seja: anunciava um
                    // fracasso de classificação que muitas vezes não tinha
                    // acontecido, e soava como se o app tivesse feito algo
                    // errado. Agora o título só constata o estado, e o motivo
                    // real continua logo abaixo, vindo de `erro`.
                    CoberturaInsuficiente(
                        titulo: "No attributes were read",
                        explicacao: erro,
                        oQueTem: "You can select the attributes below and continue.")
                }
                if !procedencia.isEmpty { oQueLi }
                Cartao {
                    Text("Name this item").font(Tokens.Fonte.secao)
                    TextField("Clothing name (optional)", text: $nomeDaPeca)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($nomeDaPecaEmFoco)
                        .onSubmit { nomeDaPecaEmFoco = false }
                    LinhaInsumo(texto: "If left blank, Closet, links and spreadsheets use the confirmed category.")
                }
                atributos
                if !detectados.isEmpty {
                    Button {
                        Task { await salvarNoCloset() }
                    } label: {
                        Group {
                            if salvandoNoCloset { ProgressView() }
                            else { Label("Add to Closet", systemImage: "archivebox") }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(salvandoNoCloset)
                }
            }
            .padding(Tokens.Espaco.m)
        }
    }

    private var importador: some View {
        Cartao {
            Text("Product link, photo or file").font(Tokens.Fonte.secao)
            TextField("Paste a product link", text: $linkDigitado)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
                .focused($linkEmFoco)
                .submitLabel(.go)
                .onSubmit { Task { await processarLink() } }
            Button {
                Task { await processarLink() }
            } label: {
                Label("Read product link", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(linkDigitado.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Divider()
            // A câmera vem primeiro porque é o gesto mais direto de quem está
            // com a peça na mão -- que é a situação do comprador em showroom.
            // Some no simulador e em aparelho sem câmera, em vez de abrir nada.
            if CapturaDeCamera.disponivel {
                Button {
                    erro = nil
                    mostrandoCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $daFototeca, matching: .images,
                         photoLibrary: .shared()) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                erro = nil
                mostrandoSeletor = true
            } label: {
                Label("Choose a file or PDF", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if let nomeDoArquivo {
                LinhaInsumo(texto: "Loaded: \(nomeDoArquivo)")
            }

            // O texto de privacidade ficava ACIMA dos botões, três linhas entre
            // a pessoa e a ação que ela veio fazer. A revisão de UX pediu duas
            // coisas que se resolvem no mesmo lugar: "esconder as leituras que
            // impedem a ação" e "colocar o textinho de proteção no rodapé".
            //
            // Ele não sai da tela. Dizer o que acontece com a foto antes de a
            // pessoa escolher uma é obrigação, não enfeite -- e a tela de
            // Privacy repete tudo. O que muda é a ordem: primeiro o que fazer,
            // depois o que acontece.
            Text(Supabase.analiseRemotaHabilitada
                 ? "The app prepares the image on this iPhone and asks before sending a reduced, metadata-free copy for visual analysis. The original is not stored; only a local thumbnail remains if you save the item to Closet."
                 : "The app reads the file on this iPhone. The original is not stored; only a local, metadata-free thumbnail remains if you save the item to Closet.")
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
        }
    }

    /// Regra 3: o usuário precisa saber de onde saiu cada marcação. Sem isto,
    /// uma cor sugerida pelo pixel parece um fato tão firme quanto um título
    /// lido por extenso, e as duas não têm a mesma força.
    private var oQueLi: some View {
        Cartao {
            Text("What I read from this file").font(Tokens.Fonte.secao)
            ForEach(procedencia, id: \.self) { LinhaInsumo(texto: $0) }
            // Este aviso fica AQUI, e só aqui. O caminho da análise remota
            // acrescentava uma segunda versão dele em `procedencia`, com outra
            // redação, e a tela mostrava as duas seguidas -- descoberto no
            // primeiro teste ponta a ponta com a Luna ligada, em 19/08.
            // Deixando um só, ele continua aparecendo nos dois caminhos.
            LinhaInsumo(texto: "Review every suggestion. Your confirmed selection is what counts.")
        }
    }

    /// Os atributos, agrupados por dimensão. O que o arquivo sugeriu vem
    /// marcado; tudo é editável, porque a §28 exige que as tags sejam sempre
    /// corrigíveis pelo usuário.
    private var atributos: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.m) {
            HStack {
                Text("Item attributes").font(Tokens.Fonte.secao)
                Spacer()
                if !detectados.isEmpty {
                    Button("Clear") { detectados.removeAll() }
                        .font(Tokens.Fonte.miudo)
                }
            }
            ForEach(dimensoes, id: \.self) { dimensao in
                VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                    Text(Traducao.rotuloDaDimensao(dimensao))
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                    FluxoDeChips(
                        termos: termosVisiveis(na: dimensao),
                        todos: termosDoFormulario,
                        marcados: $detectados)
                }
            }
        }
    }

    /// §29.5 — o único campo que o usuário digita, e ele é opcional.
    private var precoOpcional: some View {
        Cartao {
            Text("Your intended price").font(Tokens.Fonte.secao)
            Text("Optional. If you add it, I show its position among similar pieces in the panel — a price position, not a judgment.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            TextField("R$ 0,00", text: $precoDigitado)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($precoEmFoco)
                .submitLabel(.done)
        }
    }

    private var dimensoes: [String] {
        let categorias = Set(termosDoFormulario.lazy
            .filter { $0.dimensao == "categoria" && detectados.contains($0.id) }
            .map(\.id))
        let permitidas = FormularioDaPeca.dimensoesPermitidas(categorias: categorias)
        var vistas: [String] = []
        for t in termosDoFormulario where permitidas.contains(t.dimensao) {
            let visivel = t.dimensao == "motivo_estampa" ? "estampa" : t.dimensao
            if !vistas.contains(visivel) { vistas.append(visivel) }
        }
        return vistas
    }

    private func termosVisiveis(na dimensao: String) -> [Termo] {
        let encontrados = termosDoFormulario.filter {
            $0.dimensao == dimensao
                || (dimensao == "estampa" && $0.dimensao == "motivo_estampa")
        }.filter { $0.id != "trico_croche" }
        guard dimensao == "estampa" else { return encontrados }
        // Animal print é uma linguagem central da moda feminina, não um item
        // residual depois de padrões com mais títulos catalogados. A ordem da
        // tela é de reconhecimento humano; a ordem estatística segue intacta.
        let prioridade = [
            "animal_print", "floral", "listra", "xadrez", "geometrica",
            "conversacional", "tomate_print", "cereja_print", "morango_print",
            "banana_print", "abacaxi_print", "melancia_print", "liso",
        ]
        return encontrados.sorted {
            (prioridade.firstIndex(of: $0.id) ?? 99)
                < (prioridade.firstIndex(of: $1.id) ?? 99)
        }
    }

    private var termosDoFormulario: [Termo] {
        if !termos.isEmpty { return termos }
        guard ProcessInfo.processInfo.arguments.contains("-CanarioUITestDetalhes") else {
            return []
        }
        return [
            Termo(id: "vestido", rotulo: "Dress", dimensao: "categoria",
                  exclusiva: true, sinonimos: nil, semPernaBusca: nil,
                  palavrasPt: nil, palavrasEn: nil),
            Termo(id: "preto", rotulo: "Black", dimensao: "cor",
                  exclusiva: false, sinonimos: nil, semPernaBusca: nil,
                  palavrasPt: nil, palavrasEn: nil),
        ]
    }

    // MARK: Leitura

    /// Fototeca: o item vira imagem em memória e segue o mesmo caminho.
    private func processarDaFototeca(_ item: PhotosPickerItem) async {
        daFototeca = nil
        esperaAtual = .lendoArquivo
        lendo = true
        erro = nil
        guard let dados = try? await item.loadTransferable(type: Data.self),
              let imagem = MiniaturaLocal.imagem(de: dados) else {
            erro = "I couldn't open this photo."
            etapa = .entrada
            lendo = false
            return
        }
        await prepararConfirmacao(imagem, nome: "photo library image")
    }

    /// URL já coletada é a rota mais barata e mais auditável: reaproveita os
    /// atributos derivados do título da própria loja e não chama visão.
    private func processarLink() async {
        let texto = linkDigitado.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: texto), url.scheme == "https", url.host != nil else {
            erro = "Paste a complete https product link."
            return
        }
        linkEmFoco = false
        esperaAtual = .lendoLink
        lendo = true
        erro = nil
        do {
            guard let produto = try await Supabase.shared.produtoDoPainel(url: texto) else {
                erro = "This product is not in the market panel yet. Add a photo instead and I will read the visible item."
                lendo = false
                return
            }
            let existentes = Set(termos.map(\.id))
            detectados = FormularioDaPeca.podar(
                Set(produto.termIDs).intersection(existentes), termos: termos)
            guard FormularioDaPeca.temCategoria(detectados, termos: termos) else {
                erro = "I found this product, but its category is not classified yet. Add a photo or choose the attributes manually."
                etapa = .atributos
                lendo = false
                return
            }
            if precoDigitado.isEmpty, let preco = produto.price {
                precoDigitado = String(format: "%.2f", preco)
                    .replacingOccurrences(of: ".", with: ",")
            }
            nomeDoArquivo = "\(produto.brand) product link"
            procedencia = [
                "Matched \(produto.brand) · \(produto.title ?? "product") in the market panel.",
                "Attributes came from the store title and the panel taxonomy. No visual-analysis credit was used."
            ]
            // O resultado textual já está completo. A tela abre agora e a
            // foto entra quando o CDN responder; imagem acessória nunca segura
            // a navegação nem dá aparência de travamento.
            etapa = .atributos
            lendo = false
            if let imagem = produto.imageURL.flatMap(URL.init(string:)),
               imagem.scheme == "https",
               let (dados, resposta) = try? await Self.sessaoDaImagemDoProduto.data(from: imagem),
               (resposta as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
               dados.count <= 8_000_000,
               let cg = MiniaturaLocal.imagem(de: dados) {
                miniaturaJPEG = await MiniaturaLocal.dados(de: cg)
            }
        } catch {
            erro = "I couldn't check this product link right now. You can still add a photo or file."
        }
        lendo = false
    }

    /// Câmera e fototeca passam pelo mesmo portão visual. A opção pré-selecionada
    /// ainda exige um toque explícito no botão de confirmação.
    /// `recorteDe` chega preenchido só quando esta imagem veio do editor. Sem
    /// isso a foto original era sobrescrita pelo próprio recorte e não havia
    /// volta -- ver `imagemOriginal`.
    private func prepararConfirmacao(_ imagem: CGImage, nome: String,
                                     recorteDe original: CGImage? = nil) async {
        esperaAtual = .separandoPeca
        lendo = true
        erro = nil
        procedencia = []
        detectados = []
        analiseConcluidaParaOAlvo = false
        let opcoes = await MiniaturaLocal.opcoesDeAlvo(de: imagem)
        guard !opcoes.isEmpty else {
            erro = "I could not prepare this image. Choose another photo or file."
            etapa = .entrada
            lendo = false
            return
        }
        imagemPendente = imagem
        imagemOriginal = original ?? imagem
        nomePendente = nome
        opcoesDeAlvo = opcoes
        alvoEscolhido = opcoes.first?.id
        etapa = .confirmarAlvo
        lendo = false
    }

    private func confirmarAlvo() async {
        if analiseConcluidaParaOAlvo {
            etapa = .atributos
            return
        }
        guard let original = imagemPendente, let escolha = opcaoEscolhida else { return }
        let imagem: CGImage?
        switch escolha.tipo {
        case .primeiroPlano:
            imagem = MiniaturaLocal.imagem(de: escolha.dados)
        case .fotoCompleta:
            imagem = original
        }
        guard let imagem else {
            erro = "I could not open the selected item. Choose another option."
            return
        }

        let nome = nomePendente ?? "selected image"
        miniaturaJPEG = escolha.dados
        if Supabase.analiseRemotaHabilitada {
            imagemConfirmadaPendente = imagem
            dadosConfirmadosPendentes = await MiniaturaLocal.opacaParaAnalise(de: escolha.dados)
            nomeConfirmadoPendente = nome
            descricaoConfirmadaPendente = descricaoDoAlvoNormalizada
            switch await PreferenciasDaAnaliseVisual.shared.preferencia() {
            case .nuvem:
                await analisarPendente(usandoNuvem: true)
            case .aparelho:
                await analisarPendente(usandoNuvem: false)
            case .perguntar:
                pedindoConsentimentoDaNuvem = true
            }
        } else {
            await analisarImagemConfirmada(imagem, nome: nome,
                                            dadosParaNuvem: nil,
                                            descricaoDoAlvo: nil)
        }
    }

    private func analisarPendente(usandoNuvem: Bool) async {
        guard let imagem = imagemConfirmadaPendente else { return }
        let nome = nomeConfirmadoPendente ?? "selected image"
        let dados = usandoNuvem ? dadosConfirmadosPendentes : nil
        let descricao = usandoNuvem ? descricaoConfirmadaPendente : nil
        imagemConfirmadaPendente = nil
        dadosConfirmadosPendentes = nil
        nomeConfirmadoPendente = nil
        descricaoConfirmadaPendente = nil
        await analisarImagemConfirmada(imagem, nome: nome,
                                        dadosParaNuvem: dados,
                                        descricaoDoAlvo: descricao)
    }

    /// O título diz em que passo a pessoa está. "Analyze an item" nas quatro
    /// telas não dizia nada sobre o progresso.
    private var tituloDaEtapa: String {
        switch etapa {
        case .entrada:       return "Analyze an item"
        case .confirmarAlvo: return "Which item"
        case .atributos:     return "Confirm your item"
        }
    }

    /// Voltar um passo preserva foto, recorte e a leitura já paga.
    private func voltarUmaEtapa() {
        switch etapa {
        case .entrada:       break
        case .confirmarAlvo: cancelarConfirmacao()
        case .atributos:     etapa = .confirmarAlvo
        }
    }

    private func cancelarConfirmacao() {
        etapa = .entrada
        imagemPendente = nil
        imagemOriginal = nil
        nomePendente = nil
        opcoesDeAlvo = []
        alvoEscolhido = nil
        daFototeca = nil
        descricaoDoAlvo = ""
        analiseConcluidaParaOAlvo = false
    }

    private var descricaoDoAlvoNormalizada: String? {
        let limpa = descricaoDoAlvo
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpa.isEmpty else { return nil }
        return String(limpa.prefix(160))
    }

    @MainActor
    private func salvarNoCloset() async {
        guard !detectados.isEmpty else { return }
        salvandoNoCloset = true
        nomeDaPecaEmFoco = false
        let nova = PecaSalva(
            apelido: nomeDaPeca.trimmingCharacters(in: .whitespacesAndNewlines),
            termoIds: Array(detectados).sorted(),
            precoAlvo: precoAlvo)
        let salvou = await PecasSalvas.shared.salvar(
            nova, miniaturaDados: miniaturaJPEG)
        salvandoNoCloset = false
        if salvou {
            aoSalvar?()
            dismiss()
        } else {
            erro = "Your Closet is full (\(PecasSalvas.teto))."
        }
    }

    /// Só a peça confirmada termina no leitor compartilhado.
    private func analisarImagemConfirmada(_ imagem: CGImage, nome: String,
                                          dadosParaNuvem: Data?,
                                          descricaoDoAlvo: String?) async {
        esperaAtual = dadosParaNuvem == nil ? .analisandoLocal : .analisandoNaNuvem
        lendo = true
        erro = nil
        procedencia = []
        nomeDoArquivo = nome
        let leitura = await LeitorDeArquivo.ler(imagem)
        let marcas = Importacao.marcasNoTexto(leitura.texto)

        if let dadosParaNuvem {
            // Conta ANTES de saber o resultado: o servidor reserva a vaga assim
            // que a chamada chega, e uma análise que falhou no meio já gastou o
            // slot. Contar só o sucesso subestimaria o consumo justamente nos
            // dias ruins, que são quando o aviso importa.
            await RegistroDeAnalises.shared.registrar()
            avisoDeUso = await RegistroDeAnalises.shared.aviso()
            do {
                let analise = try await Supabase.shared.analisarPeca(
                    dadosParaNuvem, alvo: descricaoDoAlvo)
                if analise.alvoAmbiguo {
                    detectados = []
                    procedencia = analise.decisionEvidence.map {
                        "Why the target was ambiguous: \($0)"
                    }
                    erro = "The visual analysis found more than one plausible garment. Choose the category and attributes yourself, or try a tighter photo."
                } else {
                    let existentes = Set(termos.map(\.id))
                    // A leitura devolve um valor por dimensão, então não pode
                    // sugerir duas categorias. Mas pode sugerir comprimento
                    // numa calça, e a linha nem apareceria na tela: o atributo
                    // seguiria para o relatório sem ninguém ver. A mesma poda
                    // da escolha manual vale para a sugestão da máquina.
                    detectados = FormularioDaPeca.podar(
                        analise.idsSugeridos(existentes: existentes),
                        termos: termos)
                    let porId = Dictionary(uniqueKeysWithValues: termos.map { ($0.id, $0) })
                    let lidos = detectados.compactMap { porId[$0] }
                        .sorted { ($0.dimensao, $0.id) < ($1.dimensao, $1.id) }
                        .map(Traducao.rotuloExibido)
                    procedencia = [
                        "Visual analysis suggested: \(lidos.joined(separator: ", ")).",
                    ]
                    // "Visible evidence:" repetido em cada linha virava um
                    // muro de texto -- quatro vezes o mesmo prefixo numa tela
                    // que já é longa. Um rótulo, e as evidências como lista.
                    if !analise.decisionEvidence.isEmpty {
                        procedencia.append(
                            "Visible evidence:\n"
                            + analise.decisionEvidence
                                .map { "•  \($0)" }
                                .joined(separator: "\n"))
                    }
                    if !analise.additionalVisualAttributes.isEmpty {
                        procedencia.append(
                            "Also observed, outside the market taxonomy: "
                            + analise.additionalVisualAttributes.joined(separator: ", ") + ".")
                    }
                    if !FormularioDaPeca.temCategoria(detectados, termos: termos) {
                        detectados = []
                        erro = "The analysis returned an invalid category. Choose the attributes manually."
                    }
                }
            } catch {
                aplicarLeituraLocal(leitura,
                    mensagem: "Cloud visual analysis is unavailable right now. I kept the on-device reading; choose the missing attributes manually.")
            }
        } else {
            aplicarLeituraLocal(leitura)
        }

        if !marcas.isEmpty {
            procedencia.append("Brand text recognized on device: \(marcas.joined(separator: ", ")). This is context, not proof of model or material.")
        }
        etapa = .atributos
        analiseConcluidaParaOAlvo = true
        lendo = false
    }

    private func aplicarLeituraLocal(_ leitura: LeitorDeArquivo.Leitura,
                                     mensagem: String? = nil) {
        let achado = Importacao.atributos(de: leitura, em: termos)
        let reconheceuPeca = FormularioDaPeca.temCategoria(achado.marcados, termos: termos)
        detectados = reconheceuPeca ? achado.marcados : []
        procedencia = achado.procedencia
        if let mensagem {
            erro = mensagem
        } else if !reconheceuPeca {
            erro = "I read what I could from the image, but not the category. Pick it below and the rest stays as read."
        }
    }

    private func processar(_ resultado: Result<[URL], Error>) async {
        guard case .success(let urls) = resultado, let url = urls.first else { return }
        esperaAtual = .lendoArquivo
        lendo = true
        erro = nil
        guard let imagem = MiniaturaLocal.imagem(doArquivo: url) else {
            erro = "I couldn't open this file. Choose a JPG, PNG, HEIC or PDF."
            etapa = .entrada
            lendo = false
            return
        }
        await prepararConfirmacao(imagem, nome: url.lastPathComponent)
    }
}

/// Editor manual deliberadamente simples: o usuário enquadra a peça numa janela
/// 3:4, sem o app persistir uma segunda cópia. Ao confirmar, o recorte volta ao
/// mesmo `prepararConfirmacao`, portanto o Vision remove o fundo novamente e a
/// Luna recebe somente a opção isolada que o usuário confirmar depois.
private struct EditorDeRecorte: View {
    let imagem: CGImage
    let aoConfirmar: (CGImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var escala: CGFloat = 1
    @State private var deslocamento: CGSize = .zero
    @GestureState private var ampliacaoTemporaria: CGFloat = 1
    @GestureState private var arrastoTemporario: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geometria in
                let area = tamanhoDoRecorte(em: geometria.size)
                let escalaAtual = min(4, max(1, escala * ampliacaoTemporaria))
                let offsetAtual = limitar(
                    CGSize(width: deslocamento.width + arrastoTemporario.width,
                           height: deslocamento.height + arrastoTemporario.height),
                    escala: escalaAtual,
                    area: area)

                VStack(spacing: Tokens.Espaco.m) {
                    Spacer(minLength: Tokens.Espaco.s)
                    ZStack {
                        Color.black
                        Image(decorative: imagem, scale: 1)
                            .resizable()
                            .frame(width: tamanhoBase(area).width * escalaAtual,
                                   height: tamanhoBase(area).height * escalaAtual)
                            .offset(offsetAtual)
                    }
                    .frame(width: area.width, height: area.height)
                    .clipped()
                    .overlay {
                        RoundedRectangle(cornerRadius: Tokens.Raio.cartao)
                            .stroke(.white.opacity(0.9), lineWidth: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.cartao))
                    .contentShape(Rectangle())
                    .gesture(gestoDeArrasto(area: area)
                        .simultaneously(with: gestoDeAmpliacao(area: area)))

                    Text("Pinch to zoom and drag until the target garment fills the frame.")
                        .font(Tokens.Fonte.apoio)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                        .multilineTextAlignment(.center)

                    Button {
                        if let recortada = imagemRecortada(area: area) {
                            aoConfirmar(recortada)
                        }
                    } label: {
                        Label("Use this crop", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(Tokens.Espaco.m)
            }
            .navigationTitle("Adjust target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") {
                        escala = 1
                        deslocamento = .zero
                    }
                }
            }
        }
    }

    private func tamanhoDoRecorte(em disponivel: CGSize) -> CGSize {
        let largura = min(max(220, disponivel.width - 32), 430)
        let alturaDesejada = largura * 4 / 3
        let altura = min(alturaDesejada, max(260, disponivel.height - 190))
        return CGSize(width: min(largura, altura * 3 / 4), height: altura)
    }

    private func tamanhoBase(_ area: CGSize) -> CGSize {
        let largura = CGFloat(imagem.width)
        let altura = CGFloat(imagem.height)
        let fator = max(area.width / largura, area.height / altura)
        return CGSize(width: largura * fator, height: altura * fator)
    }

    private func limitar(_ valor: CGSize, escala: CGFloat,
                         area: CGSize) -> CGSize {
        let base = tamanhoBase(area)
        let maxX = max(0, (base.width * escala - area.width) / 2)
        let maxY = max(0, (base.height * escala - area.height) / 2)
        return CGSize(width: min(max(valor.width, -maxX), maxX),
                      height: min(max(valor.height, -maxY), maxY))
    }

    private func gestoDeArrasto(area: CGSize) -> some Gesture {
        DragGesture()
            .updating($arrastoTemporario) { valor, estado, _ in
                estado = valor.translation
            }
            .onEnded { valor in
                deslocamento = limitar(
                    CGSize(width: deslocamento.width + valor.translation.width,
                           height: deslocamento.height + valor.translation.height),
                    escala: escala,
                    area: area)
            }
    }

    private func gestoDeAmpliacao(area: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($ampliacaoTemporaria) { valor, estado, _ in
                estado = valor
            }
            .onEnded { valor in
                escala = min(4, max(1, escala * valor))
                deslocamento = limitar(deslocamento, escala: escala, area: area)
            }
    }

    private func imagemRecortada(area: CGSize) -> CGImage? {
        let base = tamanhoBase(area)
        let fatorBase = base.width / CGFloat(imagem.width)
        let fator = fatorBase * escala
        let offset = limitar(deslocamento, escala: escala, area: area)
        let larguraFonte = area.width / fator
        let alturaFonte = area.height / fator
        let x = CGFloat(imagem.width) / 2 - offset.width / fator - larguraFonte / 2
        let y = CGFloat(imagem.height) / 2 - offset.height / fator - alturaFonte / 2
        return MiniaturaLocal.recortar(
            imagem,
            retanguloNormalizado: CGRect(
                x: x / CGFloat(imagem.width),
                y: y / CGFloat(imagem.height),
                width: larguraFonte / CGFloat(imagem.width),
                height: alturaFonte / CGFloat(imagem.height)))
    }
}

/// Decodifica as opções fora da main thread. Uma confirmação com quatro
/// instâncias não pode reintroduzir o engasgo que A22 removeu do Closet.
private struct PreviaDoAlvo: View {
    let dados: Data
    let id: Int
    let altura: CGFloat
    let selecionada: Bool

    @State private var imagem: UIImage?

    private var compacta: Bool { altura < 160 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Raio.cartao)
                .fill(Tokens.Cor.superficie)
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFit()
                    .padding(Tokens.Espaco.s)
            } else {
                ProgressView()
            }
        }
        .frame(width: compacta ? 128 : nil)
        .frame(maxWidth: compacta ? nil : .infinity)
        .frame(height: altura)
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Raio.cartao)
                .stroke(selecionada ? Tokens.Cor.acao : Tokens.Cor.borda,
                        lineWidth: selecionada ? 3 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.cartao))
        .task(id: id) {
            imagem = nil
            imagem = await MiniaturaParaTela.imagem(de: dados)
        }
    }
}

/// Chips de seleção, quebrando linha conforme couber.
struct FluxoDeChips: View {
    let termos: [Termo]
    /// A taxonomia inteira, não só a desta dimensão: sem ela não dá para
    /// remover o comprimento que sobrou quando a categoria mudou.
    let todos: [Termo]
    @Binding var marcados: Set<String>

    var body: some View {
        FlowLayout(espaco: Tokens.Espaco.s) {
            ForEach(termos) { termo in
                let ativo = marcados.contains(termo.id)
                ChipDeAtributo(termo: termo, ativo: ativo) {
                    // A regra vive em `FormularioDaPeca`, fora da View, porque
                    // um `insert` solto aqui deixava montar peça que não
                    // existe -- vestido e calça ao mesmo tempo.
                    marcados = FormularioDaPeca.alternar(
                        termo, em: marcados, termos: todos)
                }
            }
        }
    }
}

/// Um chip só confirma no levantar do dedo e apenas se o deslocamento inteiro
/// ficou abaixo de 6 pt. O botão padrão aceitava a pequena translação usada
/// para iniciar um scroll; no aparelho isso marcou atributos sem intenção.
private struct ChipDeAtributo: View {
    let termo: Termo
    let ativo: Bool
    let acao: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Tokens.Espaco.xs) {
                // Ver a cor vale mais que ler o nome dela. A amostra sai do
                // centro da faixa do classificador (`CorDaPeca`).
                if let rgb = CorDaPeca.rgbRepresentativo(de: termo.id) {
                    Circle()
                        .fill(Color(red: rgb.0, green: rgb.1, blue: rgb.2))
                        // Sem contorno, branco/cru desaparece no fundo claro.
                        .overlay(Circle().strokeBorder(Tokens.Cor.borda, lineWidth: 0.5))
                        .frame(width: 12, height: 12)
                }
                Text(Traducao.rotuloExibido(termo))
            }
            // "Romantic" pede gosto; "ruffle · lace · puff sleeve" pede olhar.
            if let pista = Traducao.pistaDoTermo(termo) {
                Text(pista).font(.caption2).opacity(0.72)
            }
        }
        .font(Tokens.Fonte.miudo)
        .padding(.horizontal, Tokens.Espaco.m)
        .padding(.vertical, Tokens.Espaco.s)
        .background(ativo ? Tokens.Cor.tinta : Tokens.Cor.superficie)
        .foregroundStyle(ativo ? Tokens.Cor.fundo : Tokens.Cor.tinta)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta))
        // Mantém o alvo mínimo de acessibilidade; o filtro de gesto abaixo é
        // que impede essa área maior de transformar scroll em seleção.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(ativo ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { acao() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onEnded { valor in
                    if IntencaoDoToque.confirma(
                        deslocamentoX: Double(valor.translation.width),
                        deslocamentoY: Double(valor.translation.height)) {
                        acao()
                    }
                })
    }
}

/// Layout que quebra linha. Existe porque `LazyVGrid` com largura fixa deixaria
/// buraco entre chips de tamanhos muito diferentes ("Liso" e "Boho e artesanal").
struct FlowLayout: Layout {
    var espaco: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largura = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alturaDaLinha: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x + t.width > largura, x > 0 {
                x = 0; y += alturaDaLinha + espaco; alturaDaLinha = 0
            }
            x += t.width + espaco
            alturaDaLinha = max(alturaDaLinha, t.height)
        }
        return CGSize(width: largura, height: y + alturaDaLinha)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alturaDaLinha: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x + t.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += alturaDaLinha + espaco; alturaDaLinha = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espaco
            alturaDaLinha = max(alturaDaLinha, t.height)
        }
    }
}
