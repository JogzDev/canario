import Charts
import PhotosUI
import SwiftUI
import UIKit

/// Leitura de uma peça a partir dos atributos confirmados pelo usuário (§29).
///
/// **A ordem desta tela é a da §29, e ela é deliberada:** primeiro o parágrafo
/// dos similares (o substituto aprovado da previsão, §5), depois os similares,
/// depois cada atributo, e só então o número do conjunto (§22, K5).
///
/// O conjunto vem por último de propósito. Um número único no topo é lido como
/// veredito; o mesmo número depois das partes é lido como resumo delas. E ele
/// se cala quando os atributos discordam entre si — ver `Cluster.haDirecao`.
struct RelatorioDaPeca: View {
    let termos: [Termo]
    /// Preço que o usuário pretende praticar, se informou. §29.5 chama isso de
    /// contexto condicional, e a §5 autoriza o percentil de preço que sai dele.
    var precoAlvo: Double?
    /// Prévia local, já sem metadados. Só é persistida se o usuário guardar.
    var miniaturaJPEG: Data?
    /// Quando aberto pelo Closet, evita salvar uma duplicata da mesma peça.
    var pecaSalva: PecaSalva? = nil
    /// As cores em ordem de prioridade, vindas da tela de atributos. Vazio
    /// quando a tela é aberta de um lugar que não tem essa informação — e aí a
    /// peça é guardada sem ordem, que é diferente de guardada com a ordem
    /// errada.
    var coresPorPrioridade: [String] = []
    /// O nome que a pessoa deu à peça na tela anterior.
    ///
    /// Chega vazio quando a tela é aberta pela busca ou pelo Closet, onde não
    /// há nome a carregar. Existe porque guardar a peça passou a acontecer
    /// AQUI, e não no preenchimento: sem este campo, o nome digitado uma tela
    /// atrás seria descartado no momento exato de salvar, sem aviso.
    var apelido: String = ""
    /// A taxonomia inteira, para os chips de correção no topo. Vazia quando a
    /// tela é aberta de um lugar onde corrigir não faz sentido -- o Closet, por
    /// exemplo, onde a peça já foi salva com os atributos confirmados.
    var todosOsTermos: [Termo] = []
    /// Ligação para a seleção, quando ela é editável aqui.
    ///
    /// Existe porque separar "corrigir" de "ler o resultado" em duas telas
    /// quebraria o laço curto que é o valor do produto: mudar `saia` para
    /// `short` e ver os similares mudarem. Com os chips aqui, a separação de
    /// telas fica e o laço também.
    var selecao: Binding<Set<String>>? = nil
    /// Linguagem usada na busca. Preserva "vestido de bolinha" sem alterar os
    /// ids `vestido` + `geometrica` que alimentam o cálculo.
    var descricaoAmigavel: String? = nil
    /// Como sair do fluxo depois de guardar, quando existe um fluxo do qual
    /// sair. Só o import passa isto; aberta pelo Closet ou pela busca, a tela
    /// não tem etapas atrás de si e o rótulo "Saved" basta.
    ///
    /// Existe porque guardar a peça deixava a pessoa presa no painel: era
    /// preciso voltar passo a passo até o começo. "Deveria sair direto."
    var aoConcluir: (() -> Void)? = nil
    /// No fluxo Add, Clothing Details ocupa a tela inteira e a ação principal
    /// pedida pelo teste de uso mora no canto superior esquerdo.
    var adicionarAoClosetNoCantoEsquerdo = false

    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var coberturas: [String: Cobertura] = [:]
    @State private var similares: Similares.Resposta?
    @State private var cluster: Cluster.Resposta?
    @State private var serie: SerieDoCluster.Resposta?
    @State private var erroDosSimilares: String?
    @State private var erroDoCluster: String?
    @State private var erroDaSerie: String?
    @State private var carregandoSimilares = true
    @State private var carregandoCluster = true
    @State private var carregandoSerie = true
    @State private var carregando = true
    @State private var erro: String?
    /// nil = ainda não tentou; true = guardada; false = a lista está no teto.
    @State private var guardada: Bool?
    @State private var rejeitouSimilares = false
    @State private var fotoEscolhida: PhotosPickerItem?
    @State private var miniaturaDaPeca: UIImage?
    @State private var processandoFoto = false
    @State private var erroDaFoto: String?
    @State private var pecaGuardadaNestaTela: PecaSalva?

