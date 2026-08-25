import SwiftUI

/// Aba **Explorar** (§27): valor de esforço zero na abertura.
///
/// ## O que mudou em 31/07, e por quê
///
/// O JP abriu a aba e listou quatro problemas. Todos viraram desenho aqui:
///
/// 1. **"É muito feio mostrar coisa do dia anterior."** Era, e a causa não era
///    de tela: `computar_eventos()` existia no banco e não estava no motor, então
///    a tabela de eventos congelou em 30/07 enquanto a coleta seguia rodando.
///    Corrigido no `motor_computar.py`. A tela agora **carimba a data do dado**
///    em vez de deixar o usuário descobrir sozinho.
/// 2. **"Agrupar por marca, senão fica muito poluído."** Vinte cartões soltos
///    viravam uma parede. Agora é uma linha por marca, com o total, e a lista
///    abre no toque.
/// 3. **"Pode ter algo tipo *3ª reposição dos tamanhos PP/P em menos de 2
///    meses."** É o sinal mais forte do painel e estava invisível: a view passou
///    a contar o ordinal por produto.
/// 4. **"Esses textos repetidos não me cativam."** Estavam repetidos porque
///    todo cartão dizia a mesma frase de perna. Agora cada um traz o número com
///    unidade, a regra que produziu o estado e o nome de quem publicou.
struct Explorar: View {
    var menuAberto = false
    var alternarMenu: (() -> Void)?
    @State private var todos: [IndiceSemanal] = []
    @State private var termos: [Termo] = []
    @State private var series: [String: [PontoSerie]] = [:]
    @State private var pulsoBusca: [PontoSerie] = []
    @State private var pulsoEditorial: [PontoSerie] = []
    @State private var eventos: [EventoVarejo] = []
    @State private var inicioDaColeta = "2026-07-24"
    @State private var carregando = true
    @State private var carregandoPulso = true
    @State private var carregandoEditorial = true
    @State private var carregandoEventos = true
    @State private var erro: String?
    @State private var avisoDeCache: String?
    @State private var avisosParciais: [String] = []

    private let diasMaximosDoDigest = 42

    private var rotulos: [String: String] {
        Dictionary(uniqueKeysWithValues: termos.map { ($0.id, Traducao.rotuloExibido($0)) })
    }

    private var termosPorId: [String: Termo] {
        Dictionary(uniqueKeysWithValues: termos.map { ($0.id, $0) })
    }

    /// Um termo por linha, com a mudança MAIS RECENTE dele.
    ///
    /// Sem isto o mesmo termo aparecia várias vezes — "Casaco e jaqueta" saía
    /// duas vezes, nas semanas 13/07 e 06/07. Digest é resumo do que mudou, não
    /// histórico: repetir o termo gasta a atenção do usuário sem informar.
    private var mudaram: [IndiceSemanal] {
        var vistos = Set<String>()
        return todos
            .filter { Formato.diasDesde($0.semana) <= diasMaximosDoDigest }
            .filter { vistos.insert($0.termoId).inserted }
            .sorted {
                let esquerda = prioridade($0), direita = prioridade($1)
                return esquerda == direita ? $0.semana > $1.semana : esquerda < direita
            }
    }

