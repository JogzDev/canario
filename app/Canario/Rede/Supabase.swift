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
        case urlInvalida(String, String)

        var errorDescription: String? {
            switch self {
            case .semConfiguracao:
                return "Config.xcconfig ausente ou incompleto. Copie o Config.xcconfig.example."
            case .rede:
                return "Não foi possível falar com o servidor."
            case .resposta(let codigo, _):
                return "O servidor respondeu \(codigo)."
            case .urlInvalida(let caminho, _):
                return "Consulta malformada para \(caminho)."
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

    /// Caracteres que o PostgREST usa como sintaxe e que NÃO podem ser
    /// escapados: `=` separa chave e valor, `.` separa operador (`eq.`, `in.`),
    /// `,` separa itens de lista, `()` delimita `in.(...)`, `*` é o select
    /// completo, `&` separa parâmetros. Tudo o mais — inclusive espaço e aspas —
    /// precisa ser codificado.
    private static let sintaxePostgREST = CharacterSet(
        charactersIn: "=&.,()*:-_~/").union(.alphanumerics)

    /// Codifica a query preservando a sintaxe do PostgREST.
    ///
    /// Existe por um crash real: a consulta de Explorar tinha
    /// `estado=in.("em alta","em queda",pico)` com espaços literais, a URL
    /// ficava inválida e o app morria com SIGTRAP no force-unwrap abaixo.
    static func codificar(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: sintaxePostgREST) ?? query
    }

    /// GET em uma tabela/view exposta, com query PostgREST.
    /// Ex.: `buscar("indices_semanais", "select=*&limit=10")`
    func buscar<T: Decodable>(_ caminho: String, _ query: String) async throws -> [T] {
        guard configurado else { throw Falha.semConfiguracao }

        guard var componentes = URLComponents(
            url: url.appendingPathComponent("rest/v1/\(caminho)"),
            resolvingAgainstBaseURL: false) else {
            throw Falha.urlInvalida(caminho, query)
        }
        componentes.percentEncodedQuery = Supabase.codificar(query)

        // SEM force-unwrap. Uma consulta malformada é bug de programação, mas
        // derrubar o app na cara do usuário é a pior forma possível de reportar
        // isso — vira erro tratado, e a tela mostra falha de consulta.
        guard let enderecoFinal = componentes.url else {
            throw Falha.urlInvalida(caminho, query)
        }
        var req = URLRequest(url: enderecoFinal)
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

    /// Chama uma função do banco (`rpc/`) e decodifica a resposta.
    ///
    /// Existe para o bloco de similares (§29). Poderia ter sido feito com
    /// várias consultas `GET` e a agregação no dispositivo, e seria errado: a
    /// §33 diz **servidor calcula, app consulta**, e trazer 18 mil peças pela
    /// rede para contar quantas estão remarcadas é exatamente o oposto.
    ///
    /// A função roda com o papel `anon`, cujo `statement_timeout` é de 3
    /// segundos — o que restringiu o desenho dela do lado do banco.
    func chamar<T: Decodable>(_ funcao: String, _ argumentos: [String: Any]) async throws -> T {
        guard configurado else { throw Falha.semConfiguracao }
        let endereco = url.appendingPathComponent("rest/v1/rpc/\(funcao)")

        var req = URLRequest(url: endereco)
        req.httpMethod = "POST"
        req.setValue(chave, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: argumentos)

        do {
            let (dados, resposta) = try await sessao.data(for: req)
            let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(codigo) else {
                throw Falha.resposta(codigo, String(data: dados, encoding: .utf8) ?? "")
            }
            return try JSONDecoder().decode(T.self, from: dados)
        } catch let falha as Falha {
            throw falha
        } catch {
            throw Falha.rede(error)
        }
    }
}
