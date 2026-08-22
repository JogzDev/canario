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
                        termoIds: termos.map(\.id), precoAlvo: precoAlvo,
                        similaresRejeitados: rejeitouSimilares ? true : nil)
                    guardada = await PecasSalvas.shared.salvar(
                        nova, miniaturaDados: miniaturaJPEG)
                    if guardada == true { pecaGuardadaNestaTela = nova }
                }
            } label: {
                Label("Save", systemImage: "archivebox")
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
                    if pecaSalva != nil { fotoDaPeca }
                    if let selecao, !todosOsTermos.isEmpty {
                        chipsDeCorrecao(selecao)
                    }
                    // §29, na ordem que ela manda: o parágrafo vem primeiro, e
                    // ele é feito de similares — não do índice.
                    resumo
                    blocoDeSimilares
                    porAtributo
                    blocoDoCluster
                    blocoDoHistorico
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .task { await carregar() }
        .task(id: pecaSalva?.miniaturaArquivo) { await carregarMiniaturaDaPeca() }
        .onAppear { rejeitouSimilares = pecaSalva?.similaresRejeitados ?? false }
        .onChange(of: fotoEscolhida) { _, item in
            guard let item else { return }
            Task { await substituirFoto(item) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { botaoDeGuardar }
        }
    }

    /// A edição visual mora no detalhe, onde há contexto para entender qual
    /// peça será alterada. O card continua oferecendo “Add photo” somente para
    /// itens antigos que ainda não têm nenhuma.
    private var fotoDaPeca: some View {
        Cartao {
            if let miniaturaDaPeca {
                Image(uiImage: miniaturaDaPeca)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .accessibilityLabel("Saved clothing photo")
            }
            if let erroDaFoto {
                Text(erroDaFoto).font(Tokens.Fonte.miudo).foregroundStyle(.secondary)
            }
            PhotosPicker(selection: $fotoEscolhida, matching: .images) {
                HStack {
                    if processandoFoto { ProgressView().controlSize(.small) }
                    Label(miniaturaDaPeca == nil ? "Add photo" : "Replace photo",
                          systemImage: "photo.badge.arrow.down")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
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
            Text(frase).font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
        }
    }

    /// §29.4 — o bloco de insumos de varejo: similares com preço, remarcação e
    /// estado da grade, sempre.
    @ViewBuilder
    private var blocoDeSimilares: some View {
        if carregandoSimilares {
            secaoCarregando("Similar pieces")
        } else if let erroDosSimilares {
            falhaLocal(titulo: "Similar pieces", mensagem: erroDosSimilares)
        } else if let s = similares, let r = s.resumo,
                  !s.pecas.filter(Similares.podeExibir).isEmpty {
            if rejeitouSimilares {
                LinhaInsumo(texto: "You marked this selection as not similar. You can review it again at any time.")
                Button("Review similar pieces again") { rejeitarSimilares(false) }
                    .buttonStyle(.bordered)
            } else {
                BlocoDeSimilares(resumo: r,
                                 pecas: s.pecas.filter(Similares.podeExibir),
                                 atributos: termos, precoAlvo: precoAlvo)
                Button("None of these looks like my item") { rejeitarSimilares(true) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        } else {
            LinhaInsumo(texto: "No panel item matched all selected attributes.")
        }
    }

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

    private var frase: String {
        let comLeitura = termos.filter {
            let indice = indices[$0.id]
            return indice?.indice != nil
                && Elegibilidade.indice(indice, cobertura: coberturas[$0.id])
        }
        if comLeitura.isEmpty {
            return "You selected \(termos.count) attribute\(termos.count == 1 ? "" : "s"), but none has an available reading in this panel cut."
        }
        let acima = comLeitura.filter { (indices[$0.id]?.indice ?? 0) >= 1 }
        let abaixo = comLeitura.filter { (indices[$0.id]?.indice ?? 0) <= -1 }
        var partes = ["This item has \(termos.count) attribute\(termos.count == 1 ? "" : "s"), with readings for \(comLeitura.count)."]
        if !acima.isEmpty {
            partes.append("Above the usual range: \(acima.map(Traducao.rotuloExibido).joined(separator: ", ")).")
        }
        if !abaixo.isEmpty {
            partes.append("Below the usual range: \(abaixo.map(Traducao.rotuloExibido).joined(separator: ", ")).")
        }
        if acima.isEmpty && abaixo.isEmpty {
            partes.append("All are within their usual ranges.")
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
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                            Text(Traducao.rotuloExibido(termo)).font(Tokens.Fonte.corpo)
                            Text(Traducao.rotuloDaDimensao(termo.dimensao))
                                .font(Tokens.Fonte.miudo)
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                        }
                        Spacer()
                    }
                    let indice = indices[termo.id]
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
            LinhaInsumo(texto: Perna.frase(i?.pernasAtivas)
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
            Text("How these attributes moved").font(Tokens.Fonte.secao)
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
                if let r = SerieDoCluster.ressalva(s) { LinhaInsumo(texto: r) }
                if let c = s.categoriaUsada, c != "(todas)" {
                    LinhaInsumo(texto: "Rarity measured within \(c).")
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
                        Text(a.rotulo).font(Tokens.Fonte.miudo)
                        Spacer()
                        if let i = a.indice {
                            Text(Leitura.numero(i, casas: 2, sinal: true))
                                .font(Tokens.Fonte.miudo.monospacedDigit())
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                        }
                    }
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
            async let respostaSimilar: Similares.Resposta = Supabase.shared.chamar(
                "similares_da_peca", args)
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

            do {
                similares = try await respostaSimilar
            } catch {
                erroDosSimilares = mensagem(error)
            }
            carregandoSimilares = false
            do { cluster = try await respostaCluster }
            catch { erroDoCluster = mensagem(error) }
            carregandoCluster = false
            do { serie = try await respostaSerie }
            catch { erroDaSerie = mensagem(error) }
            carregandoSerie = false
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
