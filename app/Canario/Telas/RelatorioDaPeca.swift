import PhotosUI
import SwiftUI
import UIKit

/// Leitura de uma peça a partir dos atributos confirmados pelo usuário (§29).
/// A foto abre a tela; resultado, similares e atributos mostram a prova antes
/// da leitura combinada, que se cala quando os atributos discordam.
struct RelatorioDaPeca: View {
    let termos: [Termo]
    /// Preço que o usuário pretende praticar, se informou. §29.5 chama isso de
    /// contexto condicional, e a §5 autoriza o percentil de preço que sai dele.
    var precoAlvo: Double?
    /// Prévia local, já sem metadados. Só é persistida se o usuário guardar.
    var miniaturaJPEG: Data?
    /// Quando aberto pelo Closet, evita salvar uma duplicata da mesma peça.
    var pecaSalva: PecaSalva? = nil
    /// Análise da foto atual. A Leitura usa os detalhes livres dela, mas os
    /// atributos são sempre os que a pessoa confirmou no formulário.
    var analiseDaFoto: AnaliseVisualRemota? = nil
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
    @State private var erroDosSimilares: String?
    @State private var erroDoCluster: String?
    @State private var carregandoSimilares = true
    @State private var carregandoCluster = true
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

    private var descricaoParaLeitura: DescricaoDaPeca {
        var descricao = analiseDaFoto.map {
            DescricaoDaPeca.daFoto($0, confirmados: termos.map(\.id),
                                   em: todosOsTermos.isEmpty ? termos : todosOsTermos)
        } ?? DescricaoDaPeca.dosTermos(termos.map(\.id), em: termos)
        if let detalhes = pecaSalva?.detalhesVisuais {
            descricao.detalhes = DescricaoDaPeca.limparDetalhes(detalhes)
        }
        return descricao
    }

