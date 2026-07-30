import Foundation

/// Cliente de leitura do Supabase.
///
/// O app **só lê** (§33: servidor calcula, app consulta). A chave é a
/// publishable, que é pública por desenho e vai embutida no binário — a
/// segurança vem inteiramente das políticas RLS, e não do sigilo dela.
///
/// Sem dependência de terceiros: `URLSession` basta, e §26 pede dependências
/// mínimas e justificadas uma a uma.
actor Supabase {
    static let shared = Supabase()

    private let url: URL
    private let chave: String
    private let sessao: URLSession

    /// Erros que a interface precisa saber diferenciar para ser honesta.
    enum Falha: LocalizedError {
        case semConfiguracao
        case rede(Error)
        case resposta(Int, String)

        var errorDescription: String? {
            switch self {
            case .semConfiguracao:
                return "Config.xcconfig ausente ou incompleto. Copie o Config.xcconfig.example."
            case .rede:
                return "Não foi possível falar com o servidor."
            case .resposta(let codigo, _):
                return "O servidor respondeu \(codigo)."
            }
        }
    }

    init() {
        let info = Bundle.main.infoDictionary
        let bruto = (info?["SUPABASE_URL"] as? String) ?? ""
        // O xcconfig engole `//`, então a URL pode chegar sem o esquema.
        let normalizado = bruto.hasPrefix("http") ? bruto : "https://\(bruto)"
        self.url = URL(string: normalizado) ?? URL(string: "https://invalido.invalido")!
        self.chave = (info?["SUPABASE_PUBLISHABLE_KEY"] as? String) ?? ""

        let cfg = URLSessionConfiguration.default
        // §27 exige modo offline servindo o cache da última sincronização com
        // carimbo visível. O cache do protocolo é a base disso.
        cfg.requestCachePolicy = .useProtocolCachePolicy
        cfg.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        cfg.timeoutIntervalForRequest = 20
        self.sessao = URLSession(configuration: cfg)
    }

    var configurado: Bool {
        !chave.isEmpty && url.host != "invalido.invalido"
    }

    /// GET em uma tabela/view exposta, com query PostgREST.
    /// Ex.: `buscar("indices_semanais", "select=*&limit=10")`
    func buscar<T: Decodable>(_ caminho: String, _ query: String) async throws -> [T] {
        guard configurado else { throw Falha.semConfiguracao }

        var componentes = URLComponents(
            url: url.appendingPathComponent("rest/v1/\(caminho)"),
            resolvingAgainstBaseURL: false)!
        componentes.percentEncodedQuery = query

        var req = URLRequest(url: componentes.url!)
        req.setValue(chave, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (dados, resposta) = try await sessao.data(for: req)
            let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(codigo) else {
                throw Falha.resposta(codigo, String(data: dados, encoding: .utf8) ?? "")
            }
            return try JSONDecoder().decode([T].self, from: dados)
        } catch let falha as Falha {
            throw falha
        } catch {
            throw Falha.rede(error)
        }
    }
}