    /// Guarda a peça em "Minhas peças" (§27, A10).
    ///
    /// Grava só os `termoIds` — o que o usuário confirmou. Nada do que está na
    /// tela abaixo: índice, estado e similares são recomputados do dado de hoje
    /// quando ela for reaberta. É essa a diferença entre lista de trabalho e
    /// armário, e a §34 exclui o segundo.
    @ViewBuilder
    private var botaoDeGuardar: some View {
        if pecaSalva != nil {
            // Peça aberta a partir do Closet já está salva, e a etiqueta
            // "Saved" no canto não informava nada -- a pessoa chegou aqui
            // clicando nela dentro do próprio armário. Ocupava o único lugar
            // da barra sem dizer nada que o contexto já não dissesse.
            EmptyView()
        } else {
            switch guardada {
        case true:
            // Guardada. Se veio de um fluxo, o mesmo canto que dizia "Saved"
            // passa a ser a saída dele -- um toque, não três. Quem quiser
            // continuar lendo o painel continua: nada some da tela.
            if let aoConcluir {
                Button("Done", systemImage: "checkmark", action: aoConcluir)
                    .labelStyle(.titleAndIcon)
            } else {
                Label("Saved", systemImage: "archivebox.fill")
                    .labelStyle(.titleAndIcon)
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(.secondary)
            }
        case false:
            // O teto é dito, e não engole a peça em silêncio.
            Text("Closet full (\(PecasSalvas.teto))")
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(.secondary)
        case nil:
            Button {
                Task {
                    let nova = PecaSalva(
                        apelido: apelido.trimmingCharacters(in: .whitespacesAndNewlines),
                        termoIds: termos.map(\.id), precoAlvo: precoAlvo,
                        similaresRejeitados: rejeitouSimilares ? true : nil,
                        coresPorPrioridade: coresPorPrioridade.isEmpty
                            ? nil : coresPorPrioridade)
                    guardada = await PecasSalvas.shared.salvar(
                        nova, miniaturaDados: miniaturaJPEG)
                    if guardada == true { pecaGuardadaNestaTela = nova }
                }
            } label: {
                Label(adicionarAoClosetNoCantoEsquerdo ? "Add to Closet" : "Save",
                      systemImage: "archivebox")
            }
            .disabled(termos.isEmpty)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else {
                    // A ordem mudou em 27/08, e o motivo está medido.
                    //
                    // A foto NÃO aparecia neste caminho: `fotoDaPeca` só
                    // desenhava com `pecaSalva != nil`, ou seja, só vindo do
                    // Closet. Quem acabava de fotografar a peça chegava ao
                    // painel dela sem vê-la. E o nome que a tela anterior pede
                    // não aparecia em lugar nenhum.
                    //
                    // Os similares subiram porque a reclamação nº 1 da revisão
                    // de 20/08 continua na PENDENCIAS: "ter os similares logo
                    // em seguida e com foto! ... acho que é a parte mais legal
                    // da nossa ferramenta". Eles eram o quinto bloco.
                    //
                    // A §29 continua respeitada: ela manda o parágrafo do
                    // painel vir antes do número do conjunto, e vem -- Result
                    // antes de By attribute, e o Combined reading por último.
                    // O que mudou de lugar é a foto e a vitrine, não a ordem
                    // da leitura.
                    heroiDaPeca
                    vitrineDeSimilares
                    resumo
                    porAtributo
                    if pecaSalva != nil { editorialDosAtributos }
                    blocoDoCluster
                    blocoDoHistorico
                    if let selecao, !todosOsTermos.isEmpty {
                        chipsDeCorrecao(selecao)
                    }
                }
            }
            .padding(Tokens.Espaco.m)
        }
        // O painel de uma peça pertence ao território claro, mas não ao branco
        // padrão do sistema. Era a única tela desse percurso que descartava o
        // céu da marca ao ser empurrada pelo Closet e, por isso, parecia outro
        // app. O fundo e a barra são declarados juntos para não haver um frame
        // branco entre a foto e a área segura durante a navegação.
        .background(Tokens.Cor.ceu.ignoresSafeArea())
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Tokens.Cor.ceuFixo, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .task { await carregar() }
        .task(id: pecaSalva?.miniaturaArquivo) { await carregarMiniaturaDaPeca() }
        .onAppear { rejeitouSimilares = pecaSalva?.similaresRejeitados ?? false }
        .onChange(of: fotoEscolhida) { _, item in
            guard let item else { return }
            Task { await substituirFoto(item) }
        }
        .toolbar {
            if adicionarAoClosetNoCantoEsquerdo {
                ToolbarItem(placement: .topBarLeading) { botaoDeGuardar }
            } else {
                ToolbarItem(placement: .topBarTrailing) { botaoDeGuardar }
            }
        }
    }

    // MARK: - Vitrine