    /// Guarda a peça em "Minhas peças" (§27, A10).
    ///
    /// Grava os termos confirmados e os detalhes visuais locais. Índice,
    /// estado e similares são recomputados do dado de hoje ao reabrir.
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case false:
            // O teto é dito, e não engole a peça em silêncio.
            Text("Closet full (\(PecasSalvas.teto))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case nil:
            Button {
                Task {
                    let nova = PecaSalva(
                        apelido: apelido.trimmingCharacters(in: .whitespacesAndNewlines),
                        termoIds: termos.map(\.id), precoAlvo: precoAlvo,
                        similaresRejeitados: rejeitouSimilares ? true : nil,
                        coresPorPrioridade: coresPorPrioridade.isEmpty
                            ? nil : coresPorPrioridade,
                        detalhesVisuais: descricaoParaLeitura.detalhes)
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

    /// 2.0: a leitura específica desta peça, com o preço que a pessoa já deu.
    @ViewBuilder
    private var cartaoDaLeitura: some View {
        if Supabase.analiseRemotaHabilitada || LeituraDaPeca.testeDeInterfaceAtivo {
            let pedido = apelido.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Traducao.descricaoAmigavel(termos, consulta: "") : apelido
            NavigationLink {
                LeituraDaPeca(pedido: pedido,
                              descricao: descricaoParaLeitura,
                              precoInicial: precoAlvo)
            } label: {
                Folha {
                    HStack(spacing: 12) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Edicao.bordo)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Read this piece in the panel")
                                .font(Edicao.Tipo.linha)
                                .foregroundStyle(.primary)
                            Text("The reading finds pieces like it, checks each one and shows the proof.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        SetaDaLinha()
                    }
                    .frame(minHeight: 44)
                }
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else {
                    // A foto e os similares ficam no alto; a leitura combinada
                    // vem depois das partes, conforme §29.
                    heroiDaPeca
                    cartaoDaLeitura
                    resumo
                    vitrineDeSimilares
                    porAtributo
                    blocoDoCluster
                    if let selecao, !todosOsTermos.isEmpty {
                        chipsDeCorrecao(selecao)
                    }
                }
            }
            .padding(.horizontal, Edicao.margem)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .papelDaEdicao()
        .tint(Edicao.bordo)
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
        if let s = similares, let r = s.resumo,
                  !s.pecas.filter(Similares.podeExibir).isEmpty {
            let visiveis = s.pecas.filter(Similares.podeExibir)
            Folha {
                NavigationLink {
                    TodosOsSimilares(resumo: r, pecas: visiveis,
                                     atributos: termos, precoAlvo: precoAlvo,
                                     nomeDaPeca: nomeExibido)
                } label: {
                    CabecalhoDaFolha(titulo: Text("Show similar pieces"), abre: true)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show all \(visiveis.count) similar pieces")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(visiveis.prefix(8)) { peca in
                            MiniaturaDeSimilar(peca: peca, pedidos: termos)
                        }
                    }
                    .padding(.vertical, 2)
                }
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
        VStack(alignment: .leading, spacing: 12) {
            ImagemDaPeca(imagem: imagemDoHeroi, simbolo: "photo")
                .frame(height: 300)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(imagemDoHeroi == nil
                                    ? "This item has no photo" : "Photo of \(nomeExibido)")

            Text(nomeExibido)
                .font(Edicao.Tipo.destaque)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    /// A edição visual mora no detalhe, onde há contexto para entender qual
    /// peça será alterada. A foto em si subiu para o herói; aqui ficou só a
    /// ação, que é do Closet e não do fluxo de importação — no fluxo a foto
    /// acabou de ser escolhida e trocar significa voltar, não editar.
    private var trocarFoto: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let erroDaFoto {
                Text(erroDaFoto).font(.footnote).foregroundStyle(.secondary)
            }
            PhotosPicker(selection: $fotoEscolhida, matching: .images) {
                HStack(spacing: 8) {
                    if processandoFoto { ProgressView().controlSize(.small) }
                    Label(miniaturaDaPeca == nil ? "Add photo" : "Replace photo",
                          systemImage: "photo.badge.arrow.down")
                }
                .font(.footnote.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Edicao.bordo)
            .frame(minHeight: 44)
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
                erroDaFoto = frase("I couldn't save that photo. Your existing image was not changed.")
                return
            }
            miniaturaDaPeca = await MiniaturaParaTela.imagem(de: miniatura)
        } catch {
            erroDaFoto = frase("I couldn't read that image. Try another photo.")
        }
    }

    /// Corrigir a taxonomia refaz o painel, sem reler a foto. A lista acima
    /// já mostra os atributos confirmados; aqui fica só a edição.
    private func chipsDeCorrecao(_ selecao: Binding<Set<String>>) -> some View {
        Folha {
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
                .padding(.top, 12)
            } label: {
                CabecalhoDaFolha(titulo: Text("Change something"),
                                 simbolo: "slider.horizontal.3")
            }
            .tint(Edicao.bordo)
        }
    }

    @ViewBuilder
    private var resumo: some View {
        if carregandoSimilares {
            secaoCarregando(frase("Result"))
        } else if let erroDosSimilares {
            falhaLocal(titulo: frase("Result"), mensagem: erroDosSimilares)
        } else if let r = similares?.resumo {
            Folha {
                CabecalhoDaFolha(titulo: Text("Result"))
                ForEach(Similares.frasesDoResumo(
                    r, atributos: termos, descricao: descricaoAmigavel), id: \.self) { fraseDoPainel in
                    Text(verbatim: fraseDoPainel)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if r.nSimilares > 0 {
                    CosturaDaEdicao()
                    Text(Similares.criterio(r))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let posicao = Similares.leituraDoPreco(r, alvo: precoAlvo) {
                    CosturaDaEdicao()
                    Text("Where your price falls")
                        .font(Edicao.Tipo.linha)
                    Text(verbatim: posicao)
                        .font(.subheadline)
                }
            }
        }
    }

    private func secaoCarregando(_ titulo: String) -> some View {
        Folha {
            HStack {
                Text(titulo).font(Edicao.Tipo.titulo)
                Spacer()
                ProgressView()
            }
        }
    }

    private func falhaLocal(titulo: String, mensagem: String) -> some View {
        Folha {
            CabecalhoDaFolha(titulo: Text(verbatim: titulo))
            Text(mensagem).font(.footnote)
                .foregroundStyle(.secondary)
            Button("Try again") { Task { await carregar() } }
                .buttonStyle(.bordered)
        }
    }

    /// Uma lista só para leitura e imprensa: cada atributo é uma porta para
    /// o relatório completo, com a posição publicada nesta folha.
    @ViewBuilder
    private var porAtributo: some View {
        if !termos.isEmpty {
            Folha(espaco: 0) {
                CabecalhoDaFolha(
                    titulo: Text("Attributes"),
                    nota: frase("Tap an attribute for its reading and press coverage."))
                    .padding(.bottom, 8)
                ForEach(Array(termos.enumerated()), id: \.element.id) { indiceDaLinha, termo in
                    if indiceDaLinha > 0 { CosturaDaEdicao() }
                    NavigationLink {
                        RelatorioDoTermo(termo: termo)
                    } label: {
                        let indice = indices[termo.id]
                        let publicavel = Elegibilidade.indice(
                            indice, cobertura: coberturas[termo.id])
                        VStack(alignment: .leading, spacing: 0) {
                            LinhaDeAtributo(
                                termoId: termo.id,
                                rotulo: Traducao.rotuloExibido(termo),
                                dimensao: Traducao.rotuloDaDimensao(termo.dimensao),
                                leitura: publicavel ? indice?.indice : nil)
                            if publicavel, let semana = indice?.semana {
                                Text(frase("Week of \(Formato.data(semana))."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 44)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
            secaoCarregando(frase("Combined reading"))
        } else if let erroDoCluster {
            falhaLocal(titulo: frase("Combined reading"), mensagem: erroDoCluster)
        } else if let c = cluster, c.nAtributos > 0 {
            Folha {
                CabecalhoDaFolha(titulo: Text("Combined reading"))
                Text(Cluster.manchete(c)).font(.body)
                if let e = Cluster.explicacao(c) {
                    Text(verbatim: e).font(.footnote).foregroundStyle(.secondary)
                }
                if let k = Cluster.concentracao(c) {
                    Text(verbatim: k).font(.footnote).foregroundStyle(.secondary)
                }

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
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: Cluster.criterioDaRaridade(c))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        blocoDeProcedencia(c)
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Where this number comes from")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Edicao.bordo)
            }
        }
    }

    /// A trilha de auditoria do número do conjunto: cada atributo que entrou,
    /// com o peso, e cada um que ficou de fora, com o motivo (regra 6).
    @ViewBuilder
    private func blocoDeProcedencia(_ c: Cluster.Resposta) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Cluster.dentro(c)) { a in
                    HStack(alignment: .firstTextBaseline) {
                        Text(rotuloDoAtributo(a)).font(.footnote)
                        Spacer()
                        if let i = a.indice {
                            Text(Leitura.numero(i, casas: 2, sinal: true))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
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
        carregandoSimilares = true
        carregandoCluster = true
        if LeituraDaPeca.testeDeInterfaceAtivo {
            carregando = false
            carregandoSimilares = false
            carregandoCluster = false
            return
        }
        guard !termos.isEmpty else { carregando = false; return }
        let termoIds = termos.map(\.id)
        let ids = termoIds.joined(separator: ",")
        let conjuntoIds = Set(termoIds)
        do {
            // Índice, cobertura e os dois RPCs começam juntos: a tela não
            // soma duas ondas de rede antes de mostrar o painel.
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
            // Índices e cobertura liberam a tela; os dois RPCs preenchem
            // suas seções quando responderem.
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
