import Foundation

/// Sincroniza somente os campos digitados no Closet. Miniaturas nunca entram
/// nesta camada. O merge acontece duas vezes: localmente para resposta rápida
/// e no RPC atômico para uma requisição antiga nunca vencer uma edição nova.
actor SincronizacaoDoCloset {
    static let shared = SincronizacaoDoCloset()

    enum Falha: LocalizedError {
        case semConta
        case resposta(Int)
        case dadosInvalidos

        var errorDescription: String? {
            switch self {
            case .semConta: return "Sign in before synchronizing your Closet."
            case .resposta: return "Closet sync is temporarily unavailable. Your local changes are safe."
            case .dadosInvalidos: return "Closet sync returned data I could not verify. Your local copy was kept."
            }
        }
    }

    struct Resultado: Sendable {
        let itens: Int
        let data: Date
    }

    private struct LinhaRemota: Decodable {
        let id: UUID
        let apelido: String?
        let termoIds: [String]?
        let precoAlvo: Double?
        let canal: String?
        let criadaEm: Date?
        let favorita: Bool?
        let similaresRejeitados: Bool?
        let atualizadoEm: Date
        let removidoEm: Date?

        enum CodingKeys: String, CodingKey {
            case id, apelido, canal, favorita
            case termoIds = "termo_ids"
            case precoAlvo = "preco_alvo"
            case criadaEm = "criada_em"
            case similaresRejeitados = "similares_rejeitados"
            case atualizadoEm = "atualizado_em"
            case removidoEm = "removido_em"
        }

        var peca: PecaSalva? {
            guard removidoEm == nil, let apelido, let termoIds, let criadaEm else { return nil }
            return PecaSalva(id: id, apelido: apelido, termoIds: termoIds,
                             precoAlvo: precoAlvo, canal: canal, criadaEm: criadaEm,
                             miniaturaArquivo: nil, favorita: favorita,
                             similaresRejeitados: similaresRejeitados,
                             atualizadaEm: atualizadoEm)
        }
    }

    private let http: URLSession
    private let autenticacao: Autenticacao
    private let loja: PecasSalvas
    private var emCurso: Task<Resultado, Error>?

    init(http: URLSession? = nil,
         autenticacao: Autenticacao = .shared,
         loja: PecasSalvas = .shared) {
        self.autenticacao = autenticacao
        self.loja = loja
        if let http {
            self.http = http
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 15
            cfg.waitsForConnectivity = false
            self.http = URLSession(configuration: cfg)
        }
    }

    func sincronizar() async throws -> Resultado {
        if let emCurso { return try await emCurso.value }
        let tarefa = Task { try await executar() }
        emCurso = tarefa
        defer { emCurso = nil }
        return try await tarefa.value
    }

    private func executar() async throws -> Resultado {
        guard let contexto = await autenticacao.contextoAtual() else {
            throw Falha.semConta
        }
        await loja.usarEspacoDoUsuario(contexto.sessao.usuario.id)

        let primeiraLeitura = try await buscar(contexto)
        await aplicar(primeiraLeitura)

        let estado = await loja.estadoParaSincronizar()
        try await enviar(estado, contexto: contexto)

        // Confirma o que o banco efetivamente aceitou. Essa segunda leitura é
        // também quem resolve uma edição concorrente de outro aparelho.
        let confirmada = try await buscar(contexto)
        await aplicar(confirmada)
        return Resultado(itens: confirmada.filter { $0.removidoEm == nil }.count,
                         data: Date())
    }

    private func buscar(_ contexto: ContextoAutenticado) async throws -> [LinhaRemota] {
        var componentes = URLComponents(
            url: contexto.url.appendingPathComponent("rest/v1/closet_items"),
            resolvingAgainstBaseURL: false)
        componentes?.queryItems = [URLQueryItem(
            name: "select",
            value: "id,apelido,termo_ids,preco_alvo,canal,criada_em,favorita,similares_rejeitados,atualizado_em,removido_em")]
        guard let url = componentes?.url else { throw Falha.dadosInvalidos }
        var req = URLRequest(url: url)
        autenticar(&req, contexto)
        let dados = try await executar(req)
        do {
            return try Self.decoder.decode([LinhaRemota].self, from: dados)
        } catch {
            throw Falha.dadosInvalidos
        }
    }

    private func enviar(_ estado: PecasSalvas.EstadoParaSincronizar,
                        contexto: ContextoAutenticado) async throws {
        var mudancas = estado.itens.map { peca -> [String: Any] in
            var linha: [String: Any] = [
                "id": peca.id.uuidString.lowercased(),
                "apelido": peca.apelido,
                "termo_ids": peca.termoIds,
                "criada_em": Self.data(peca.criadaEm),
                "atualizado_em": Self.data(peca.atualizadaEm ?? peca.criadaEm),
            ]
            if let valor = peca.precoAlvo { linha["preco_alvo"] = valor }
            if let valor = peca.canal { linha["canal"] = valor }
            if let valor = peca.favorita { linha["favorita"] = valor }
            if let valor = peca.similaresRejeitados { linha["similares_rejeitados"] = valor }
            return linha
        }
        mudancas += estado.exclusoes.map { id, data in
            ["id": id.uuidString.lowercased(),
             "atualizado_em": Self.data(data),
             "removido_em": Self.data(data)]
        }
        guard !mudancas.isEmpty else { return }

        let url = contexto.url.appendingPathComponent(
            "rest/v1/rpc/aplicar_mudancas_closet")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        autenticar(&req, contexto)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["p_mudancas": mudancas])
        _ = try await executar(req)
    }

    private func aplicar(_ linhas: [LinhaRemota]) async {
        let ativas = linhas.compactMap(\.peca)
        let removidas = Dictionary(uniqueKeysWithValues: linhas.compactMap { linha in
            linha.removidoEm.map { (linha.id, max($0, linha.atualizadoEm)) }
        })
        await loja.aplicarRemotos(ativas, removidos: removidas)
    }

    private func autenticar(_ req: inout URLRequest, _ contexto: ContextoAutenticado) {
        req.setValue(contexto.chavePublicavel, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(contexto.sessao.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func executar(_ req: URLRequest) async throws -> Data {
        do {
            let (dados, resposta) = try await http.data(for: req)
            let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(codigo) else { throw Falha.resposta(codigo) }
            return dados
        } catch let falha as Falha {
            throw falha
        } catch {
            throw Falha.resposta(0)
        }
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func data(_ data: Date) -> String { formatter.string(from: data) }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let texto = try dec.singleValueContainer().decode(String.self)
            if let data = formatter.date(from: texto) { return data }
            let simples = ISO8601DateFormatter()
            if let data = simples.date(from: texto) { return data }
            throw DecodingError.dataCorruptedError(
                in: try dec.singleValueContainer(), debugDescription: "Invalid ISO date")
        }
        return decoder
    }
}
