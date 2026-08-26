import Foundation
import CryptoKit

/// Sincroniza os campos digitados e, numa rota privada separada, somente a
/// miniatura já reduzida e sem metadados. A foto original nunca entra aqui.
/// O merge acontece duas vezes: localmente para resposta rápida e no RPC
/// atômico para uma requisição antiga nunca vencer uma edição nova.
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
        let miniaturaHash: String?
        let miniaturaExtensao: String?
        let atualizadoEm: Date
        let removidoEm: Date?

        enum CodingKeys: String, CodingKey {
            case id, apelido, canal, favorita
            case termoIds = "termo_ids"
            case precoAlvo = "preco_alvo"
            case criadaEm = "criada_em"
            case similaresRejeitados = "similares_rejeitados"
            case miniaturaHash = "miniatura_hash"
            case miniaturaExtensao = "miniatura_extensao"
            case atualizadoEm = "atualizado_em"
            case removidoEm = "removido_em"
        }

        var peca: PecaSalva? {
            guard removidoEm == nil, let apelido, let termoIds, let criadaEm else { return nil }
            return PecaSalva(id: id, apelido: apelido, termoIds: termoIds,
                             precoAlvo: precoAlvo, canal: canal, criadaEm: criadaEm,
                             miniaturaArquivo: nil,
                             miniaturaHashRemoto: miniaturaHash,
                             miniaturaExtensaoRemota: miniaturaExtensao,
                             favorita: favorita,
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

        // Falha de uma imagem não bloqueia atributos nem o uso offline. Hash
        // ausente faz a próxima sincronização tentar novamente.
        await sincronizarMiniaturas(contexto)

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
            value: "id,apelido,termo_ids,preco_alvo,canal,criada_em,favorita,similares_rejeitados,miniatura_hash,miniatura_extensao,atualizado_em,removido_em")]
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
            if let valor = peca.miniaturaHashRemoto { linha["miniatura_hash"] = valor }
            if let valor = peca.miniaturaExtensaoRemota { linha["miniatura_extensao"] = valor }
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

    private func sincronizarMiniaturas(_ contexto: ContextoAutenticado) async {
        let estado = await loja.estadoParaSincronizar()
        let usuario = contexto.sessao.usuario.id.uuidString.lowercased()

        for peca in estado.itens {
            let local = await loja.miniaturaParaSincronizar(de: peca)
            if peca.miniaturaHashRemoto == nil, let local {
                let hash = Self.hash(local.dados)
                do {
                    let extensaoAnterior = peca.miniaturaExtensaoRemota
                    try await enviarMiniatura(local.dados, id: peca.id,
                                              extensao: local.extensao,
                                              usuario: usuario, contexto: contexto)
                    await loja.registrarMiniaturaSincronizada(
                        id: peca.id, hash: hash, extensao: local.extensao)
                    if let extensaoAnterior, extensaoAnterior != local.extensao {
                        try? await apagarMiniaturas(
                            id: peca.id, extensoes: [extensaoAnterior],
                            usuario: usuario, contexto: contexto)
                    }
                } catch {
                    continue
                }
            } else if let hashRemoto = peca.miniaturaHashRemoto,
                      let extensao = Self.extensaoValida(peca.miniaturaExtensaoRemota),
                      local.map({ Self.hash($0.dados) }) != hashRemoto {
                do {
                    let dados = try await baixarMiniatura(
                        id: peca.id, extensao: extensao,
                        usuario: usuario, contexto: contexto)
                    guard Self.hash(dados) == hashRemoto else { continue }
                    _ = await loja.restaurarMiniaturaSincronizada(
                        id: peca.id, dados: dados, hash: hashRemoto, extensao: extensao)
                } catch {
                    continue
                }
            }
        }

        if !estado.exclusoes.isEmpty {
            for id in estado.exclusoes.keys {
                try? await apagarMiniaturas(
                    id: id, extensoes: ["jpg", "png"],
                    usuario: usuario, contexto: contexto)
            }
        }
    }

    private func enviarMiniatura(_ dados: Data, id: UUID, extensao: String,
                                 usuario: String,
                                 contexto: ContextoAutenticado) async throws {
        guard dados.count <= 3_000_000,
              let extensao = Self.extensaoValida(extensao) else {
            throw Falha.dadosInvalidos
        }
        let caminho = "\(usuario)/\(id.uuidString.lowercased()).\(extensao)"
        let url = contexto.url.appendingPathComponent(
            "storage/v1/object/closet-thumbnails/\(caminho)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        autenticar(&req, contexto)
        req.setValue(extensao == "png" ? "image/png" : "image/jpeg",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = dados
        _ = try await executar(req)
    }

    private func baixarMiniatura(id: UUID, extensao: String, usuario: String,
                                 contexto: ContextoAutenticado) async throws -> Data {
        let caminho = "\(usuario)/\(id.uuidString.lowercased()).\(extensao)"
        let url = contexto.url.appendingPathComponent(
            "storage/v1/object/authenticated/closet-thumbnails/\(caminho)")
        var req = URLRequest(url: url)
        autenticar(&req, contexto)
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        let dados = try await executar(req)
        guard !dados.isEmpty, dados.count <= 3_000_000 else { throw Falha.dadosInvalidos }
        return dados
    }

    private func apagarMiniaturas(id: UUID, extensoes: [String], usuario: String,
                                  contexto: ContextoAutenticado) async throws {
        let caminhos = extensoes.compactMap(Self.extensaoValida).map {
            "\(usuario)/\(id.uuidString.lowercased()).\($0)"
        }
        guard !caminhos.isEmpty else { return }
        let url = contexto.url.appendingPathComponent(
            "storage/v1/object/closet-thumbnails")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        autenticar(&req, contexto)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["prefixes": caminhos])
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

    private static func hash(_ dados: Data) -> String {
        SHA256.hash(data: dados).map { String(format: "%02x", $0) }.joined()
    }

    private static func extensaoValida(_ valor: String?) -> String? {
        guard let valor else { return nil }
        let normalizada = valor.lowercased()
        return ["jpg", "png"].contains(normalizada) ? normalizada : nil
    }

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