    /// A categoria filtra o mercado (§11); sozinha não é uma tendência. O
    /// radar destaca os atributos atuais e deixa categoria para a busca.
    private var buscaDaSemana: [PontoSerie] {
        guard let semana = pulsoBusca.map(\.semana).max() else { return [] }
        return pulsoBusca.filter {
            $0.semana == semana && $0.z != nil
                && termosPorId[$0.termoId]?.dimensao != "categoria"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else {
                    conteudo
                }
            }
            .navigationTitle("Weekly Trends")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let alternarMenu {
                        BotaoDoMenu(menuAberto: menuAberto, acao: alternarMenu)
                    }
                }
            }
        }
        .task { await carregar() }
    }

    private var conteudo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if let avisoDeCache {
                    Label(avisoDeCache, systemImage: "wifi.slash")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
                if !avisosParciais.isEmpty {
                    ForEach(avisosParciais, id: \.self) { aviso in
                        Label(aviso, systemImage: "exclamationmark.circle")
                            .font(Tokens.Fonte.miudo)
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                    }
                }
                atalhoDeComparacao
                radarDeBusca
                radarEditorial
                digest
                curvaDoPainel
                movimento(titulo: "Restocks", tipo: "reposicao",
                          vazio: "No restock was confirmed in this window. Confirmation requires seeing a size disappear, return and remain available.")
                movimento(titulo: "Markdowns", tipo: "remarcacao",
                          vazio: "No price reduction of 5% or more was confirmed in this window.")
            }
            .padding(Tokens.Espaco.m)
            .padding(.bottom, 20)
        }
    }

    /// Comparar é uma ferramenta de leitura de tendências, não uma forma de
    /// encontrar uma peça. Mantê-la nesta aba evita competir com a Search da
    /// barra principal e dá contexto antes de escolher os atributos.
    private var atalhoDeComparacao: some View {
        NavigationLink {
            Comparar()
        } label: {
            Cartao {
                HStack(spacing: Tokens.Espaco.m) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Tokens.Cor.acao)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Compare attributes")
                            .font(Tokens.Fonte.secao)
                            .foregroundStyle(Tokens.Cor.tinta)
                        Text("Put market readings side by side.")
                            .font(Tokens.Fonte.apoio)
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Tokens.Fonte.miudo.weight(.semibold))
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Movimento das marcas

    /// Uma linha por marca, com o total; a lista de peças abre no toque.
    private func movimento(titulo: String, tipo: String, vazio: String) -> some View {
        let doTipo = eventos.filter { $0.tipo == tipo }
        let porMarca = Dictionary(grouping: doTipo, by: \.marca)
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
        let maisRecente = doTipo.map(\.data).max()

        return VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(titulo).font(Tokens.Fonte.secao)
                Spacer()
                if let maisRecente {
                    // O carimbo que faltava: o usuário vê a data do dado sem
                    // precisar deduzi-la de um cartão.
                    Text(carimbo(maisRecente))
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }
            if carregandoEventos && porMarca.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if porMarca.isEmpty {
                CoberturaInsuficiente(titulo: "No record in this window",
                                      explicacao: vazio, oQueTem: nil)
            } else {
                ForEach(porMarca, id: \.key) { marca, lista in
                    NavigationLink {
                        ListaDeEventos(marca: marca, titulo: titulo, eventos: lista,
                                       inicioDaColeta: inicioDaColeta)
                    } label: {
                        LinhaDeMarca(marca: marca, eventos: lista)
                    }
                    .buttonStyle(.plain)
                }
                if tipo == "reposicao" {
                    LinhaInsumo(texto: "A restock appears only after a second visit confirms it. A size that returns for one day may be a catalog correction rather than a buying decision, so the newest confirmed event is usually from yesterday.")
                }
            }
        }
    }

    /// §24 na abertura da aba: é o bloco de maior valor por esforço zero, e o
    /// único que responde a uma pergunta que o comprador já tem na cabeça antes
    /// de abrir o app.
    private var curvaDoPainel: some View {
        NavigationLink {
            CurvaDeTamanhosView(termo: nil)
        } label: {
            Cartao {
                HStack(alignment: .firstTextBaseline) {
                    Text("Size availability").font(Tokens.Fonte.secao)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
                Text("Where size availability is breaking across the panel.")
                    .font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }
        }
        .buttonStyle(.plain)
    }

    /// A data do dado, sempre explícita.
    ///
    /// A §6 barra as frases de cultivo do tipo "está fresquinho", e com razão:
    /// além de serem linguagem de engajamento, elas somem justamente no dia em
    /// que o usuário mais precisa saber se o número envelheceu. A data resolve
    /// as duas coisas de uma vez.
    private func carimbo(_ data: String) -> String {
        "most recent event: \(Formato.data(data))"
    }

    // MARK: Radares atuais

    /// Google é uma fonte, não um veredito. Mostrá-lo separadamente resolve o
    /// atraso aparente sem enfraquecer a regra que exige duas fontes para
    /// chamar algo de tendência confirmada.
    private var radarDeBusca: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Search interest now").font(Tokens.Fonte.secao)
                Spacer()
                if let semana = buscaDaSemana.map(\.semana).max() {
                    Text(Formato.data(semana))
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }
            Text("What people in Brazil searched for on Google, compared with each term's previous 12 weeks.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)

            if carregandoPulso && buscaDaSemana.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if buscaDaSemana.isEmpty {
                LinhaInsumo(texto: "No current Google search reading is available.")
            } else {
                ForEach(gruposDaBusca, id: \.titulo) { grupo in
                    if !grupo.pontos.isEmpty {
                        Text(grupo.titulo.uppercased())
                            .font(Tokens.Fonte.miudo.weight(.semibold))
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                            .padding(.top, Tokens.Espaco.xs)
                        ForEach(grupo.pontos.prefix(5)) { ponto in
                            if let termo = termosPorId[ponto.termoId] {
                                NavigationLink { RelatorioDoTermo(termo: termo) } label: {
                                    Cartao {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(Traducao.rotuloExibido(termo)).font(Tokens.Fonte.corpo)
                                            Spacer()
                                            Text(ponto.z.map(Leitura.emPalavras) ?? "—")
                                                .font(Tokens.Fonte.miudo.weight(.semibold))
                                                .foregroundStyle(Tokens.Cor.acao)
                                            Image(systemName: "chevron.right")
                                                .font(Tokens.Fonte.miudo)
                                                .foregroundStyle(Tokens.Cor.tintaFraca)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                LinhaInsumo(texto: "This is the current search pulse, not a confirmed trend on its own.")
            }
        }
    }

    private var gruposDaBusca: [(titulo: String, pontos: [PontoSerie])] {
        let ordenados = buscaDaSemana.sorted { ($0.z ?? 0) > ($1.z ?? 0) }
        return [
            ("High", ordenados.filter { ($0.z ?? 0) >= 1 }),
            ("Building", ordenados.filter { (0.35..<1).contains($0.z ?? 0) }),
            ("Steady", ordenados.filter { abs($0.z ?? 0) < 0.35 }),
            ("Cooling", ordenados.filter { ($0.z ?? 0) <= -0.35 }.reversed()),
        ].map { ($0.0, Array($0.1)) }
    }

    private var manchetesAtuais: [PontoSerie.Meta.Exemplo] {
        guard let semana = pulsoEditorial.map(\.semana).max() else { return [] }
        var vistos = Set<String>()
        return pulsoEditorial
            .filter { $0.semana == semana }
            .flatMap { $0.meta?.exemplos ?? [] }
            .filter { Explicacao.mancheteDeclaraModa($0.titulo) }
            .filter { vistos.insert(($0.url ?? $0.titulo).lowercased()).inserted }
            .prefix(8).map { $0 }
    }

    private var radarEditorial: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week in fashion").font(Tokens.Fonte.secao)
                Spacer()
                if let semana = pulsoEditorial.map(\.semana).max() {
                    Text(Formato.data(semana))
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }
            Text("Current, fashion-specific headlines from the monitored publications. They provide context; one article alone does not establish a trend.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)

            if carregandoEditorial && manchetesAtuais.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if manchetesAtuais.isEmpty {
                LinhaInsumo(texto: "No current headline passed the fashion-context check.")
            } else {
                ForEach(manchetesAtuais, id: \.titulo) { manchete in
                    if let bruto = manchete.url, let url = URL(string: bruto) {
                        Link(destination: url) { linhaEditorial(manchete) }
                            .buttonStyle(.plain)
                    } else {
                        linhaEditorial(manchete)
                    }
                }
            }
        }
    }

    private func linhaEditorial(_ manchete: PontoSerie.Meta.Exemplo) -> some View {
        Cartao {
            Text(manchete.titulo)
                .font(Tokens.Fonte.apoio.weight(.semibold))
                .foregroundStyle(Tokens.Cor.tinta)
            HStack {
                Text(manchete.veiculo).font(Tokens.Fonte.miudo)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(Tokens.Fonte.miudo)
            }
            .foregroundStyle(Tokens.Cor.acao)
        }
    }

    // MARK: Tendência confirmada

    private var digest: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Confirmed movements").font(Tokens.Fonte.secao)
                Spacer()
                if let semana = mudaram.map(\.semana).max() {
                    Text("updated \(Formato.data(semana))")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }
            if mudaram.isEmpty {
                LinhaInsumo(texto: "No movement has been confirmed by two independent sources in the last \(diasMaximosDoDigest) days.")
            } else {
                ForEach(gruposDoDigest, id: \.titulo) { grupo in
                    if !grupo.indices.isEmpty {
                        Text(grupo.titulo)
                            .font(Tokens.Fonte.miudo.weight(.semibold))
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                            .textCase(.uppercase)
                            .padding(.top, Tokens.Espaco.xs)
                        ForEach(grupo.indices) { i in
                            NavigationLink {
                                if let termo = termoDe(i) { RelatorioDoTermo(termo: termo) }
                            } label: {
                                CartaoDeMudanca(indice: i,
                                                rotulo: rotulos[i.termoId] ?? i.termoId,
                                                series: series[i.termoId] ?? [])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var gruposDoDigest: [(titulo: String, indices: [IndiceSemanal])] {
        [
            ("Trending up", mudaram.filter { $0.estado == "em alta" }),
            ("Editorial highlights", mudaram.filter { $0.estado == "pico" }),
            ("Within the usual range", mudaram.filter { $0.estado == "estavel" }),
            ("Trending down", mudaram.filter { $0.estado == "em queda" }),
        ]
    }

    private func prioridade(_ indice: IndiceSemanal) -> Int {
        let ordem = ["em alta": 0, "pico": 1, "estavel": 2, "em queda": 3]
        return ordem[indice.estado ?? ""] ?? 4
    }

    private func termoDe(_ i: IndiceSemanal) -> Termo? {
        guard let rotulo = rotulos[i.termoId] else { return nil }
        return Termo(id: i.termoId, rotulo: rotulo, dimensao: "", exclusiva: false,
                     sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    @MainActor
    private func carregar() async {
        erro = nil
        avisoDeCache = nil
        avisosParciais = []
        var mostrouCache = false
        if let salvo = await CacheDoExplorar.shared.carregar() {
            aplicar(salvo)
            carregando = false
            mostrouCache = true
            // Trocar de aba e voltar não refaz cinco consultas. Os carimbos
            // continuam mostrando a idade real do dado; isto só evita trabalho
            // duplicado dentro dos quinze minutos seguintes à sincronização.
            if Date().timeIntervalSince(salvo.salvoEm) < 15 * 60 { return }
        } else {
            carregando = true
            carregandoPulso = true
            carregandoEditorial = true
            carregandoEventos = true
        }

        do {
            async let i = CatalogoDeIndices.shared.carregar()
            async let t = CatalogoDeTermos.shared.carregar()

            todos = try await i.filter { $0.estado != nil }
            termos = try await t
            carregando = false
        } catch {
            let mensagem = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            if mostrouCache {
                avisoDeCache = "Offline · showing the last sync"
                erro = nil
            } else {
                erro = mensagem
            }
            carregando = false
            return
        }

        // A primeira tela útil já está visível. Radar, manchetes, explicações
        // e eventos renovam em paralelo, cada um com seu próprio estado. Uma
        // recusa do CDN ou um RPC lento não volta a cobrir tudo com spinner.
        async let busca: Void = carregarPulsoDeBusca()
        async let editorial: Void = carregarPulsoEditorial()
        async let detalhes: Void = carregarDetalhesConfirmados()
        async let movimentos: Void = carregarEventos()
        _ = await (busca, editorial, detalhes, movimentos)

        await CacheDoExplorar.shared.salvar(SnapshotDoExplorar(
            todos: todos, termos: termos, series: series,
            pulsoBusca: pulsoBusca, pulsoEditorial: pulsoEditorial,
            eventos: eventos, salvoEm: Date()))
    }

    @MainActor
    private func carregarPulsoDeBusca() async {
        carregandoPulso = true
        defer { carregandoPulso = false }
        do {
            let corte = Self.dataISO(diasAtras: 21)
            let novos: [PontoSerie] = try await Supabase.shared.buscar(
                "series_do_app",
                "select=*&segmento=eq.\(Recorte.segmento)&fonte=eq.busca"
                + "&semana=gte.\(corte)&order=semana.desc&limit=250")
            pulsoBusca = novos
        } catch {
            avisar("Search interest could not refresh; the rest of the page is available.")
        }
    }

    @MainActor
    private func carregarPulsoEditorial() async {
        carregandoEditorial = true
        defer { carregandoEditorial = false }
        do {
            let corte = Self.dataISO(diasAtras: 14)
            let novos: [PontoSerie] = try await Supabase.shared.buscar(
                "series_do_app",
                "select=*&segmento=eq.\(Recorte.segmento)"
                + "&fonte=in.(editorial_br,editorial_intl)&semana=gte.\(corte)"
                + "&order=semana.desc&limit=250")
            pulsoEditorial = novos
        } catch {
            avisar("Fashion headlines could not refresh; the rest of the page is available.")
        }
    }

    @MainActor
    private func carregarDetalhesConfirmados() async {
        let alvos = mudaram
        guard !alvos.isEmpty else { series = [:]; return }
        do {
            let ids = Set(alvos.map(\.termoId)).joined(separator: ",")
            let semanas = Set(alvos.map(\.semana)).joined(separator: ",")
            let pontos: [PontoSerie] = try await Supabase.shared.buscar(
                "series_do_app",
                "select=*&termo_id=in.(\(ids))&semana=in.(\(semanas))&limit=1000")
            let semanaDoAlvo = Dictionary(
                alvos.map { ($0.termoId, $0.semana) },
                uniquingKeysWith: { primeiro, _ in primeiro })
            var mapa: [String: [PontoSerie]] = [:]
            for p in pontos where semanaDoAlvo[p.termoId] == p.semana {
                mapa[p.termoId, default: []].append(p)
            }
            series = mapa
        } catch {
            avisar("Confirmed-movement details could not refresh.")
        }
    }

    @MainActor
    private func carregarEventos() async {
        carregandoEventos = true
        defer { carregandoEventos = false }
        do {
            async let rep: [EventoVarejo] = Supabase.shared.chamar(
                "eventos_recentes", ["tipo_evento": "reposicao", "limite": 120])
            async let rem: [EventoVarejo] = Supabase.shared.chamar(
                "eventos_recentes", ["tipo_evento": "remarcacao", "limite": 120])
            eventos = try await rep + (try await rem)
        } catch {
            avisar("Store movements could not refresh.")
        }
    }

    @MainActor
    private func avisar(_ texto: String) {
        if !avisosParciais.contains(texto) { avisosParciais.append(texto) }
    }

    @MainActor
    private func aplicar(_ salvo: SnapshotDoExplorar) {
        todos = salvo.todos
        termos = salvo.termos
        series = salvo.series
        pulsoBusca = salvo.pulsoBusca
        pulsoEditorial = salvo.pulsoEditorial
        eventos = salvo.eventos
        carregandoPulso = false
        carregandoEditorial = false
        carregandoEventos = false
    }

    private static func dataISO(diasAtras: Int) -> String {
        let data = Calendar(identifier: .iso8601).date(
            byAdding: .day, value: -diasAtras, to: Date()) ?? Date()
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: data)
    }
}

// MARK: - Cache instantâneo da aba

struct SnapshotDoExplorar: Codable {
    let todos: [IndiceSemanal]
    let termos: [Termo]
    let series: [String: [PontoSerie]]
    let pulsoBusca: [PontoSerie]
    let pulsoEditorial: [PontoSerie]
    let eventos: [EventoVarejo]
    let salvoEm: Date
}

actor CacheDoExplorar {
    static let shared = CacheDoExplorar()
    private var memoria: SnapshotDoExplorar?

    private var arquivo: URL {
        FileManager.default.urls(for: .cachesDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("canario-explorar-v2.json")
    }

    func carregar() -> SnapshotDoExplorar? {
        if let memoria { return memoria }
        guard let dados = try? Data(contentsOf: arquivo),
              let salvo = try? JSONDecoder().decode(
                SnapshotDoExplorar.self, from: dados) else { return nil }
        memoria = salvo
        return salvo
    }

    func salvar(_ snapshot: SnapshotDoExplorar) {
        memoria = snapshot
        guard let dados = try? JSONEncoder().encode(snapshot) else { return }
        try? dados.write(to: arquivo, options: .atomic)
    }
}

// MARK: - Linha de marca

/// "Maria Filó · 12 peças com queda de preço". O número na frente, porque é ele
/// que faz o comprador decidir se abre.
struct LinhaDeMarca: View {
    let marca: String
    let eventos: [EventoVarejo]

    var body: some View {
        Cartao {
            HStack(alignment: .center, spacing: Tokens.Espaco.s) {
                HStack(spacing: -10) {
                    ForEach(Array(eventos.compactMap(\.imagem).prefix(3).enumerated()),
                            id: \.offset) { _, endereco in
                        ZStack {
                            Circle().fill(Tokens.Cor.superficie)
                            Image(systemName: "tshirt")
                                .font(.caption)
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                            ImagemRemota(endereco: URL(string: endereco), modo: .fit)
                                .clipShape(Circle())
                        }
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(Tokens.Cor.fundo, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    Text(NomeDeMarca.exibido(marca)).font(Tokens.Fonte.corpo)
                    LinhaInsumo(texto: resumo)
                }
                Spacer()
                Text("\(eventos.count)")
                    .font(Tokens.Fonte.numero)
                Image(systemName: "chevron.right")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(NomeDeMarca.exibido(marca)), \(eventos.count) items. \(resumo)")
    }

    private var resumo: String {
        let repetidas = eventos.filter { ($0.ordinal ?? 1) > 1 }.count
        var partes: [String] = []
        if let d = eventos.map(\.data).max() { partes.append("mais recente em \(Formato.data(d))") }
        if repetidas > 0 { partes.append("\(repetidas) had happened before") }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Lista de peças de uma marca

struct ListaDeEventos: View {
    let marca: String
    let titulo: String
    let eventos: [EventoVarejo]
    let inicioDaColeta: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                ForEach(eventos) { e in
                    Cartao {
                        HStack(alignment: .top, spacing: Tokens.Espaco.m) {
                            ZStack {
                                Tokens.Cor.fundo.opacity(0.55)
                                Image(systemName: "tshirt")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(Tokens.Cor.tintaFraca)
                                ImagemRemota(endereco: e.imagem.flatMap(URL.init(string:)),
                                             modo: .fit)
                            }
                            .frame(width: 82, height: 108)
                            .clipShape(RoundedRectangle(
                                cornerRadius: Tokens.Raio.etiqueta,
                                style: .continuous))
                            VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                                HStack(alignment: .firstTextBaseline) {
                                    Label(NomeDeMarca.exibido(e.marca), systemImage: e.icone)
                                        .font(Tokens.Fonte.apoio.weight(.semibold))
                                    Spacer()
                                    Text(Formato.data(e.data)).font(Tokens.Fonte.miudo)
                                        .foregroundStyle(Tokens.Cor.tintaFraca)
                                }
                                Text(e.peca ?? "—").font(Tokens.Fonte.corpo)
                                Text(e.resumo).font(Tokens.Fonte.apoio)
                                    .foregroundStyle(Tokens.Cor.tintaFraca)
                            }
                        }
                        // A repetição em destaque: é ela que separa um evento
                        // isolado de um padrão de reposição.
                        if let r = e.repeticao(desde: inicioDaColeta) {
                            Text(r)
                                .font(Tokens.Fonte.miudo.weight(.semibold))
                                .foregroundStyle((e.ordinal ?? 1) > 1 ? Tokens.Cor.alta : Tokens.Cor.tintaFraca)
                        }
                        // Regra 3: todo número carrega o caminho até a origem.
                        if let url = e.urlDaPeca, let link = URL(string: url) {
                            Link("View on the brand's website", destination: link)
                                .font(Tokens.Fonte.miudo)
                        }
                    }
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .navigationTitle("\(titulo) · \(marca)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Cartão do digest

/// Um termo que mudou de estado, com o número **acompanhado da unidade**, a
/// regra que produziu o estado e quem publicou.
struct CartaoDeMudanca: View {
    let indice: IndiceSemanal
    let rotulo: String
    let series: [PontoSerie]

    var body: some View {
        Cartao {
            HStack(alignment: .firstTextBaseline) {
                Text(rotulo).font(Tokens.Fonte.corpo)
                Spacer()
                SeloEstado(estado: indice.estado)
            }

            // O número com a unidade colada. Antes saía "+1.15" sozinho.
            if let v = indice.indice {
                Text(Leitura.emPalavras(v))
                    .font(Tokens.Fonte.numero)
            }
            LinhaInsumo(texto: "Compared with this attribute's usual behavior over the previous 12 weeks.")

            // Por que este estado, e não outro.
            Text(Explicacao.porQue(estado: indice.estado, indice: indice, series: series))
                .font(Tokens.Fonte.apoio)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // De onde veio, com nome de veículo.
            ForEach(Explicacao.origens(series), id: \.self) { LinhaInsumo(texto: $0) }
            LinhaInsumo(texto: "Reading updated: \(Formato.data(indice.semana)).")

            let manchetes = Explicacao.manchetes(series)
            if !manchetes.isEmpty {
                Text("Related articles").font(Tokens.Fonte.miudo.weight(.semibold))
                ForEach(manchetes, id: \.titulo) { m in
                    if let u = m.url, let link = URL(string: u) {
                        Link(destination: link) {
                            Text("\(m.veiculo): \(m.titulo)")
                                .font(Tokens.Fonte.miudo)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        LinhaInsumo(texto: "\(m.veiculo): \(m.titulo)")
                    }
                }
            }
        }
    }
}

enum NomeDeMarca {
    static func exibido(_ nome: String) -> String {
        nome == "Maria Filo" ? "Maria Filó" : nome
    }
}
