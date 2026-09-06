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

    // MARK: - Tokens Locais

    /// A moldura das três prévias da peça: NEUTRA, não o céu da marca.
    ///
    /// Era `Tokens.Cor.ceu` (#BBE5ED) até 05/09, e este fluxo é onde o dano
    /// era maior: a pessoa olha a prévia sobre azul, decide se a cor sugerida
    /// pela análise está certa e confirma — ou seja, a moldura influenciava
    /// justamente o passo em que o dado de cor entra no Closet. Um fundo
    /// cromático desloca a percepção na direção complementar; a peça lia mais
    /// quente do que é. Ver `SubstratoDaPeca` em `Componentes.swift`.
    ///
    /// Os botões desta tela (`Choose from Photos`, `BotaoDeEntrada`) continuam
    /// no céu da marca de propósito: ali a cor é identidade, e não há nenhuma
    /// peça dentro deles para ser julgada.
    private let corDestaque = Tokens.Cor.substratoDaPeca

    @State private var mostrandoSeletor = false
    @State private var mostrandoCamera = false
    @State private var mostrandoCorConstante = false
    /// Confiança que o SISTEMA reportou para a cor desta captura, 0…1.
    ///
    /// `nil` em todo caminho que não seja a rota de cor constante do iOS 18 —
    /// fototeca, arquivo, PDF e a câmera comum. Escrito num lugar só, dentro
    /// de `prepararConfirmacao`, justamente para não sobreviver de uma foto
    /// para a seguinte: uma confiança velha grudada numa foto nova seria pior
    /// que não medir nada.
    @State private var confiancaDaCaptura: Double?
    /// A foto de cor constante da captura atual, quando o enquadramento ainda é
    /// o dela. Ver `medicaoAindaVale`.
    @State private var imagemDeMedicao: CGImage?
    /// A mesma foto, guardada para o "desfazer recorte" poder devolvê-la.
    @State private var medicaoOriginal: CGImage?
    /// A confiança original, pelo mesmo motivo de `medicaoOriginal`.
    @State private var confiancaOriginal: Double?
    /// O par resolvido para o alvo que a pessoa confirmou.
    @State private var medicaoDoAlvo: CGImage?
    @State private var confiancaDoAlvoEscolhido: Double?
    /// A pessoa escolheu a rota de cor precisa e depois isolou a peça, o que
    /// desfaz a medição. A tela precisa dizer isso; ficar em silêncio seria
    /// deixá-la achar que a cor continua medida.
    @State private var perdeuAMedicaoAoIsolar = false
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
        case lendoArquivo, separandoPeca, analisandoLocal, analisandoNaNuvem

        var mensagem: String {
            switch self {
            case .lendoArquivo:     return frase("Reading the file…")
            case .separandoPeca:    return frase("Separating the garment…")
            case .analisandoLocal:  return frase("Reading the garment…")
            case .analisandoNaNuvem: return frase("Reading the garment…")
            }
        }

        /// Só quando a espera é longa por natureza. Aviso em espera curta vira
        /// ruído; ausência de aviso em espera longa parece travamento.
        var expectativa: String? {
            switch self {
            case .lendoArquivo, .analisandoLocal: return nil
            case .separandoPeca:
                return frase("This happens on this iPhone.")
            case .analisandoNaNuvem:
                return frase("The visual analysis runs on the server and usually takes a few seconds.")
            }
        }

        /// O que dizer quando os "poucos segundos" já passaram. O limite do
        /// pedido é 30 s; até lá a tela precisa continuar dizendo a verdade e
        /// lembrar que Close existe. `nil` onde a espera é curta por natureza.
        var avisoDeDemora: String? {
            switch self {
            case .lendoArquivo, .analisandoLocal: return nil
            case .separandoPeca:
                return frase("Still separating the garment on this iPhone. You can close and try a tighter photo.")
            case .analisandoNaNuvem:
                return frase("This is taking longer than usual. It stops on its own after 30 seconds — you can close and read the garment on this iPhone instead.")
            }
        }
    }
    @State private var erro: String?
    @State private var detectados: Set<String> = []
    /// As três telas do fluxo de preenchimento, nomeadas. O resultado abre
    /// e termina aqui mesmo, com nome, atributos e Add to Closet. A antiga
    /// Clothing Details repetia o mesmo conteúdo e foi removida deste fluxo.
    enum Etapa {
        /// Foto e preço. Nada de atributos: eles ainda não existem.
        case entrada
        /// Qual peça da foto é a que interessa.
        case confirmarAlvo
        /// O que o app leu, já marcado, para a pessoa corrigir.
        case atributos
        /// A leitura de mercado da peça confirmada, e o lugar onde ela é
        /// guardada no Closet.
        ///
        /// Esta etapa existiu até 24/08, saiu no `dee5957` junto com a
        /// reorganização do Add, e volta em 27/08 com o fluxo que o JP
        /// desenhou: "Show me the market, e no final da tela de show me the
        /// market o usuário tem a chance de adicionar ao closet ou não".
        /// Guardar deixa de ser o fim do preenchimento e passa a ser uma
        /// decisão tomada **depois** de ver o que o mercado diz — que é a
        /// ordem em que a informação chega para quem está comprando.
        case painel
    }

    /// Ver o comentário na tela de confirmação do alvo.
    static let mostraAlternativasDeAlvo = false

    /// Teto de cores por peça, fixado pelo JP em 26/08. Não é número
    /// arbitrário: bate com o `maxItems: 3` que o prompt da Luna já impõe, e
    /// a quarta cor deixaria de descrever a peça para descrever a estampa —
    /// que tem dimensão própria.
    static let tetoDeCores = 3

    /// Neutros, depois cromáticos. Dois blocos de cinco.
    static let ordemDasCores = [
        "preto", "cinza", "branco_cru", "terrosos", "outras_cores",
        "vermelho_rosa", "amarelo_laranja", "verde", "azul", "lilas_roxo",
    ]

    @State private var etapa = Etapa.entrada
    @State private var nomeDoArquivo: String?
    @State private var procedencia: [String] = []
    @State private var precoDigitado = ""
    @State private var miniaturaJPEG: Data?
    @State private var imagemPendente: CGImage?
    /// A foto como ela entrou, antes de qualquer recorte.
    @State private var imagemOriginal: CGImage?
    @State private var nomePendente: String?
    /// Há recorte a desfazer?
    private var fotoFoiRecortada: Bool {
        guard let atual = imagemPendente, let original = imagemOriginal
        else { return false }
        return atual !== original
    }
    @State private var opcoesDeAlvo: [MiniaturaLocal.OpcaoDeAlvo] = []
    @State private var alvoEscolhido: Int?
    @State private var descricaoDoAlvo = ""
    @State private var nomeDaPeca = ""
    /// As cores **na ordem de prioridade**: índice 0 é a cor principal.
    ///
    /// Existe separado de `detectados` porque `Set` não tem ordem, e ordem é
    /// justamente o que esta dimensão carrega: 1 é a cor que domina a peça, 2
    /// e 3 são as secundárias. A Luna já devolve ranqueado por área visível;
    /// aqui a ordem só é preservada e fica editável.
    @State private var coresPorPrioridade: [String] = []
    @State private var analiseConcluidaParaOAlvo = false
    @State private var mostrandoEditorDeRecorte = false
    @State private var pedindoConsentimentoDaNuvem = false
    @State private var imagemConfirmadaPendente: CGImage?
    @State private var dadosConfirmadosPendentes: Data?
    @State private var nomeConfirmadoPendente: String?
    @State private var descricaoConfirmadaPendente: String?
    @FocusState private var precoEmFoco: Bool
    @FocusState private var dicaDoAlvoEmFoco: Bool
    @FocusState private var nomeDaPecaEmFoco: Bool

    /// §29.5 — contexto condicional.
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

    private let tiposAceitos: [UTType] = [.pdf, .jpeg, .png, .heic, .heif, .tiff, .image]

    var body: some View {
        NavigationStack {
            Group {
                if lendo {
                    Carregando(mensagem: esperaAtual.mensagem,
                               expectativa: esperaAtual.expectativa,
                               avisoDeDemora: esperaAtual.avisoDeDemora)
                } else {
                    switch etapa {
                    case .entrada:       telaDeEntrada
                    case .confirmarAlvo: confirmacaoDoAlvo
                    case .atributos:     telaDeAtributos
                    case .painel:
                        RelatorioDaPeca(
                            termos: termosDoFormulario.filter { detectados.contains($0.id) },
                            precoAlvo: precoAlvo,
                            miniaturaJPEG: miniaturaJPEG,
                            pecaSalva: nil,
                            coresPorPrioridade: coresPorPrioridade,
                            apelido: nomeDaPeca,
                            todosOsTermos: termosDoFormulario,
                            selecao: $detectados,
                            aoConcluir: { encerrarFluxo() },
                            adicionarAoClosetNoCantoEsquerdo: true)
                            // Corrigir um chip aqui recria a view, e o `.task`
                            // dela recalcula o painel. NÃO chama a Luna de
                            // novo: reler a foto é outra ação e custa dinheiro.
                            // Corrigir o que ela leu é grátis e instantâneo.
                            .id(detectados)
                    }
                }
            }
            .navigationTitle(tituloDaEtapa)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if etapa == .entrada || lendo {
                            dismiss()
                        } else {
                            voltarUmaEtapa()
                        }
                    } label: {
                        Image(systemName: etapa == .entrada || lendo ? "xmark" : "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(etapa == .entrada || lendo ? "Close" : "Back")
                }
                if etapa == .confirmarAlvo, !lendo {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                mostrandoEditorDeRecorte = true
                            } label: {
                                Label("Adjust photo", systemImage: "crop")
                            }
                            if fotoFoiRecortada {
                                Button {
                                    guard let original = imagemOriginal else { return }
                                    let nome = nomePendente ?? "photo"
                                    Task {
                                        // Volta ao enquadramento da captura, e
                                        // com ele volta a medição.
                                        await prepararConfirmacao(
                                            original, nome: nome,
                                            medicao: medicaoOriginal,
                                            confianca: confiancaOriginal)
                                    }
                                } label: {
                                    Label("Undo crop", systemImage: "arrow.uturn.backward")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Photo options")
                    }
                }
            }
        }
        .task {
            avisoDeUso = await RegistroDeAnalises.shared.aviso()
            if ProcessInfo.processInfo.arguments.contains("-CanarioUITestDetalhes") {
                detectados = Set(["vestido", "preto"])
                // A rota determinística preenche o conjunto na mão, então
                // precisa preencher a ordem também -- senão a tela mostraria
                // preto marcado e sem número, que é um estado que a interação
                // real nunca produz.
                ordenarCoresPelaTaxonomia()
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
                guard let imagem else { return }
                Task { await prepararConfirmacao(imagem, nome: "camera photo") }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $mostrandoCorConstante) {
            CapturaDeCorConstante { resultado in
                mostrandoCorConstante = false
                guard let resultado else { return }
                medicaoOriginal = resultado.imagemDeMedicao
                confiancaOriginal = resultado.confianca
                Task {
                    await prepararConfirmacao(resultado.imagem,
                                              nome: "color-accurate photo",
                                              medicao: resultado.imagemDeMedicao,
                                              confianca: resultado.confianca)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $mostrandoEditorDeRecorte) {
            if let imagem = imagemPendente {
                EditorDeRecorte(imagem: imagem) { recortada in
                    mostrandoEditorDeRecorte = false
                    let nome = nomePendente ?? frase("cropped image")
                    let original = imagemOriginal ?? imagem
                    Task {
                        // Sem `medicao` e sem `confianca`: o recorte mudou a
                        // geometria, e o par deixou de se corresponder.
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

    // MARK: - Formulário & Confirmação de Alvo

    private var confirmacaoDoAlvo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Imagem Principal em Destaque (Fundo Azul Claro, sem borda)
                if let escolhida = opcaoEscolhida {
                    // 240, e não 300: com o card maior a tela pedia rolagem
                    // para chegar no botão que é a razão dela existir, o que o
                    // Davi apontou no teste de 27/08. A foto continua sendo o
                    // maior elemento da tela; ela só parou de empurrar a ação
                    // para fora.
                    PreviaDoAlvo(dados: escolhida.dados,
                                 id: escolhida.id,
                                 altura: 240,
                                 selecionada: false,
                                 corDeFundo: corDestaque,
                                 raio: Tokens.Raio.cartaoGrande)
                        .sombraDeCartao()
                        .accessibilityLabel("Selected photo of your item")
                }

                // 2. Seletor de Foto (No Background vs Full Photo)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose a photo")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Tokens.Cor.tinta)

                    HStack(spacing: 14) {
                        ForEach(opcoesDeAlvo) { opcao in
                            Button {
                                if alvoEscolhido != opcao.id {
                                    analiseConcluidaParaOAlvo = false
                                }
                                alvoEscolhido = opcao.id
                            } label: {
                                VStack(spacing: 6) {
                                    PreviaDoAlvo(dados: opcao.dados,
                                                 id: opcao.id,
                                                 altura: 96,
                                                 selecionada: alvoEscolhido == opcao.id,
                                                 corDeFundo: corDestaque,
                                                 raio: Tokens.Raio.cartao)
                                        .sombraDeCartao()

                                    Text(opcao.tipo == .primeiroPlano ? "No Background" : "Full photo")
                                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Tokens.Cor.tinta)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(opcao.rotulo.lowercased())")
                        }
                    }
                }

                // 3. Campo de Dica Opcional com Card Arredondado Neutro
                VStack(alignment: .leading, spacing: 8) {
                    Text("If there is more than 1 item in the photo, specify the target")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Tokens.Cor.tinta)

                    Divider()

                    TextField("Ex: Black Tank Top", text: $descricaoDoAlvo)
                        .font(.system(size: 15, design: .rounded))
                        .focused($dicaDoAlvoEmFoco)
                        .submitLabel(.done)
                        .onSubmit { dicaDoAlvoEmFoco = false }
                        .onChange(of: descricaoDoAlvo) { _, _ in
                            analiseConcluidaParaOAlvo = false
                        }
                }
                .padding(.horizontal, Tokens.Espaco.m)
                .padding(.vertical, 14)
                // Cinza do sistema, e não um preto a 5%: o cinza do sistema
                // acompanha o aparelho e o contraste, e o preto translúcido
                // fica sujo sobre qualquer fundo que não seja branco puro.
                .background(Tokens.Cor.superficie)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // O aviso do teto diário mora aqui, e não na tela de
                // resultado: este é o botão que gasta a próxima análise, e
                // aviso depois do gasto não é aviso, é relatório. O visual
                // novo tirou a linha da tela mas manteve o cálculo, então o
                // estado continuava sendo lido e ninguém mais o via.
                if let avisoDeUso {
                    LinhaInsumo(texto: avisoDeUso)
                }

                // 4. Botões de Ação Finais
                VStack(spacing: 12) {
                    Button {
                        Task { await confirmarAlvo() }
                    } label: {
                        Text("Analyze this item")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .background(Tokens.Cor.acao)
                            .clipShape(Capsule())
                            .sombraDeCartao()
                    }
                    .buttonStyle(.plain)
                    .disabled(opcaoEscolhida == nil)

                    Button {
                        cancelarConfirmacao()
                    } label: {
                        Text("Choose another photo")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Tokens.Cor.acao)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // A tela cabe inteira desde que o card da foto encolheu, mas a
        // `ScrollView` continuava aceitando o puxão e mostrando uma faixa
        // branca embaixo -- parecia conteúdo cortado que não existe.
        // `.basedOnSize` desliga o repique **só quando o conteúdo cabe**: com
        // Dynamic Type grande, quando ele deixa de caber, a rolagem volta
        // sozinha. Tirar a `ScrollView` daria a mesma tela estática e deixaria
        // o botão inalcançável em texto grande, que é caso de aceite da 1.2.
        .scrollBounceBehavior(.basedOnSize)
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

    /// Tela 1: a foto e as opções de entrada simplificadas.
    /// Tela 1: três entradas, centralizadas, e nada mais.
    ///
    /// O preço desceu para o fim da tela de atributos em 26/08 -- pedir um
    /// número antes de a pessoa ter visto a peça reconhecida era pedir cedo.
    /// Sobrou pouca coisa, e o JP foi direto: *"não precisa ser um slider que
    /// sobe tudo, só o necessário pra dar ao usuário as 3 opções"*.
    ///
    /// A `ScrollView` fica, e não por teimosia: em Dynamic Type grande o grupo
    /// passa da tela, e sem ela o último botão sairia cortado -- o que
    /// reprovaria justamente o aceite de acessibilidade que já passou. O
    /// `minHeight` resolve os dois pedidos ao mesmo tempo: com o texto no
    /// tamanho normal o conteúdo é alto como a tela e os `Spacer` o
    /// centralizam, sem nada para rolar; quando ele cresce, o scroll aparece
    /// sozinho porque passou a ser necessário.
    private var telaDeEntrada: some View {
        GeometryReader { area in
            ScrollView {
                VStack(spacing: Tokens.Espaco.g) {
                    Spacer(minLength: 0)
                    importador
                    Spacer(minLength: 0)
                    if let nomeDoArquivo {
                        LinhaInsumo(texto: "Loaded: \(nomeDoArquivo)")
                    }
                    avisoDePrivacidade
                }
                .padding(.horizontal, Tokens.Espaco.g)
                .padding(.vertical, Tokens.Espaco.m)
                .frame(maxWidth: .infinity, minHeight: area.size.height)
            }
        }
        // Sem barra de teclado: esta tela tem três botões e nenhum campo
        // desde que o preço desceu para a tela de atributos.
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Tela 3: o que o app leu, já marcado, para a pessoa corrigir.
    private var telaDeAtributos: some View {
        telaDeAtributosSemTeclado
            // O `intended price` desceu para esta tela em 26/08 e o teclado
            // dele veio sem saída: `decimalPad` não tem tecla de retorno, e a
            // barra de "Done" tinha ficado na tela de entrada, que já não tem
            // campo nenhum. Sem isto, quem digitasse o preço ficava com meia
            // tela coberta e nenhum jeito óbvio de fechar.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        precoEmFoco = false
                        nomeDaPecaEmFoco = false
                    }
                }
            }
    }

    private var telaDeAtributosSemTeclado: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if let miniaturaJPEG {
                    PreviaDoAlvo(dados: miniaturaJPEG,
                                 id: miniaturaJPEG.count,
                                 altura: 220,
                                 selecionada: true,
                                 corDeFundo: corDestaque,
                                 raio: 24)
                        .accessibilityLabel("Item being described")
                }
                if let erro {
                    CoberturaInsuficiente(
                        titulo: "No attributes were read",
                        explicacao: erro,
                        oQueTem: "You can select the attributes below and continue.")
                }
                atributos
                precoOpcional
                // A procedência desceu para cá, e recolhida.
                //
                // Ela ficava entre o nome e a grade, aberta, com quatro
                // bullets de evidência e o texto da marca -- e no teste em
                // aparelho de 27/08 o primeiro atributo tocável só apareceu
                // depois de duas telas de rolagem. O Davi foi direto: "a
                // pessoa precisa conseguir ir direto pros ajustes".
                //
                // A regra 3 continua valendo: saber de onde saiu cada
                // marcação não é opcional. O que muda é que ela deixa de ser
                // leitura OBRIGATÓRIA antes da ação e vira leitura disponível
                // a um toque, depois dela.
                if !procedencia.isEmpty { oQueLi }
                // O preenchimento não termina em "guardar": termina em ver.
                // Guardar passa a ser a decisão tomada na tela seguinte, com a
                // leitura de mercado à vista -- que é a ordem em que a
                // informação chega para quem está comprando.
                if !detectados.isEmpty {
                    Button {
                        precoEmFoco = false
                        nomeDaPecaEmFoco = false
                        etapa = .painel
                    } label: {
                        Text("Show me the market")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Tokens.Cor.acao)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Tokens.Espaco.m)
        }
    }

    private var importador: some View {
        VStack(spacing: Tokens.Espaco.m) {
            PhotosPicker(selection: $daFototeca, matching: .images,
                         photoLibrary: .shared()) {
                VStack(spacing: Tokens.Espaco.g) {
                    // Variante preenchida, como no Figma: o cartão é a ação
                    // principal da tela e o desenho vazado do contorno some
                    // dentro de 300 pt de superfície colorida.
                    Image(systemName: "photo.fill.on.rectangle.fill")
                        .font(.system(size: 76))
                        .foregroundStyle(Tokens.Cor.noite)
                    Text("Choose from Photos")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Tokens.Cor.noite)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(Tokens.Cor.ceu)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.cartaoGrande,
                                            style: .continuous))
                .sombraDeCartao()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose from Photos")

            // Some no simulador e em aparelho sem câmera, em vez de abrir nada.
            if CapturaDeCamera.disponivel {
                BotaoDeEntrada(titulo: "Take a photo", simbolo: "camera") {
                    erro = nil
                    mostrandoCamera = true
                }
            }
            // A rota de cor constante é uma ESCOLHA, não o caminho padrão:
            // ela dispara o flash sempre, e forçar isso em quem só quer
            // registrar a peça seria trocar um incômodo garantido por um ganho
            // que nem toda pessoa precisa. Some por completo onde não existe —
            // iOS 17, simulador, aparelho sem câmera traseira.
            if CapturaDeCorConstante.disponivel {
                BotaoDeEntrada(titulo: "Color-accurate photo",
                               simbolo: "camera.aperture") {
                    erro = nil
                    mostrandoCorConstante = true
                }
            }
            BotaoDeEntrada(titulo: "Choose a file or PDF", simbolo: "doc.badge.plus") {
                erro = nil
                mostrandoSeletor = true
            }
        }
    }

    /// Dizer o que acontece com a foto ANTES de a pessoa escolher uma é
    /// obrigação declarada na ficha e na política, não enfeite -- e é a única
    /// linha da tela que diz se a análise na nuvem está ligada neste build. O
    /// visual novo apagou a frase inteira; ela vive no rodapé, que foi onde a
    /// revisão de UX pediu que ficasse.
    private var avisoDePrivacidade: some View {
        Text(Supabase.analiseRemotaHabilitada
             ? "The app prepares the image on this iPhone and asks before sending a reduced, metadata-free copy for visual analysis. The original is not stored; only a local thumbnail remains if you save the item to Closet."
             : "The app reads the file on this iPhone. The original is not stored; only a local, metadata-free thumbnail remains if you save the item to Closet.")
            .font(Tokens.Fonte.miudo)
            .foregroundStyle(Tokens.Cor.tintaFraca)
            .multilineTextAlignment(.center)
    }

    private var oQueLi: some View {
        Cartao {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                    ForEach(procedencia, id: \.self) { LinhaInsumo(texto: $0) }
                    LinhaInsumo(texto: "Review every suggestion. Your confirmed selection is what counts.")
                }
                .padding(.top, Tokens.Espaco.s)
            } label: {
                Text("What I read from this file").font(Tokens.Fonte.secao)
            }
        }
    }

    private var atributos: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Describe your item attributes")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                if !detectados.isEmpty {
                    Button("Clear") { limparAtributos() }
                        .font(Tokens.Fonte.miudo)
                }
            }

            // Uma linha no lugar de um relatório. Ela diz as duas coisas que
            // a pessoa precisa saber para agir: já veio preenchido, e mexer é
            // esperado. O texto é do Davi, quase palavra por palavra.
            Text("We've selected what we identified — adjust anything that looks off.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)

            // O nome fica aqui, entre o convite e a grade, como no Figma: é o
            // único campo digitado da tela e some se ficar espremido entre
            // dois cartões.
            VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                HStack(spacing: Tokens.Espaco.s) {
                    TextField("Clothing name (optional)", text: $nomeDaPeca)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($nomeDaPecaEmFoco)
                        .onSubmit { nomeDaPecaEmFoco = false }
                    Image(systemName: "pencil")
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                        .accessibilityHidden(true)
                }
                Divider()
                Text("If left blank, Closet, links and spreadsheets use the confirmed category.")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }
            ForEach(dimensoes, id: \.self) { dimensao in
                VStack(alignment: .leading, spacing: 10) {
                    Text(Traducao.rotuloDaDimensao(dimensao))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    if dimensao == "cor" { legendaDaOrdemDeCor }
                    FlowLayout(espaco: dimensao == "cor" ? 8 : 12) {
                        ForEach(termosVisiveis(na: dimensao)) { termo in
                            BotaoDeAtributo(termo: termo,
                                            ativo: detectados.contains(termo.id),
                                            compacto: dimensao == "cor",
                                            prioridade: prioridade(de: termo),
                                            acao: { alternar(termo) })
                        }
                    }
                    Divider()
                }
            }
        }
    }

    /// A tela precisa dizer o que os números significam, e dizer de onde eles
    /// vieram. "1" sobre um círculo não se explica sozinho, e apresentar uma
    /// ordem calculada pela Luna como se fosse escolha da pessoa seria o tipo
    /// de silêncio que a §2 proíbe.
    private var legendaDaOrdemDeCor: some View {
        Text(coresPorPrioridade.isEmpty
             ? "Pick up to \(Self.tetoDeCores), in order — the first one is the main color."
             : "1 is the main color, 2 and 3 are secondary. Tap a color again to remove it.")
            .font(Tokens.Fonte.miudo)
            .foregroundStyle(Tokens.Cor.tintaFraca)
    }

    private func prioridade(de termo: Termo) -> Int? {
        guard termo.dimensao == "cor",
              let posicao = coresPorPrioridade.firstIndex(of: termo.id)
        else { return nil }
        return posicao + 1
    }

    /// Marcar e desmarcar. Cor tem regra própria porque é a única dimensão em
    /// que a ORDEM é informação: as outras respondem "é isto?", e cor responde
    /// "nesta ordem".
    private func alternar(_ termo: Termo) {
        guard termo.dimensao == "cor" else {
            detectados = FormularioDaPeca.alternar(termo, em: detectados,
                                                   termos: termosDoFormulario)
            sincronizarCores()
            return
        }
        if let posicao = coresPorPrioridade.firstIndex(of: termo.id) {
            coresPorPrioridade.remove(at: posicao)
            detectados.remove(termo.id)
            return
        }
        // No teto, o toque não faz nada em silêncio -- e silêncio numa tela de
        // toque é indistinguível de defeito. A legenda acima já diz o teto
        // antes do toque, que é o momento em que a informação serve.
        guard coresPorPrioridade.count < Self.tetoDeCores else { return }
        coresPorPrioridade.append(termo.id)
        detectados = FormularioDaPeca.podar(detectados.union([termo.id]),
                                            termos: termosDoFormulario)
    }

    private func limparAtributos() {
        detectados.removeAll()
        coresPorPrioridade.removeAll()
    }

    /// A ordem e o conjunto têm que dizer a mesma coisa. Sem isto, uma cor
    /// removida pela poda continuaria com número na tela — e número na tela
    /// que não corresponde a nada salvo é exatamente o que este projeto foi
    /// construído para não fazer.
    private func sincronizarCores() {
        coresPorPrioridade.removeAll { !detectados.contains($0) }
    }

    /// Ordem de recurso, para quando a leitura não ranqueia.
    ///
    /// A leitura local sai do texto do arquivo, e texto não diz proporção:
    /// "vestido preto e branco" não informa qual das duas domina. Então a
    /// ordem aqui é a da taxonomia e a pessoa reordena tocando. Só a Luna
    /// ranqueia por área visível, e é por isso que o caminho dela usa
    /// `coresSugeridas` em vez desta função.
    private func ordenarCoresPelaTaxonomia() {
        let cores = termosDoFormulario
            .filter { $0.dimensao == "cor" && detectados.contains($0.id) }
            .map(\.id)
        coresPorPrioridade = Array(cores.prefix(Self.tetoDeCores))
        for excedente in cores.dropFirst(Self.tetoDeCores) {
            detectados.remove(excedente)
        }
    }

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
            if !vistas.contains(t.dimensao) { vistas.append(t.dimensao) }
        }
        return vistas
    }

    private func termosVisiveis(na dimensao: String) -> [Termo] {
        let encontrados = termosDoFormulario
            .filter { $0.dimensao == dimensao }
            .filter { $0.id != "trico_croche" }
        // Cor não sai na ordem do servidor. Ela chegava Blue, Black, White,
        // Red / Green, Earth, Gray, Yellow / Purple, Other -- com os neutros
        // espalhados no meio dos cromáticos, o que obriga a varrer a grade
        // inteira para achar cinza. Neutros na primeira fileira, cromáticos na
        // segunda: são exatamente cinco e cinco, e é a arrumação do Figma.
        if dimensao == "cor" {
            return Self.ordemDasCores.compactMap { id in
                encontrados.first { $0.id == id }
            } + encontrados.filter { !Self.ordemDasCores.contains($0.id) }
        }
        guard dimensao == "estampa" else { return encontrados }
        let prioridade = [
            "animal_print", "floral", "listra", "xadrez", "geometrica",
            "conversacional", "liso",
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

    // MARK: - Leitura e Fluxos

    private func processarDaFototeca(_ item: PhotosPickerItem) async {
        daFototeca = nil
        esperaAtual = .lendoArquivo
        lendo = true
        erro = nil
        guard let dados = try? await item.loadTransferable(type: Data.self),
              let imagem = MiniaturaLocal.imagem(de: dados) else {
            erro = frase("I couldn't open this photo.")
            etapa = .entrada
            lendo = false
            return
        }
        await prepararConfirmacao(imagem, nome: "photo library image")
    }

    /// O PAR SÓ VALE ENQUANTO O ENQUADRAMENTO NÃO MUDA.
    ///
    /// `medicao` é a foto de cor constante da mesma cena que `imagem`. As duas
    /// só se correspondem pixel a pixel enquanto ninguém mexe na geometria:
    /// recortar a exibida deixa a de medição no enquadramento antigo, e medir
    /// cor num pedaço diferente do que a pessoa escolheu seria pior do que não
    /// medir. Por isso o recorte entra aqui com `medicao: nil`, e o desfazer
    /// devolve a original.
    ///
    /// O padrão `nil` de todos os três é o portão: quem entra por fototeca,
    /// arquivo ou câmera comum apaga a medida anterior sem precisar lembrar.
    private func prepararConfirmacao(_ imagem: CGImage, nome: String,
                                     recorteDe original: CGImage? = nil,
                                     medicao: CGImage? = nil,
                                     confianca: Double? = nil) async {
        imagemDeMedicao = medicao
        confiancaDaCaptura = confianca
        esperaAtual = .separandoPeca
        lendo = true
        erro = nil
        procedencia = []
        detectados = []
        analiseConcluidaParaOAlvo = false
        let opcoes = await MiniaturaLocal.opcoesDeAlvo(de: imagem)
        guard !opcoes.isEmpty else {
            erro = frase("I could not prepare this image. Choose another photo or file.")
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
        guard !termos.isEmpty else {
            erro = frase("The item taxonomy is not available yet. Go back and try again; no visual-analysis credit was used.")
            return
        }
        guard let original = imagemPendente, let escolha = opcaoEscolhida else { return }
        let imagem: CGImage?
        // A MEDIÇÃO SÓ ACOMPANHA A FOTO INTEIRA, E ISSO É DELIBERADO.
        //
        // "Peça isolada" não é um recorte retangular: o Vision devolve uma
        // máscara, e a máscara nasceu da foto natural. Aplicá-la aos pixels da
        // foto de cor constante exigiria que o Vision achasse as MESMAS
        // instâncias, na mesma ordem, nas duas versões da cena — e isso não é
        // garantido por nada. Medir cor num recorte que talvez não seja o que a
        // pessoa escolheu é pior do que não medir.
        //
        // Então: foto inteira mantém a cor medida; peça isolada volta ao
        // comportamento de sempre (sugestão que a pessoa confirma). A tela diz
        // isso em vez de deixar a diferença invisível.
        let medicao: CGImage?
        let confiancaDoAlvo: Double?
        switch escolha.tipo {
        case .primeiroPlano:
            imagem = MiniaturaLocal.imagem(de: escolha.dados)
            medicao = nil
            confiancaDoAlvo = nil
        case .fotoCompleta:
            imagem = original
            medicao = imagemDeMedicao
            confiancaDoAlvo = imagemDeMedicao == nil ? nil : confiancaDaCaptura
        }
        guard let imagem else {
            erro = frase("I could not open the selected item. Choose another option.")
            return
        }
        medicaoDoAlvo = medicao
        confiancaDoAlvoEscolhido = confiancaDoAlvo
        perdeuAMedicaoAoIsolar = escolha.tipo == .primeiroPlano
            && imagemDeMedicao != nil

        let nome = nomePendente ?? frase("selected image")
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
        let nome = nomeConfirmadoPendente ?? frase("selected image")
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

    private var tituloDaEtapa: String {
        switch etapa {
        case .entrada:       return frase("Analyze an item")
        case .confirmarAlvo: return frase("Confirm your item")
        case .atributos:     return frase("Fill the info")
        case .painel:        return frase("Market panel")
        }
    }

    private func voltarUmaEtapa() {
        switch etapa {
        case .entrada:
            break
        case .confirmarAlvo:
            cancelarConfirmacao()
        case .atributos:
            etapa = .confirmarAlvo
        case .painel:
            etapa = .atributos
        }
    }

    /// A peça foi guardada e o fluxo acabou. Volta ao começo pronto para a
    /// próxima, em vez de deixar a pessoa desandar as etapas uma a uma.
    private func encerrarFluxo() {
        cancelarConfirmacao()
        detectados = []
        coresPorPrioridade = []
        nomeDaPeca = ""
        precoDigitado = ""
        procedencia = []
        nomeDoArquivo = nil
        miniaturaJPEG = nil
        erro = nil
        aoSalvar?()
        dismiss()
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

    private func analisarImagemConfirmada(_ imagem: CGImage, nome: String,
                                          dadosParaNuvem: Data?,
                                          descricaoDoAlvo: String?) async {
        esperaAtual = dadosParaNuvem == nil ? .analisandoLocal : .analisandoNaNuvem
        lendo = true
        erro = nil
        procedencia = []
        nomeDoArquivo = nome
        let leitura = await LeitorDeArquivo.ler(
            imagem, imagemParaCor: medicaoDoAlvo,
            confiancaDaCaptura: confiancaDoAlvoEscolhido)
        let marcas = Importacao.marcasNoTexto(leitura.texto)

        if let dadosParaNuvem {
            await RegistroDeAnalises.shared.registrar()
            avisoDeUso = await RegistroDeAnalises.shared.aviso()
            do {
                let analise = try await Supabase.shared.analisarPeca(
                    dadosParaNuvem, alvo: descricaoDoAlvo)
                if analise.alvoAmbiguo {
                    detectados = []
                    coresPorPrioridade = []
                    procedencia = analise.decisionEvidence.map {
                        "Why the target was ambiguous: \($0)"
                    }
                    erro = frase("The visual analysis found more than one plausible garment. Choose the category and attributes yourself, or try a tighter photo.")
                } else {
                    let existentes = Set(termos.map(\.id))
                    detectados = FormularioDaPeca.podar(
                        analise.idsSugeridos(existentes: existentes),
                        termos: termos)
                    // A ordem vem da Luna, que ranqueia por área visível. É a
                    // única fonte de ranqueamento que existe no sistema.
                    coresPorPrioridade = analise
                        .coresSugeridas(existentes: existentes)
                        .filter { detectados.contains($0) }
                        .prefix(Self.tetoDeCores)
                        .map { $0 }
                    let porId = Dictionary(uniqueKeysWithValues: termos.map { ($0.id, $0) })
                    let lidos = detectados.compactMap { porId[$0] }
                        .sorted { ($0.dimensao, $0.id) < ($1.dimensao, $1.id) }
                        .map(Traducao.rotuloExibido)
                    procedencia = [
                        "Visual analysis suggested: \(lidos.joined(separator: ", ")).",
                    ]
                    if !analise.decisionEvidence.isEmpty {
                        procedencia.append(
                            frase("Visible evidence:\n")
                            + analise.decisionEvidence
                                .map { "•  \($0)" }
                                .joined(separator: "\n"))
                    }
                    if !analise.additionalVisualAttributes.isEmpty {
                        procedencia.append(
                            frase("Also observed, outside the market taxonomy: ")
                            + analise.additionalVisualAttributes.joined(separator: ", ") + ".")
                    }
                    if !FormularioDaPeca.temCategoria(detectados, termos: termos) {
                        detectados = []
                        coresPorPrioridade = []
                        erro = frase("The analysis returned an invalid category. Choose the attributes manually.")
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
            procedencia.append(frase("Brand text recognized on device: \(marcas.joined(separator: ", ")). This is context, not proof of model or material."))
        }
        // A pessoa pediu cor precisa e depois isolou a peça. A medição não
        // acompanha o recorte (ver `confirmarAlvo`), e ela precisa saber disso
        // agora, na tela onde ainda dá para voltar e escolher a foto inteira --
        // não depois, olhando um Closet que ela acha medido e não é.
        if perdeuAMedicaoAoIsolar {
            procedencia.append(frase("The measured color applies to the whole photo. You isolated the item, so the color here was read the usual way — go back and pick the full photo if you want the measured one."))
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
        ordenarCoresPelaTaxonomia()
        procedencia = achado.procedencia
        if let mensagem {
            erro = mensagem
        } else if !reconheceuPeca {
            // Com a rota paga desligada a leitura é só o texto impresso na
            // imagem, e foto de roupa quase nunca tem texto. A frase antiga
            // valia para os dois casos e por isso um build de colaborador --
            // que o SETUP.md manda deixar com REMOTE_ANALYSIS_ENABLED = NO --
            // parecia defeito de análise. Aqui a tela passa a dizer qual dos
            // dois aconteceu.
            erro = Supabase.analiseRemotaHabilitada
                ? "I read what I could from the image, but not the category. Pick it below and the rest stays as read."
                : "Cloud visual analysis is off in this build, so I only read text printed on the image — a garment photo usually has none. Pick the attributes below; nothing failed."
        }
    }

    private func processar(_ resultado: Result<[URL], Error>) async {
        guard case .success(let urls) = resultado, let url = urls.first else { return }
        esperaAtual = .lendoArquivo
        lendo = true
        erro = nil
        guard let imagem = MiniaturaLocal.imagem(doArquivo: url) else {
            erro = frase("I couldn't open this file. Choose a JPG, PNG, HEIC or PDF.")
            etapa = .entrada
            lendo = false
            return
        }
        await prepararConfirmacao(imagem, nome: url.lastPathComponent)
    }
}

/// As duas entradas secundárias da tela de análise.
///
/// Nasceram como dois blocos idênticos copiados um do outro, e a cópia já
/// tinha começado a divergir -- altura, peso da fonte e espaçamento do ícone
/// eram escritos duas vezes. Uma view, e a próxima entrada nasce igual às
/// outras sem ninguém precisar lembrar das medidas.
private struct BotaoDeEntrada: View {
    /// `LocalizedStringKey`, e não `String`, por um motivo medido: com
    /// `String` o Xcode não enxerga o literal do lado de quem chama, e o
    /// primeiro build depois desta view **podou "Take a photo" e "Choose a
    /// file or PDF" do String Catalog**. Os botões continuavam funcionando --
    /// e tinham deixado de ser traduzíveis, sem erro nenhum.
    let titulo: LocalizedStringKey
    let simbolo: String
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: Tokens.Espaco.s) {
                Image(systemName: simbolo)
                    .font(.system(size: 18, weight: .semibold))
                Text(titulo)
                    .font(.system(.callout, design: .rounded).weight(.bold))
            }
            .foregroundStyle(Tokens.Cor.noite)
            .frame(maxWidth: .infinity)
            // 54 é confortável e passa dos 44 pt mínimos da HIG; `minHeight`
            // em vez de `height` para o botão crescer com Dynamic Type em vez
            // de cortar o rótulo.
            .frame(minHeight: 54)
            .background(Tokens.Cor.ceu)
            .clipShape(Capsule())
            .sombraDeCartao()
        }
        .buttonStyle(.plain)
    }
}

/// Editor manual.
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

/// Pré-visualização com suporte customizado a fundo e raio de cantos.
private struct PreviaDoAlvo: View {
    let dados: Data
    let id: Int
    let altura: CGFloat
    let selecionada: Bool
    /// Neutro por padrão: quem esquecer de passar a cor recebe o substrato, e
    /// não uma superfície de sistema que muda com o tema. Cor de moldura de
    /// peça não é decoração, é condição de medição.
    var corDeFundo: Color = Tokens.Cor.substratoDaPeca
    var raio: CGFloat = Tokens.Raio.cartao

    @State private var imagem: UIImage?

    private var compacta: Bool { altura < 160 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: raio, style: .continuous)
                .fill(corDeFundo)
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFit()
                    .padding(Tokens.Espaco.s)
            } else {
                ProgressView()
            }
        }
        .frame(width: compacta ? 96 : nil)
        .frame(maxWidth: compacta ? nil : .infinity)
        .frame(height: altura)
        .overlay {
            if selecionada && compacta {
                RoundedRectangle(cornerRadius: raio, style: .continuous)
                    .stroke(Color.blue, lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
        .task(id: id) {
            imagem = nil
            imagem = await MiniaturaParaTela.imagem(de: dados)
        }
    }
}

/// Chips de seleção.
struct FluxoDeChips: View {
    let termos: [Termo]
    let todos: [Termo]
    @Binding var marcados: Set<String>

    var body: some View {
        FlowLayout(espaco: Tokens.Espaco.s) {
            ForEach(termos) { termo in
                let ativo = marcados.contains(termo.id)
                ChipDeAtributo(termo: termo, ativo: ativo) {
                    marcados = FormularioDaPeca.alternar(
                        termo, em: marcados, termos: todos)
                }
            }
        }
    }
}

private struct ChipDeAtributo: View {
    let termo: Termo
    let ativo: Bool
    let acao: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Tokens.Espaco.xs) {
                if let rgb = CorDaPeca.rgbRepresentativo(de: termo.id) {
                    Circle()
                        .fill(Color(red: rgb.0, green: rgb.1, blue: rgb.2))
                        .overlay(Circle().strokeBorder(Tokens.Cor.borda, lineWidth: 0.5))
                        .frame(width: 12, height: 12)
                }
                Text(Traducao.rotuloExibido(termo))
            }
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