    /// A fileira de similares no alto, e a porta para todos eles.
    ///
    /// Substitui a lista vertical que ficava em quinto lugar. O motivo está na
    /// PENDENCIAS desde 20/08: *"ter os similares logo em seguida e com foto!
    /// Não tô mais vendo eles e acho que é a parte mais legal da nossa
    /// ferramenta."* Uma lista de cartões altos empurrava tudo para baixo; uma
    /// fileira mostra quatro de relance e cabe acima da dobra.
    ///
    /// **Nada de honestidade se perde aqui, ela muda de lugar.** O quanto casou
    /// e o que faltou, a grade de tamanhos, a remarcação e o link continuam
    /// inteiros -- na tela que o chevron abre, onde há espaço para eles serem
    /// lidos em vez de espremidos numa miniatura de 96 pt.
    @ViewBuilder
    private var vitrineDeSimilares: some View {
        if carregandoSimilares {
            secaoCarregando("Similar pieces")
        } else if let erroDosSimilares {
            falhaLocal(titulo: "Similar pieces", mensagem: erroDosSimilares)
        } else if let s = similares, let r = s.resumo,
                  !s.pecas.filter(Similares.podeExibir).isEmpty {
            let visiveis = s.pecas.filter(Similares.podeExibir)
            VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                NavigationLink {
                    TodosOsSimilares(resumo: r, pecas: visiveis,
                                     atributos: termos, precoAlvo: precoAlvo,
                                     nomeDaPeca: nomeExibido)
                } label: {
                    HStack {
                        Text("Show similar pieces").font(Tokens.Fonte.secao)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show all \(visiveis.count) similar pieces")

                // O critério continua dito ANTES da vitrine: quantos casaram e
                // com quantos atributos. Sem ele a fileira parece um resultado
                // exato, e quase nunca é.
                LinhaInsumo(texto: Similares.criterio(r))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Tokens.Espaco.m) {
                        ForEach(visiveis.prefix(8)) { peca in
                            MiniaturaDeSimilar(peca: peca, pedidos: termos)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let leitura = Similares.leituraDoPreco(r, alvo: precoAlvo) {
                    Cartao {
                        Text("Where your price falls")
                            .font(Tokens.Fonte.miudo.weight(.semibold))
                        Text(leitura).font(Tokens.Fonte.apoio)
                    }
                }
            }
        } else if let s = similares, let r = s.resumo {
            // Zero similares tem texto próprio e não some da tela.
            Cartao {
                Text("Similar pieces").font(Tokens.Fonte.secao)
                LinhaInsumo(texto: Similares.criterio(r))
            }
        }
    }

    // MARK: - Herói

    /// A peça, grande, com o nome que a pessoa deu.
    ///
    /// Ela não existia neste caminho. `fotoDaPeca` só desenhava vindo do
    /// Closet, então quem acabava de fotografar chegava ao painel da própria
    /// peça sem vê-la -- e o nome digitado uma tela antes não aparecia em
    /// canto nenhum do app até a peça ser guardada.
    private var heroiDaPeca: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.m) {
            // A moldura é NEUTRA, não o céu da marca. Este é o maior retrato
            // de peça do app (300 pt) e era o pior caso da indução cromática
            // apontada na revisão de 05/09; ver `SubstratoDaPeca`.
            SubstratoDaPeca {
                if let imagem = imagemDoHeroi {
                    Image(uiImage: imagem)
                        .resizable()
                        .scaledToFit()
                } else {
                    // Sem foto o quadro não vira buraco: ele diz o que falta.
                    PecaSemFoto(legenda: "No photo for this item")
                }
            }
            .frame(height: 300)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(imagemDoHeroi == nil
                                ? "This item has no photo" : "Photo of \(nomeExibido)")

            Text(nomeExibido)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Tokens.Cor.azulMarca)
                .fixedSize(horizontal: false, vertical: true)

            // Os atributos confirmados como subtítulo, e não mais como cartão
            // de lista. Eles são a legenda da peça, não uma seção -- e a
            // correção continua a um toque, no fim da tela.
            // Quando ninguém nomeou a peça, o título cai na categoria -- e
            // aí a legenda não pode começar repetindo a mesma palavra logo
            // abaixo ("Dress" / "Dress · Black"). Nesse caso a categoria sai da
            // legenda, que passa a dizer só o que o título ainda não disse.
            if !atributosDaLegenda.isEmpty {
                Text(atributosDaLegenda.map(Traducao.rotuloExibido)
                        .joined(separator: " · "))
                    .font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if pecaSalva != nil { trocarFoto }
        }
    }

    /// A foto do herói vem de onde ela existir: do fluxo de importação, que
    /// carrega os bytes em memória, ou do Closet, que já a tem em disco.
    private var imagemDoHeroi: UIImage? {
        if let miniaturaDaPeca { return miniaturaDaPeca }
        guard let miniaturaJPEG else { return nil }
        return UIImage(data: miniaturaJPEG)
    }

    /// Os atributos da legenda, sem repetir o que o título já diz.
    private var atributosDaLegenda: [Termo] {
        guard nomeVeioDaCategoria else { return termos }
        return termos.filter { $0.dimensao != "categoria" }
    }

    private var nomeVeioDaCategoria: Bool {
        let proprio = NomeCompartilhavel.apelidoValido(
            apelido.trimmingCharacters(in: .whitespacesAndNewlines))
        let doCloset = pecaSalva.flatMap {
            NomeCompartilhavel.apelidoValido($0.apelido)
        }
        return proprio == nil && doCloset == nil
    }

    /// O nome da peça: o que a pessoa digitou, ou a categoria confirmada.
    ///
    /// Cair na categoria e não em "Item" é o mesmo critério que o Closet já
    /// usa, e é o que faz o título dizer algo mesmo quando ninguém nomeou.
    private var nomeExibido: String {
        let apelidoLimpo = apelido.trimmingCharacters(in: .whitespacesAndNewlines)
        if let valido = NomeCompartilhavel.apelidoValido(apelidoLimpo) { return valido }
        if let salva = pecaSalva,
           let doCloset = NomeCompartilhavel.apelidoValido(salva.apelido) {
            return doCloset
        }
        if let categoria = termos.first(where: { $0.dimensao == "categoria" }) {
            return Traducao.rotuloExibido(categoria)
        }
        return termos.isEmpty ? "Item" : Traducao.rotuloExibido(termos[0])
    }

