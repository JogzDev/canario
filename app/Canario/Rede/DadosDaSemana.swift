import Foundation

/// O que a aba Esta semana carrega, num lugar só.
///
/// Os carregadores vieram do `Explorar`, a aba de mercado da 1.x, sem mudar o
/// que pedem ao banco: `resumo_de_eventos` (A58) para os movimentos das lojas,
/// `series_do_app` para a busca e para a imprensa, o catálogo de índices e de
/// termos. O cache também é o mesmo arquivo, então as duas telas não baixam o
/// mesmo dado duas vezes enquanto convivem.
///
/// O que é novo aqui é a escolha da manchete.
@MainActor
final class DadosDaSemana: ObservableObject {
    @Published private(set) var indices: [IndiceSemanal] = []
    @Published private(set) var termos: [Termo] = []
    @Published private(set) var pulsoBusca: [PontoSerie] = []
    @Published private(set) var pulsoEditorial: [PontoSerie] = []
    @Published private(set) var resumos: [String: ResumoDeEventos.Resposta] = [:]
    @Published private(set) var carregando = true
    @Published private(set) var carregandoEventos = true
    @Published private(set) var erro: String?
    @Published private(set) var avisoDeCache: String?
    @Published private(set) var avisos: [String] = []

    private var termosPorId: [String: Termo] = [:]
    /// A série do Explorar só serve às telas antigas; guardada para o cache
    /// continuar legível pelas duas.
    private var seriesDoCache: [String: [PontoSerie]] = [:]

    // MARK: A manchete

    /// Abaixo disto, uma taxa por mil é barulho: 3 peças de um catálogo de 10
    /// dariam "300 por mil" e ganhariam a capa de uma marca que repôs 400.
    static let pecasMinimasParaTaxa = 20

    /// A história de um tipo de movimento, escolhida pela PROPORÇÃO.
    ///
    /// Por contagem bruta a C&A ganha quase todo dia: é 32% do sortimento do
    /// painel. A capa virava vitrine de quem tem o maior catálogo, e isso não é
    /// descoberta. A régua passa a ser peças movidas por mil ofertadas, entre
    /// as marcas com volume suficiente; a contagem continua na manchete, e a
    /// frase de apoio diz por que ESTA marca é a história. Sem denominador na
    /// janela (fora da retenção), cai para a contagem e diz isso.
    func historia(_ tipo: String, evitando outra: String? = nil) -> Historia? {
        guard let r = resumos[tipo] else { return nil }
        let candidatas = r.marcas.filter {
            $0.marca != outra && $0.pecas >= Self.pecasMinimasParaTaxa
        }
        let comTaxa = candidatas.filter { $0.porMilOfertadas != nil }
        if let melhor = comTaxa.max(by: { ($0.porMilOfertadas ?? 0) < ($1.porMilOfertadas ?? 0) }) {
            return Historia(tipo: tipo, marca: melhor, resposta: r, porProporcao: true)
        }
        if let maior = (candidatas.isEmpty ? r.marcas.filter { $0.marca != outra } : candidatas)
            .max(by: { $0.pecas < $1.pecas }) {
            return Historia(tipo: tipo, marca: maior, resposta: r, porProporcao: false)
        }
        return nil
    }

    struct Historia: Identifiable {
        let tipo: String
        let marca: ResumoDeEventos.Marca
        let resposta: ResumoDeEventos.Resposta
        /// Verdadeiro quando a marca foi escolhida pela taxa, não pelo volume.
        let porProporcao: Bool
        var id: String { tipo + marca.marca }

        /// "19 de cada 100 peças à venda": a taxa por mil em linguagem de gente.
        var deCadaCem: Int? {
            marca.porMilOfertadas.map { Int(($0 / 10).rounded()) }
        }
    }

    /// As marcas que não viraram manchete, pela mesma régua da manchete.
    func prateleira(_ tipo: String, sem usadas: Set<String>, limite: Int = 8) -> [ResumoDeEventos.Marca] {
        guard let r = resumos[tipo] else { return [] }
        return r.marcas
            .filter { !usadas.contains($0.marca) && !$0.exemplos.isEmpty }
            .sorted { ($0.porMilOfertadas ?? -1, $0.pecas) > ($1.porMilOfertadas ?? -1, $1.pecas) }
            .prefix(limite).map { $0 }
    }

    // MARK: Busca e imprensa

    /// A semana mais recente da busca, sem categoria (categoria é a unidade do
    /// painel, não um sinal de busca que a pessoa leia como tendência).
    var buscaDaSemana: [PontoSerie] {
        guard let semana = pulsoBusca.map(\.semana).max() else { return [] }
        return pulsoBusca
            .filter { $0.semana == semana && $0.z != nil
                      && termosPorId[$0.termoId]?.dimensao != "categoria" }
            .sorted { ($0.z ?? 0) > ($1.z ?? 0) }
    }

    var semanaDaBusca: String? { pulsoBusca.map(\.semana).max() }

