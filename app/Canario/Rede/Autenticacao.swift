import Foundation
import CryptoKit
import Security

struct UsuarioDaConta: Codable, Equatable, Sendable {
    let id: UUID
    let email: String?
    let provedores: [String]?

    init(id: UUID, email: String?, provedores: [String]? = nil) {
        self.id = id
        self.email = email
        self.provedores = provedores
    }
}

struct SessaoDaConta: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiraEm: Date
    let usuario: UsuarioDaConta

    var precisaRenovar: Bool { expiraEm.timeIntervalSinceNow < 90 }
}

enum ProvedorDaConta: String, Sendable {
    case apple
    case google
}

struct ContextoAutenticado: Sendable {
    let url: URL
    let chavePublicavel: String
    let sessao: SessaoDaConta
}

struct DesafioOAuth: Sendable {
    let endereco: URL
    let verificador: String
}

/// O login pode funcionar mesmo se uma conta Apple antiga não tiver entregue
/// um refresh token. Essa informação não é de produto: ela só permite que a
/// interface seja honesta, no momento da exclusão, sobre revogação automática
/// ou o caminho manual oficial da Apple.
struct ResultadoDaExclusao: Sendable {
    let exigeRevogacaoManualApple: Bool
}

/// Cliente pequeno para o contrato HTTP público do Supabase Auth.
///
/// O app já tem uma camada de rede própria e não precisa incorporar um SDK
/// inteiro para cinco endpoints. Senhas e tokens de provedor atravessam apenas
/// TLS e nunca são gravados em log. A única credencial persistida é a sessão,
/// no Keychain do aparelho.
actor Autenticacao {
    static let shared = Autenticacao()

    enum Falha: LocalizedError, Equatable {
        case semConfiguracao
        case emailInvalido
        case senhaCurta
        case callbackInvalido
        case resposta(Int, String)
        case rede

        var errorDescription: String? {
            switch self {
            case .semConfiguracao:
                return "Account sync is not configured in this build. You can keep using DataDrobe without an account."
            case .emailInvalido:
                return "Enter a valid email address."
            case .senhaCurta:
                return "Use at least 10 characters for your password."
            case .callbackInvalido:
                return "The sign-in response could not be verified. Please try again."
            case .rede:
                return "The account service could not be reached. Your local Closet is still available."
            case .resposta(let codigo, let mensagem):
                if codigo == 400 && mensagem.lowercased().contains("invalid login") {
                    return "The email or password is incorrect."
                }
                if codigo == 429 {
                    return "Too many attempts. Wait a moment and try again."
                }
                return mensagem.isEmpty ? "The account service returned HTTP \(codigo)." : mensagem
            }
        }
    }

    private struct RespostaAuth: Decodable {
        struct Usuario: Decodable {
            struct Metadados: Decodable { let providers: [String]? }
            let id: UUID
            let email: String?
            let appMetadata: Metadados?

            enum CodingKeys: String, CodingKey {
                case id, email
                case appMetadata = "app_metadata"
            }
        }

        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?
        let expiresAt: Double?
        let user: Usuario?

        enum CodingKeys: String, CodingKey {
            case user
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
        }
    }

    private struct RespostaDeErro: Decodable {
        let msg: String?
        let message: String?
        let errorDescription: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case msg, message, error
            case errorDescription = "error_description"
        }

        var texto: String { errorDescription ?? msg ?? message ?? error ?? "" }
    }

    private struct RespostaDeExclusao: Decodable {
        let appleRevocation: String?

        enum CodingKeys: String, CodingKey {
            case appleRevocation = "apple_revocation"
        }
    }

    private let url: URL
    private let chave: String
    private let sessaoHTTP: URLSession
    private let callback = "datadrobe://auth-callback"
    private var sessaoEmMemoria: SessaoDaConta?

    init() {
        let info = Bundle.main.infoDictionary
        let urlConta = Self.valorConfigurado(info?["AUTH_SUPABASE_URL"] as? String)
            ?? Self.valorConfigurado(info?["SUPABASE_URL"] as? String)
            ?? ""
        let chaveConta = Self.valorConfigurado(info?["AUTH_SUPABASE_PUBLISHABLE_KEY"] as? String)
            ?? Self.valorConfigurado(info?["SUPABASE_PUBLISHABLE_KEY"] as? String)
            ?? ""
        let normalizada = urlConta.hasPrefix("http") ? urlConta : "https://\(urlConta)"
        self.url = URL(string: normalizada) ?? URL(string: "https://invalido.invalido")!
        self.chave = chaveConta

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.sessaoHTTP = URLSession(configuration: cfg)
        self.sessaoEmMemoria = CofreDaConta.ler()
    }

    init(url: URL, chave: String, sessaoHTTP: URLSession) {
        self.url = url
        self.chave = chave
        self.sessaoHTTP = sessaoHTTP
        self.sessaoEmMemoria = nil
    }

    var configurada: Bool { !chave.isEmpty && url.host != "invalido.invalido" }

    func sessaoAtual() async -> SessaoDaConta? {
        guard var atual = sessaoEmMemoria else { return nil }
        if atual.precisaRenovar {
            do {
                atual = try await renovar(com: atual.refreshToken)
                guardar(atual)
            } catch {
                // Uma queda de rede não transforma uma sessão ainda válida em
                // logout. Se ela já expirou, fecha para não usar JWT inválido.
                if atual.expiraEm <= Date() { limparSessao() }
            }
        }
        return sessaoEmMemoria
    }

    func contextoAtual() async -> ContextoAutenticado? {
        guard configurada, let sessao = await sessaoAtual() else { return nil }
        return ContextoAutenticado(url: url, chavePublicavel: chave, sessao: sessao)
    }

    func entrar(email: String, senha: String) async throws -> SessaoDaConta {
        try validar(email: email, senha: senha)
        return try await autenticar(
            caminho: "token", query: "grant_type=password",
            corpo: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines),
                    "password": senha])
    }

    func cadastrar(email: String, senha: String) async throws -> SessaoDaConta? {
        try validar(email: email, senha: senha)
        let dados = try await pedir(
            caminho: "signup", query: consultaDeRetorno, metodo: "POST",
            corpo: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines),
                    "password": senha])
        let resposta = try JSONDecoder.supabase.decode(RespostaAuth.self, from: dados)
        guard resposta.accessToken != nil else { return nil }
        return try materializar(resposta)
    }

    func recuperarSenha(email: String) async throws {
        guard Self.emailValido(email) else { throw Falha.emailInvalido }
        _ = try await pedir(
            caminho: "recover", query: consultaDeRetorno, metodo: "POST",
            corpo: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    func atualizarSenha(_ senha: String) async throws {
        guard senha.count >= 10 else { throw Falha.senhaCurta }
        guard let atual = await sessaoAtual() else { throw Falha.callbackInvalido }
        _ = try await pedir(caminho: "user", metodo: "PUT",
                            corpo: ["password": senha], bearer: atual.accessToken)
    }

    func entrarComToken(_ token: String, provedor: ProvedorDaConta,
                        nonce: String?) async throws -> SessaoDaConta {
        var corpo: [String: Any] = ["provider": provedor.rawValue, "id_token": token]
        if let nonce, !nonce.isEmpty { corpo["nonce"] = nonce }
        return try await autenticar(caminho: "token", query: "grant_type=id_token", corpo: corpo)
    }

    /// No native Sign in with Apple, o `identityToken` autentica a conta no
    /// Supabase e o `authorizationCode` de uso único permite ao nosso servidor
    /// obter o refresh token que a Apple exige para revogação posterior.
    ///
    /// Não se recusa o login por uma falha de infraestrutura nessa segunda
    /// etapa: a pessoa ainda precisa poder entrar e excluir os próprios dados.
    /// Sem a credencial, a exclusão mostra o fluxo manual oficial da Apple.
    func entrarComApple(_ token: String, nonce: String?,
                        codigoDeAutorizacao: String?) async throws -> SessaoDaConta {
        let sessao = try await entrarComToken(token, provedor: .apple, nonce: nonce)
        guard let codigoDeAutorizacao, !codigoDeAutorizacao.isEmpty else { return sessao }
        do {
            try await registrarCredencialApple(codigoDeAutorizacao, sessao: sessao)
        } catch {
            // O código não atravessa logs nem armazenamento local. A sessão
            // continua válida; `excluir-conta` sinalizará a alternativa manual.
        }
        return sessao
    }

    func desafioOAuthGoogle() throws -> DesafioOAuth {
        guard configurada else { throw Falha.semConfiguracao }
        let verificador = Self.segredoAleatorio(comprimento: 64)
        let resumo = SHA256.hash(data: Data(verificador.utf8))
        let desafio = Data(resumo).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var componentes = URLComponents(url: url.appendingPathComponent("auth/v1/authorize"),
                                        resolvingAgainstBaseURL: false)
        componentes?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: callback),
            URLQueryItem(name: "scopes", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: desafio),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        guard let final = componentes?.url else { throw Falha.semConfiguracao }
        return DesafioOAuth(endereco: final, verificador: verificador)
    }

    func receberCallback(_ endereco: URL, verificadorPKCE: String? = nil) async throws -> SessaoDaConta {
        guard endereco.scheme == "datadrobe", endereco.host == "auth-callback" else {
            throw Falha.callbackInvalido
        }
        let texto = endereco.absoluteString.replacingOccurrences(of: "#", with: "?")
        guard let componentes = URLComponents(string: texto) else { throw Falha.callbackInvalido }
        let valores = Dictionary(uniqueKeysWithValues:
            (componentes.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let erro = valores["error_description"] ?? valores["error"] {
            throw Falha.resposta(400, erro)
        }
        if let codigo = valores["code"], let verificadorPKCE, !codigo.isEmpty {
            return try await autenticar(
                caminho: "token", query: "grant_type=pkce",
                corpo: ["auth_code": codigo, "code_verifier": verificadorPKCE])
        }
        guard let access = valores["access_token"], !access.isEmpty,
              let refresh = valores["refresh_token"], !refresh.isEmpty,
              let usuario = Self.usuarioDoJWT(access) else {
            throw Falha.callbackInvalido
        }
        let segundos = Double(valores["expires_in"] ?? "3600") ?? 3600
        let nova = SessaoDaConta(accessToken: access, refreshToken: refresh,
                                 expiraEm: Date().addingTimeInterval(segundos), usuario: usuario)
        guardar(nova)
        return nova
    }

    func sair() async {
        if let atual = sessaoEmMemoria {
            _ = try? await pedir(caminho: "logout", metodo: "POST",
                                 corpo: nil, bearer: atual.accessToken)
        }
        limparSessao()
    }

    func solicitarExclusao() async throws -> ResultadoDaExclusao {
        guard let atual = await sessaoAtual() else { throw Falha.callbackInvalido }
        let endpoint = url.appendingPathComponent("functions/v1/excluir-conta")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(chave, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(atual.accessToken)", forHTTPHeaderField: "Authorization")
        let (dados, resposta) = try await sessaoHTTP.data(for: req)
        let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(codigo) else {
            throw Falha.resposta(codigo, "The account could not be deleted. Please try again.")
        }
        let respostaDaExclusao = try? JSONDecoder().decode(RespostaDeExclusao.self, from: dados)
        let usavaApple = atual.usuario.provedores?.contains("apple") == true
        limparSessao()
        return ResultadoDaExclusao(
            exigeRevogacaoManualApple: usavaApple
                && respostaDaExclusao?.appleRevocation != "revoked")
    }

    private func registrarCredencialApple(_ codigo: String,
                                          sessao: SessaoDaConta) async throws {
        guard configurada else { throw Falha.semConfiguracao }
        let endpoint = url.appendingPathComponent("functions/v1/registrar-credencial-apple")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(chave, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(sessao.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "authorization_code": codigo,
        ])
        let (_, resposta) = try await sessaoHTTP.data(for: req)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Falha.resposta(status, "Apple authorization could not be prepared for account deletion.")
        }
    }

    private func autenticar(caminho: String, query: String,
                             corpo: [String: Any]) async throws -> SessaoDaConta {
        let dados = try await pedir(caminho: caminho, query: query,
                                    metodo: "POST", corpo: corpo)
        let resposta = try JSONDecoder.supabase.decode(RespostaAuth.self, from: dados)
        return try materializar(resposta)
    }

    private func renovar(com refresh: String) async throws -> SessaoDaConta {
        let dados = try await pedir(caminho: "token", query: "grant_type=refresh_token",
                                    metodo: "POST", corpo: ["refresh_token": refresh])
        return try materializar(JSONDecoder.supabase.decode(RespostaAuth.self, from: dados))
    }

    private func materializar(_ resposta: RespostaAuth) throws -> SessaoDaConta {
        guard let access = resposta.accessToken, let refresh = resposta.refreshToken else {
            throw Falha.callbackInvalido
        }
        let usuario: UsuarioDaConta
        if let recebido = resposta.user {
            usuario = UsuarioDaConta(
                id: recebido.id, email: recebido.email,
                provedores: recebido.appMetadata?.providers)
        } else if let extraido = Self.usuarioDoJWT(access) {
            usuario = extraido
        } else {
            throw Falha.callbackInvalido
        }
        let expira: Date
        if let timestamp = resposta.expiresAt {
            expira = Date(timeIntervalSince1970: timestamp)
        } else {
            expira = Date().addingTimeInterval(resposta.expiresIn ?? 3600)
        }
        let nova = SessaoDaConta(accessToken: access, refreshToken: refresh,
                                 expiraEm: expira, usuario: usuario)
        guardar(nova)
        return nova
    }

    private func pedir(caminho: String, query: String? = nil, metodo: String,
                       corpo: [String: Any]?, bearer: String? = nil) async throws -> Data {
        guard configurada else { throw Falha.semConfiguracao }
        var componentes = URLComponents(
            url: url.appendingPathComponent("auth/v1/\(caminho)"),
            resolvingAgainstBaseURL: false)
        componentes?.percentEncodedQuery = query
        guard let final = componentes?.url else { throw Falha.semConfiguracao }
        var req = URLRequest(url: final)
        req.httpMethod = metodo
        req.setValue(chave, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(bearer ?? chave)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let corpo {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        }
        do {
            let (dados, resposta) = try await sessaoHTTP.data(for: req)
            let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(codigo) else {
                let erro = try? JSONDecoder().decode(RespostaDeErro.self, from: dados)
                throw Falha.resposta(codigo, erro?.texto ?? "")
            }
            return dados
        } catch let falha as Falha {
            throw falha
        } catch {
            throw Falha.rede
        }
    }

    private func validar(email: String, senha: String) throws {
        guard Self.emailValido(email) else { throw Falha.emailInvalido }
        guard senha.count >= 10 else { throw Falha.senhaCurta }
    }

    private var consultaDeRetorno: String {
        var componentes = URLComponents()
        componentes.queryItems = [URLQueryItem(name: "redirect_to", value: callback)]
        return componentes.percentEncodedQuery ?? ""
    }

    static func emailValido(_ email: String) -> Bool {
        let partes = email.split(separator: "@", omittingEmptySubsequences: false)
        return partes.count == 2 && partes[0].count >= 1 && partes[1].contains(".")
    }

    static func tipoDoCallback(_ endereco: URL) -> String? {
        let texto = endereco.absoluteString.replacingOccurrences(of: "#", with: "?")
        return URLComponents(string: texto)?.queryItems?
            .first(where: { $0.name == "type" })?.value
    }

    private static func valorConfigurado(_ valor: String?) -> String? {
        guard let valor else { return nil }
        let limpo = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty, !limpo.hasPrefix("$(") else { return nil }
        return limpo
    }

    private static func usuarioDoJWT(_ token: String) -> UsuarioDaConta? {
        let partes = token.split(separator: ".")
        guard partes.count >= 2 else { return nil }
        var base64 = String(partes[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let dados = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let sub = json["sub"] as? String, let id = UUID(uuidString: sub) else { return nil }
        let metadados = json["app_metadata"] as? [String: Any]
        return UsuarioDaConta(
            id: id, email: json["email"] as? String,
            provedores: metadados?["providers"] as? [String])
    }

    private static func segredoAleatorio(comprimento: Int) -> String {
        let alfabeto = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._~")
        var bytes = [UInt8](repeating: 0, count: comprimento)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { alfabeto[Int($0) % alfabeto.count] })
    }

    private func guardar(_ sessao: SessaoDaConta) {
        sessaoEmMemoria = sessao
        CofreDaConta.gravar(sessao)
    }

    private func limparSessao() {
        sessaoEmMemoria = nil
        CofreDaConta.apagar()
    }
}

private enum CofreDaConta {
    private static let servico = "br.com.canario.ch3.app.auth"
    private static let conta = "supabase-session"

    static func gravar(_ sessao: SessaoDaConta) {
        guard let dados = try? JSONEncoder().encode(sessao) else { return }
        apagar()
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: conta,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: dados,
        ]
        SecItemAdd(consulta as CFDictionary, nil)
    }

    static func ler() -> SessaoDaConta? {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: conta,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let dados = resultado as? Data else { return nil }
        return try? JSONDecoder().decode(SessaoDaConta.self, from: dados)
    }

    static func apagar() {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: conta,
        ]
        SecItemDelete(consulta as CFDictionary)
    }
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