    /// Atalho pedido para o Closet: cada atributo abre a mesma série editorial
    /// auditável usada em Trends, sem criar uma leitura especial por peça.
    private var editorialDosAtributos: some View {
        Cartao {
            Text("How the press is covering these attributes")
                .font(Tokens.Fonte.secao)
            Text("Open an attribute to see Brazilian and international coverage, weekly counts and contributing publications.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            ForEach(termos) { termo in
                NavigationLink {
                    RelatorioDoTermo(termo: termo)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Traducao.rotuloExibido(termo))
                                .foregroundStyle(.primary)
                            Text(Traducao.rotuloDaDimensao(termo.dimensao))
                                .font(Tokens.Fonte.miudo)
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A edição visual mora no detalhe, onde há contexto para entender qual
    /// peça será alterada. A foto em si subiu para o herói; aqui ficou só a
    /// ação, que é do Closet e não do fluxo de importação — no fluxo a foto
    /// acabou de ser escolhida e trocar significa voltar, não editar.
    private var trocarFoto: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
            if let erroDaFoto {
                Text(erroDaFoto).font(Tokens.Fonte.miudo).foregroundStyle(.secondary)
            }
            PhotosPicker(selection: $fotoEscolhida, matching: .images) {
                HStack(spacing: Tokens.Espaco.xs) {
                    if processandoFoto { ProgressView().controlSize(.small) }
                    Label(miniaturaDaPeca == nil ? "Add photo" : "Replace photo",
                          systemImage: "photo.badge.arrow.down")
                }
                .font(Tokens.Fonte.miudo.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.Cor.acao)
            .disabled(processandoFoto)
        }
    }

    @MainActor
    private func carregarMiniaturaDaPeca() async {
        guard let pecaSalva,
              let dados = await PecasSalvas.shared.miniatura(de: pecaSalva) else {
            miniaturaDaPeca = nil
            return
        }
        miniaturaDaPeca = await MiniaturaParaTela.imagem(de: dados)
    }

    @MainActor
    private func substituirFoto(_ item: PhotosPickerItem) async {
        guard let pecaSalva else { return }
        processandoFoto = true
        erroDaFoto = nil
        defer {
            processandoFoto = false
            fotoEscolhida = nil
        }
        do {
            guard let dados = try await item.loadTransferable(type: Data.self),
                  let imagem = MiniaturaLocal.imagem(de: dados),
                  let miniatura = await MiniaturaLocal.dados(de: imagem),
                  await PecasSalvas.shared.salvar(pecaSalva, miniaturaDados: miniatura)
            else {
                erroDaFoto = "I couldn't save that photo. Your existing image was not changed."
                return
            }
            miniaturaDaPeca = await MiniaturaParaTela.imagem(de: miniatura)
        } catch {
            erroDaFoto = "I couldn't read that image. Try another photo."
        }
    }

    /// §29.1 — template determinístico. Só conta o que foi medido.
    ///
    /// O parágrafo do painel vem PRIMEIRO, e o da taxonomia depois: é o que a
    /// §29 pede, e faz sentido — "encontrei 230 peças parecidas, 22% a preço
    /// cheio" responde a uma pergunta que o comprador tem; "3 atributos, 2 com
    /// leitura" responde a uma pergunta que ele não fez.
    /// Os atributos confirmados, corrigíveis sem sair do painel.
    ///
    /// Mudar um chip recalcula o painel na hora e **não chama a análise visual
    /// de novo**: reler a foto é outra ação, e custa. Corrigir o que ela leu é
    /// grátis, e é o que a pessoa espera ao consertar um erro.
    private func chipsDeCorrecao(_ selecao: Binding<Set<String>>) -> some View {
        Cartao {
            Text("Confirmed attributes").font(Tokens.Fonte.secao)

            // A lista do que ESTÁ marcado, uma linha por atributo. A primeira
            // versão desta caixa mostrava a taxonomia inteira aqui, com os não
            // marcados junto -- era a tela de atributos de novo, dentro da tela
            // de resultado. Aqui a pergunta já é outra: "o que foi confirmado?".
            VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                // Todo item começa por marcador, cor inclusive. A amostra da
                // cor trocava o marcador por ela mesma, e a lista ficava com
                // duas margens: os atributos alinhavam por "•" e as cores por
                // uma bolinha de outro tamanho. Agora a amostra vem DEPOIS do
                // nome, como ilustração do que já foi dito.
                ForEach(confirmados(selecao.wrappedValue), id: \.id) { termo in
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Espaco.s) {
                        Text("•").foregroundStyle(Tokens.Cor.tintaFraca)
                        Text(Traducao.rotuloExibido(termo))
                            .fixedSize(horizontal: false, vertical: true)
                        if let rgb = CorDaPeca.rgbRepresentativo(de: termo.id) {
                            Circle()
                                .fill(Color(red: rgb.0, green: rgb.1, blue: rgb.2))
                                .overlay(Circle().strokeBorder(
                                    Tokens.Cor.borda, lineWidth: 0.5))
                                .frame(width: 10, height: 10)
                                // Círculo não tem linha de base. Sem isto ele
                                // encosta a borda inferior na base do texto e
                                // parece afundado.
                                .alignmentGuide(.firstTextBaseline) { d in
                                    d[.bottom] - 1
                                }
                        }
                    }
                    // Sem isto o VoiceOver lê "marcador" antes de cada
                    // atributo, e lê a amostra de cor como imagem sem rótulo.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Traducao.rotuloExibido(termo))
                }
            }
            .font(Tokens.Fonte.corpo)

            // Corrigir continua a um toque, mas recolhido: quem chegou aqui
            // veio ler o resultado, não refazer o formulário.
            DisclosureGroup {
                FluxoDeChips(
                    termos: todosOsTermos.filter { termo in
                        FormularioDaPeca.dimensoesPermitidas(
                            categorias: Set(todosOsTermos.lazy
                                .filter { $0.dimensao == "categoria"
                                          && selecao.wrappedValue.contains($0.id) }
                                .map(\.id))
                        ).contains(termo.dimensao)
                    },
                    todos: todosOsTermos,
                    marcados: selecao)
                .padding(.top, Tokens.Espaco.s)
            } label: {
                Text("Change something")
                    .font(Tokens.Fonte.miudo.weight(.medium))
            }
            .tint(Tokens.Cor.tintaFraca)
        }
    }