    func serieDeBusca(_ termoId: String) -> [PontoSerie] {
        pulsoBusca.filter { $0.termoId == termoId && $0.z != nil }
            .sorted { $0.semana < $1.semana }
    }

    /// Manchetes atuais que declaram moda, sem repetir matéria.
    var manchetes: [PontoSerie.Meta.Exemplo] {
        guard let semana = pulsoEditorial.map(\.semana).max() else { return [] }
        var vistos = Set<String>()
        return pulsoEditorial
            .filter { $0.semana == semana }
            .flatMap { $0.meta?.exemplos ?? [] }
            .filter { Explicacao.mancheteDeclaraModa($0.titulo) }
            .filter { vistos.insert(($0.url ?? $0.titulo).lowercased()).inserted }
            .prefix(8).map { $0 }
    }

    func termo(_ id: String) -> Termo? { termosPorId[id] }

    func rotulo(_ id: String) -> String {
        termosPorId[id].map(Traducao.rotuloExibido) ?? id
    }

    func dimensao(_ id: String) -> String? {
        guard let d = termosPorId[id]?.dimensao, !d.isEmpty else { return nil }
        return Traducao.rotuloDaDimensao(d)
    }

    // MARK: Carga

    func carregar() async {
        erro = nil
        avisoDeCache = nil
        avisos = []
        var mostrouCache = false
        if let salvo = await CacheDoExplorar.shared.carregar() {
            aplicar(salvo)
            carregando = false
            mostrouCache = true
            // Cache incompleto não é cache fresco: uma carga que falhou não
            // pode segurar a tela vazia por quinze minutos.
            let completo = !salvo.resumos.isEmpty && !salvo.pulsoBusca.isEmpty
            if completo && Date().timeIntervalSince(salvo.salvoEm) < 15 * 60 { return }
        } else {
            carregando = true
            carregandoEventos = true
        }

        do {
            async let i = CatalogoDeIndices.shared.carregar()
            async let t = CatalogoDeTermos.shared.carregar()
            indices = try await i.filter { $0.estado != nil }
            termos = try await t
            termosPorId = Dictionary(termos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            carregando = false
        } catch is CancellationError {
            return
        } catch {
            let mensagem = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            if mostrouCache {
                avisoDeCache = frase("Offline · showing the last sync")
            } else {
                erro = mensagem
            }
            carregando = false
            return
        }

        async let busca: Void = carregarPulsoDeBusca()
        async let editorial: Void = carregarPulsoEditorial()
        async let eventos: Void = carregarEventos()
        _ = await (busca, editorial, eventos)

        // Só guarda o que veio: sem os movimentos, o cache seria uma semana vazia.
        guard !resumos.isEmpty else { return }
        await CacheDoExplorar.shared.salvar(SnapshotDoExplorar(
            todos: indices, termos: termos, series: seriesDoCache,
            pulsoBusca: pulsoBusca, pulsoEditorial: pulsoEditorial,
            resumos: resumos, salvoEm: Date()))
    }

    private func carregarPulsoDeBusca() async {
        do {
            pulsoBusca = try await Supabase.shared.buscar(
                "series_do_app",
                "select=*&segmento=eq.\(Recorte.segmento)&fonte=eq.busca"
                + "&semana=gte.\(Self.dataISO(diasAtras: 21))&order=semana.desc&limit=250")
        } catch is CancellationError {
        } catch {
            avisar(frase("Search interest could not refresh; the rest of the page is available."))
        }
    }

    private func carregarPulsoEditorial() async {
        do {
            pulsoEditorial = try await Supabase.shared.buscar(
                "series_do_app",
                "select=*&segmento=eq.\(Recorte.segmento)"
                + "&fonte=in.(editorial_br,editorial_intl)"
                + "&semana=gte.\(Self.dataISO(diasAtras: 14))&order=semana.desc&limit=250")
        } catch is CancellationError {
        } catch {
            avisar(frase("Fashion headlines could not refresh; the rest of the page is available."))
        }
    }

    private func carregarEventos() async {
        carregandoEventos = true
        defer { carregandoEventos = false }
        do {
            async let rep: ResumoDeEventos.Resposta = Supabase.shared.chamar(
                "resumo_de_eventos",
                ["tipo_evento": "reposicao", "dias": 7, "exemplos_por_marca": 12])
            async let rem: ResumoDeEventos.Resposta = Supabase.shared.chamar(
                "resumo_de_eventos",
                ["tipo_evento": "remarcacao", "dias": 7, "exemplos_por_marca": 12])
            resumos = ["reposicao": try await rep, "remarcacao": try await rem]
        } catch is CancellationError {
        } catch {
            avisar(frase("Store movements could not refresh."))
        }
    }

    private func avisar(_ texto: String) {
        if !avisos.contains(texto) { avisos.append(texto) }
    }

    private func aplicar(_ salvo: SnapshotDoExplorar) {
        indices = salvo.todos
        termos = salvo.termos
        termosPorId = Dictionary(termos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        seriesDoCache = salvo.series
        pulsoBusca = salvo.pulsoBusca
        pulsoEditorial = salvo.pulsoEditorial
        resumos = salvo.resumos
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