    /// Os termos marcados, na ordem da taxonomia — que desde o P15 é a ordem
    /// por frequência real no painel, e não a alfabética do id interno.
    private func confirmados(_ marcados: Set<String>) -> [Termo] {
        todosOsTermos.filter { marcados.contains($0.id) }
    }

    private var resumo: some View {
        Cartao {
            // A revisão de UX apontou que esta tela não deixa claro qual é o
            // resultado -- ela abre com um parágrafo e a pessoa tem de deduzir.
            // A ordem NÃO muda (ver o cabeçalho deste arquivo: o número do
            // conjunto vem por último de propósito, senão vira veredito). O que
            // muda é dizer, com todas as letras, que isto aqui é o resultado.
            Text("Result").font(Tokens.Fonte.secao)
            if let r = similares?.resumo {
                // As mesmas frases da §29, uma por linha. Nada foi reescrito:
                // o parágrafo sempre foi uma lista de frases, juntada no fim.
                let frases = Similares.frasesDoResumo(
                    r, atributos: termos, descricao: descricaoAmigavel)
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    ForEach(frases, id: \.self) { f in
                        HStack(alignment: .firstTextBaseline,
                               spacing: Tokens.Espaco.s) {
                            Text("•").foregroundStyle(Tokens.Cor.tintaFraca)
                            Text(f).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(Tokens.Fonte.corpo)
                // Para o VoiceOver a lista vira uma frase só: marcador lido a
                // cada linha viraria ruído.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Similares.paragrafo(
                    r, atributos: termos, descricao: descricaoAmigavel))
                Divider()
            }
            Text(leituraDoConjunto).font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
        }
    }

    /// §29.4 — o bloco de insumos de varejo: similares com preço, remarcação e
    /// estado da grade, sempre.
        private func secaoCarregando(_ titulo: String) -> some View {
        Cartao {
            HStack {
                Text(titulo).font(Tokens.Fonte.secao)
                Spacer()
                ProgressView()
            }
        }
    }

    private func falhaLocal(titulo: String, mensagem: String) -> some View {
        Cartao {
            Text(titulo).font(Tokens.Fonte.secao)
            Text(mensagem).font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            Button("Try again") { Task { await carregar() } }
                .buttonStyle(.bordered)
        }
    }

    /// Renomeada de `frase` em 05/09: o nome sombreava a função global
    /// `frase(_:)` dentro desta View inteira.
    private var leituraDoConjunto: String {
        let comLeitura = termos.filter {
            let indice = indices[$0.id]
            return indice?.indice != nil
                && Elegibilidade.indice(indice, cobertura: coberturas[$0.id])
        }
        let total = String(termos.count)
        if comLeitura.isEmpty {
            return termos.count == 1
                ? frase("You selected 1 attribute, but it has no available reading in this panel cut.")
                : frase("You selected \(total) attributes, but none has an available reading in this panel cut.")
        }
        let acima = comLeitura.filter { (indices[$0.id]?.indice ?? 0) >= 1 }
        let abaixo = comLeitura.filter { (indices[$0.id]?.indice ?? 0) <= -1 }
        let lidos = String(comLeitura.count)
        var partes = [termos.count == 1
            ? frase("This item has 1 attribute, with readings for \(lidos).")
            : frase("This item has \(total) attributes, with readings for \(lidos).")]
        if !acima.isEmpty {
            partes.append(frase("Above the usual range: \(acima.map(Traducao.rotuloExibido).joined(separator: ", "))."))
        }
        if !abaixo.isEmpty {
            partes.append(frase("Below the usual range: \(abaixo.map(Traducao.rotuloExibido).joined(separator: ", "))."))
        }
        if acima.isEmpty && abaixo.isEmpty {
            partes.append(frase("All are within their usual ranges."))
        }
        return partes.joined(separator: " ")
    }

    /// Um bloco por atributo, cada um com o próprio portão de cobertura.
    @ViewBuilder
    private var porAtributo: some View {
        let publicaveis = termos.filter {
            let indice = indices[$0.id]
            return indice?.indice != nil
                && Elegibilidade.indice(indice, cobertura: coberturas[$0.id])
        }
        if !publicaveis.isEmpty {
          VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            Text("BY ATTRIBUTE")
                .font(Tokens.Fonte.grupo)
                .tracking(0.6)
                .foregroundStyle(Tokens.Cor.tintaFraca)
                .padding(.leading, Tokens.Espaco.xs)
            ForEach(publicaveis) { termo in
                Cartao {
                    let indice = indices[termo.id]
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                            Text(Traducao.rotuloExibido(termo))
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                            Text(Traducao.rotuloDaDimensao(termo.dimensao))
                                .font(Tokens.Fonte.miudo)
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                        }
                        Spacer()
                        // O número sobe para o mesmo peso do rótulo, e fica na
                        // COR DA TINTA.
                        //
                        // No desenho da Bianca ele estava em verde, e verde
                        // quer dizer "bom". Isto aqui é desvio-padrão: acima
                        // da faixa usual não é bom nem ruim, é posição. Pintar
                        // de verde transformaria medição em veredito, que é
                        // exatamente o que as regras 2 e 6 existem para
                        // impedir. A direção continua dita -- por escrito, na
                        // pílula, que a §32 exige que não dependa de cor.
                        if let valor = indice?.indice {
                            // Sinal só quando ele significa alguma coisa. Com
                            // `sinal: true` sempre, um índice nulo saía como
                            // "+0.0" -- um mais na frente de zero, que sugere
                            // direção onde não há nenhuma.
                            Text(Leitura.numero(valor, casas: 1,
                                                sinal: abs(valor) >= 0.05))
                                .font(.system(size: 34, weight: .semibold,
                                              design: .rounded))
                                .foregroundStyle(Tokens.Cor.tinta)
                                .monospacedDigit()
                                .accessibilityLabel(
                                    "\(Leitura.numero(valor, casas: 1, sinal: abs(valor) >= 0.05)) on the statistical scale")
                        }
                    }
                    SeloEstado(estado: indice?.estado, leitura: indice?.indice)
                    conteudo(de: termo)
                }
            }
          }
        }
    }

    @ViewBuilder
    private func conteudo(de termo: Termo) -> some View {
        let i = indices[termo.id]
        if let valor = i?.indice {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                LinhaInsumo(texto: Leitura.explicacao(valor))
                // "on the statistical scale" dizia que existe uma escala sem
                // dizer qual. O "?" diz.
                BotaoDeAjuda(titulo: Explicacao.tituloDaEscala,
                             texto: Explicacao.textoDaEscala,
                             rotulo: "What this number is")
            }
            LinhaInsumo(texto: Perna.baseadoEm(i?.pernasAtivas)
                        + " · week of \(Formato.data(i?.semana ?? ""))")
        }
    }

    /// O histórico dos ATRIBUTOS da peça (A14).
    ///
    /// Não é a peça do usuário ao longo do tempo — ela não está no painel, e a
    /// §34 exclui acompanhá-la. É o recorte de mercado que ela ocupa.
    @ViewBuilder
    private var blocoDoHistorico: some View {
        Cartao {
            Text("This mix, week by week").font(Tokens.Fonte.secao)
            // O título anterior, "How these attributes moved", não era falso --
            // era uma frase onde devia haver um nome, e não dizia o que se
            // move nem em relação a quê. O JP perguntou por que eu o achava
            // feio; é isto. "Mix" faz o trabalho que faltava: diz que a linha
            // é da COMBINAÇÃO, e não da peça.
            //
            // E a explicação embaixo passa a carregar o que o título não
            // consegue. Ela precisa dizer três coisas, porque a §34 depende
            // disso: que o app não segue a peça de ninguém, que a linha é do
            // recorte de mercado que os atributos ocupam, e que o ponto
            // marcado é semana rala. Sem a primeira, um gráfico de dois anos
            // sobre uma peça criada hoje afirma um histórico que não existe.
            //
            // A PRIMEIRA FRASE ERA FALSA, e era minha. "The panel items that
            // share these attributes, week by week" descreve uma CONTAGEM DE
            // PEÇAS, e é o que qualquer pessoa entende ao ler. A linha não é
            // isso: `serie_do_cluster` devolve
            // `sum(indice * peso) / sum(peso)` -- a média dos índices dos
            // atributos, ponderada pela raridade de cada um (K5), e o índice
            // de cada atributo é distância em desvios-padrão das 12 semanas
            // anteriores DELE. O eixo Y já dizia isso ("distance from the
            // usual behavior of the previous 12 weeks") e contradizia a
            // legenda; quem lia os dois lia duas afirmações incompatíveis.
            // Quantas peças existem com estes atributos é o bloco "Result",
            // onde o número vem do painel e vem com a data em que foi visto.
            // Uma frase só: concatenar literais produz `String` e pula a
            // localização. O texto preserva a semântica corrigida da A57.
            Text("How unusual these attributes were each week, compared with their own previous 12 weeks — one line, weighted by how rare each attribute is. It is not a count of items, and it is not your item: DataDrobe never tracks a piece you own. A marked point is a week built on fewer attributes than you selected, so the line is thinner there.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            if carregandoSerie {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if let erroDaSerie {
                Text("The chart could not be loaded: \(erroDaSerie)")
                    .font(Tokens.Fonte.corpo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                Button("Try the chart again") { Task { await carregar() } }
                    .buttonStyle(.bordered)
            } else if let motivo = SerieDoCluster.porQueNaoDesenha(serie) {
                // Nunca um espaço em branco: a tela diz o que falta.
                Text(motivo)
                    .font(Tokens.Fonte.corpo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            } else if let s = serie {
                Chart(s.pontos.filter { $0.data != nil }) { p in
                    AreaMark(x: .value("Week", p.data!),
                             yStart: .value("Baseline", 0),
                             yEnd: .value("Index", p.indice))
                        .foregroundStyle(Tokens.Cor.azulMarca.opacity(0.12))
                    LineMark(x: .value("Week", p.data!),
                             y: .value("Index", p.indice))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Tokens.Cor.azulMarca)
                    // Semana com menos atributos que o pedido ganha ponto
                    // visível: a linha sozinha mente por omissão, porque parece
                    // uniforme mesmo quando metade dela veio de um atributo só.
                    if SerieDoCluster.ralo(p, de: s.atributosPedidos) {
                        PointMark(x: .value("Week", p.data!),
                                  y: .value("Index", p.indice))
                            .symbolSize(28)
                            .foregroundStyle(Tokens.Cor.semDado)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartYAxisLabel(Explicacao.unidadeDoIndice)
                .frame(height: 160)
                .accessibilityLabel(
                    "Combined history across \(s.pontos.count) weeks")
                // Onde a linha termina. A borda direita de um gráfico é lida
                // como "agora"; aqui ela é a última semana publicada, e com a
                // coleta parada as duas coisas estão a semanas de distância.
                if let fim = SerieDoCluster.ateQuando(s) { LinhaInsumo(texto: fim) }
                if let r = SerieDoCluster.ressalva(s) { LinhaInsumo(texto: r) }
                if let c = s.categoriaUsada, c != "(todas)" {
                    let categoria = Traducao.rotuloExibido(id: c).lowercased()
                    LinhaInsumo(texto: "Compared with other \(categoria) items in the current panel.")
                }
            }
        }
    }

    /// §22 / K5 — o número da peça inteira, com os pesos abertos.
    ///
    /// Esta tela declarava, até 02/08, que o cálculo não existia. Agora existe,
    /// e a honestidade mudou de lugar: em vez de dizer "não há número", ela diz
    /// **de que o número é feito** e, quando os atributos discordam entre si,
    /// se recusa a dar direção.
    @ViewBuilder
    private var blocoDoCluster: some View {
        if carregandoCluster {
            secaoCarregando("Combined reading")
        } else if let erroDoCluster {
            falhaLocal(titulo: "Combined reading", mensagem: erroDoCluster)
        } else if let c = cluster, c.nAtributos > 0 {
            Cartao {
                Text("Combined reading").font(Tokens.Fonte.secao)
                Text(Cluster.manchete(c)).font(Tokens.Fonte.corpo)
                if let e = Cluster.explicacao(c) { LinhaInsumo(texto: e) }
                if let k = Cluster.concentracao(c) { LinhaInsumo(texto: k) }

                // A revisão de UX pediu para separar visualmente esta caixa:
                // o RESULTADO e a TRILHA DE AUDITORIA estavam no mesmo cartão,
                // divididos só por uma linha, e a trilha é mais longa que o
                // resultado.
                //
                // Recolher, e não remover. A regra 3 exige que a pessoa possa
                // auditar de onde o número saiu -- é isso que separa esta tela
                // de um app que só afirma. O que ela não exige é que a
                // auditoria esteja sempre aberta ocupando a tela de quem já
                // confia. Fica a um toque, e o rótulo diz o que tem dentro.
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                        LinhaInsumo(texto: Cluster.criterioDaRaridade(c))
                        blocoDeProcedencia(c)
                    }
                    .padding(.top, Tokens.Espaco.s)
                } label: {
                    Text("Where this number comes from")
                        .font(Tokens.Fonte.miudo.weight(.semibold))
                }
                .tint(Tokens.Cor.tintaFraca)
            }
        }
    }

    /// A trilha de auditoria do número do conjunto: cada atributo que entrou,
    /// com o peso, e cada um que ficou de fora, com o motivo (regra 6).
    @ViewBuilder
    private func blocoDeProcedencia(_ c: Cluster.Resposta) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            ForEach(Cluster.dentro(c)) { a in
                    HStack(alignment: .firstTextBaseline) {
                        Text(rotuloDoAtributo(a)).font(Tokens.Fonte.miudo)
                        Spacer()
                        if let i = a.indice {
                            Text(Leitura.numero(i, casas: 2, sinal: true))
                                .font(Tokens.Fonte.miudo.monospacedDigit())
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                        }
                    }
                    // A barra do peso, colada no texto que a nomeia.
                    //
                    // Ideia da Bianca, e boa: peso é proporção, e proporção se
                    // lê num piscar numa barra e não num número. A armadilha
                    // que o desenho dela tinha é que a barra ficava na mesma
                    // linha do VALOR (-1,37) e podia ser lida como se fosse
                    // ele. Aqui ela nasce imediatamente antes da frase que
                    // começa com "55% of the weight", e é essa vizinhança que
                    // diz de quem ela é.
                    if let peso = a.pesoRelativo {
                        BarraDePeso(fracao: peso)
                    }
                    // E a frase inteira fica. O desenho novo mostrava só "55%
                    // of the weight", mas é a segunda metade -- "2% of items
                    // with this dimension (13 in the panel)" -- que EXPLICA o
                    // peso. Sem ela, o parágrafo acima promete que atributo
                    // incomum pesa mais e a tela não mostra o quanto ele é
                    // incomum.
                    if let p = Cluster.porQuePesa(a) { LinhaInsumo(texto: p) }
            }
            if let s = Cluster.ressalvaDeSemana(c) { LinhaInsumo(texto: s) }
        }
    }

    private func carregar() async {
        carregando = true
        erro = nil
        erroDosSimilares = nil
        erroDoCluster = nil
        erroDaSerie = nil
        carregandoSimilares = true
        carregandoCluster = true
        carregandoSerie = true
        guard !termos.isEmpty else { carregando = false; return }
        let termoIds = termos.map(\.id)
        let ids = termoIds.joined(separator: ",")
        let conjuntoIds = Set(termoIds)
        do {
            // Todas as cinco operações começam no mesmo instante. A versão
            // anterior esperava índice+cobertura e SÓ DEPOIS iniciava os três
            // RPCs; a duração percebida era a soma de duas ondas de rede.
            async let i = CatalogoDeIndices.shared.carregar()
            async let c: [Cobertura] = Supabase.shared.buscar(
                "cobertura_por_celula",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=in.(\(ids))&order=semana.desc&limit=600")

            let args: [String: Any] = {
                var argumentos: [String: Any] = ["termos": termoIds, "limite": 8]
                if let precoAlvo { argumentos["preco_alvo"] = precoAlvo }
                return argumentos
            }()
            // `_v2` desde a A57. A versão sem sufixo continua no banco,
            // intacta, servindo os aparelhos que ainda não atualizaram: quem
            // decide a versão instalada é a pessoa, e trocar o comportamento
            // por baixo dela seria mudar a tela de quem não pediu.
            async let respostaSimilar: Similares.Resposta = Supabase.shared.chamar(
                "similares_da_peca_amplo_v2", args)
            async let respostaCluster: Cluster.Resposta = Supabase.shared.chamar(
                "indice_do_cluster", ["termos": termoIds])
            async let respostaSerie: SerieDoCluster.Resposta = Supabase.shared.chamar(
                "serie_do_cluster", ["termos": termoIds, "semanas": 52])

            let recebidosI = try await i.filter { conjuntoIds.contains($0.termoId) }
            let mapaI = SelecaoDeEstado.porTermo(recebidosI)
            indices = mapaI

            // A cobertura tem de ser a da MESMA semana do índice do atributo.
            var mapaC: [String: Cobertura] = [:]
            for x in try await c {
                guard let indice = mapaI[x.termoId], indice.semana == x.semana else { continue }
                mapaC[x.termoId] = x
            }
            coberturas = mapaC
            // Índices e cobertura bastam para liberar a tela. Os três RPCs
            // continuam em voo e ocupam somente suas próprias seções.
            carregando = false

            // Cancelamento nao e falha de rede: e a tela sendo fechada ou a
            // pergunta sendo trocada. Escrever "The server could not be
            // reached" nesse caso e acusar o servidor de um erro que foi
            // nosso.
            do {
                similares = try await respostaSimilar
            } catch is CancellationError {
                return
            } catch {
                erroDosSimilares = mensagem(error)
            }
            carregandoSimilares = false
            do { cluster = try await respostaCluster }
            catch is CancellationError { return }
            catch { erroDoCluster = mensagem(error) }
            carregandoCluster = false
            do { serie = try await respostaSerie }
            catch is CancellationError { return }
            catch { erroDaSerie = mensagem(error) }
            carregandoSerie = false
        } catch is CancellationError {
            return
        } catch {
            erro = mensagem(error)
        }
        carregando = false
    }

    private func mensagem(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }

    private func rejeitarSimilares(_ rejeitados: Bool) {
        rejeitouSimilares = rejeitados
        guard var atualizada = pecaSalva ?? pecaGuardadaNestaTela else { return }
        atualizada.similaresRejeitados = rejeitados ? true : nil
        pecaGuardadaNestaTela = atualizada
        Task { await PecasSalvas.shared.salvar(atualizada) }
    }

    /// O `rotulo` do cluster vem do banco, em português ("Basico"). A tela é em
    /// inglês, e a taxonomia já carregada tem o termo correspondente — então o
    /// rótulo exibido sai do mesmo lugar que o resto da interface usa.
    private func rotuloDoAtributo(_ a: Cluster.Atributo) -> String {
        if let termo = termos.first(where: { $0.id == a.termoId }) {
            return Traducao.rotuloExibido(termo)
        }
        return a.rotulo
    }
}
