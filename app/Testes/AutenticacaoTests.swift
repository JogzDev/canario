import Foundation
import XCTest
@testable import CanarioLogica

private final class ProtocoloAuthFalso: URLProtocol {
    static var responder: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let responder = Self.responder else { throw URLError(.unknown) }
            let (codigo, dados) = try responder(request)
            let resposta = HTTPURLResponse(
                url: request.url!, statusCode: codigo, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resposta, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: dados)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class AutenticacaoTests: XCTestCase {
    private let usuario = "715ed5db-f090-4b8c-a067-640ecee36aa0"

    private func cliente() -> Autenticacao {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ProtocoloAuthFalso.self]
        return Autenticacao(
            url: URL(string: "https://conta.supabase.co")!,
            chave: "publicavel-conta",
            sessaoHTTP: URLSession(configuration: cfg))
    }

    override func tearDown() {
        ProtocoloAuthFalso.responder = nil
        super.tearDown()
    }

    func testEndpointDaContaExigeHTTPS() {
        XCTAssertEqual(Autenticacao.endpointSeguro("conta.supabase.co").absoluteString,
                       "https://conta.supabase.co")
        XCTAssertEqual(Autenticacao.endpointSeguro("https://conta.supabase.co").host,
                       "conta.supabase.co")
        XCTAssertEqual(Autenticacao.endpointSeguro("http://conta.supabase.co").host,
                       "invalido.invalido")
    }

    func testEmailESenhaUsamTokenPasswordSemLogicaAdministrativa() async throws {
        ProtocoloAuthFalso.responder = { [usuario] pedido in
            XCTAssertEqual(pedido.url?.path, "/auth/v1/token")
            XCTAssertEqual(pedido.url?.query, "grant_type=password")
            XCTAssertEqual(pedido.httpMethod, "POST")
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "apikey"), "publicavel-conta")
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "Authorization"),
                           "Bearer publicavel-conta")
            let corpo = try JSONSerialization.jsonObject(with: corpoAuth(pedido))
                as? [String: String]
            XCTAssertEqual(corpo?["email"], "person@example.com")
            XCTAssertEqual(corpo?["password"], "uma-senha-segura")
            return (200, Data("""
            {"access_token":"access","refresh_token":"refresh","expires_in":3600,
             "user":{"id":"\(usuario)","email":"person@example.com"}}
            """.utf8))
        }

        let sessao = try await cliente().entrar(
            email: "person@example.com", senha: "uma-senha-segura")
        XCTAssertEqual(sessao.usuario.id.uuidString.lowercased(), usuario)
        XCTAssertEqual(sessao.usuario.email, "person@example.com")
    }

    func testSenhaCurtaFalhaAntesDaRede() async {
        ProtocoloAuthFalso.responder = { _ in
            XCTFail("senha inválida não deve atravessar a rede")
            return (500, Data())
        }
        do {
            _ = try await cliente().entrar(email: "person@example.com", senha: "curta")
            XCTFail("deveria recusar")
        } catch Autenticacao.Falha.senhaCurta {
            // correto
        } catch {
            XCTFail("erro inesperado: \(error)")
        }
    }

    func testCadastroSemSessaoExplicaConfirmacaoPorEmail() async throws {
        ProtocoloAuthFalso.responder = { pedido in
            XCTAssertEqual(pedido.url?.path, "/auth/v1/signup")
            XCTAssertEqual(pedido.url?.query, "redirect_to=datadrobe://auth-callback")
            return (200, Data(#"{"user":{"id":"715ed5db-f090-4b8c-a067-640ecee36aa0","email":"person@example.com"}}"#.utf8))
        }
        let sessao = try await cliente().cadastrar(
            email: "person@example.com", senha: "uma-senha-segura")
        XCTAssertNil(sessao)
    }

    func testCallbackOAuthExtraiIdentidadeDoJWTSemConfiarEmTextoDaTela() async throws {
        let cabecalho = Data(#"{"alg":"none"}"#.utf8).base64URLEncodedString()
        let payload = Data("""
        {"sub":"\(usuario)","email":"google@example.com"}
        """.utf8).base64URLEncodedString()
        let jwt = "\(cabecalho).\(payload).assinatura"
        let url = try XCTUnwrap(URL(string:
            "datadrobe://auth-callback#access_token=\(jwt)&refresh_token=refresh&expires_in=3600"))

        let sessao = try await cliente().receberCallback(url)
        XCTAssertEqual(sessao.usuario.email, "google@example.com")
        XCTAssertEqual(sessao.usuario.id.uuidString.lowercased(), usuario)
    }

    func testGoogleUsaPKCES256ENaoMandaOVerificadorNoEndereco() async throws {
        let desafio = try await cliente().desafioOAuthGoogle()
        let itens = try XCTUnwrap(URLComponents(
            url: desafio.endereco, resolvingAgainstBaseURL: false)?.queryItems)
        let valores = Dictionary(uniqueKeysWithValues: itens.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(valores["provider"], "google")
        XCTAssertEqual(valores["code_challenge_method"], "s256")
        XCTAssertGreaterThanOrEqual(desafio.verificador.count, 43)
        XCTAssertNotEqual(valores["code_challenge"], desafio.verificador)
        XCTAssertFalse(desafio.endereco.absoluteString.contains(desafio.verificador))
    }

    func testCallbackPKCETrocaCodigoUmaVezComOVerificadorLocal() async throws {
        ProtocoloAuthFalso.responder = { [usuario] pedido in
            XCTAssertEqual(pedido.url?.query, "grant_type=pkce")
            let corpo = try JSONSerialization.jsonObject(with: corpoAuth(pedido))
                as? [String: String]
            XCTAssertEqual(corpo?["auth_code"], "codigo-unico")
            XCTAssertEqual(corpo?["code_verifier"], "verificador-local")
            return (200, Data("""
            {"access_token":"access","refresh_token":"refresh","expires_in":3600,
             "user":{"id":"\(usuario)","email":"google@example.com",
             "app_metadata":{"providers":["google"]}}}
            """.utf8))
        }
        let url = try XCTUnwrap(URL(string: "datadrobe://auth-callback?code=codigo-unico"))
        let sessao = try await cliente().receberCallback(
            url, verificadorPKCE: "verificador-local")
        XCTAssertEqual(sessao.usuario.provedores, ["google"])
    }

    func testCallbackDeRecuperacaoEIdentificadoAntesDeTrocarASenha() {
        let url = URL(string: "datadrobe://auth-callback#type=recovery&access_token=x")!
        XCTAssertEqual(Autenticacao.tipoDoCallback(url), "recovery")
    }

    func testAppleGuardaCodigoDeAutorizacaoNoServidorEAvisaFallbackNaExclusao() async throws {
        var chamadas: [URLRequest] = []
        ProtocoloAuthFalso.responder = { [usuario] pedido in
            chamadas.append(pedido)
            switch pedido.url?.path {
            case "/auth/v1/token":
                return (200, Data("""
                {"access_token":"access-apple","refresh_token":"refresh","expires_in":3600,
                 "user":{"id":"\(usuario)","email":"relay@privaterelay.appleid.com",
                 "app_metadata":{"providers":["apple"]}}}
                """.utf8))
            case "/functions/v1/registrar-credencial-apple":
                XCTAssertEqual(pedido.value(forHTTPHeaderField: "Authorization"),
                               "Bearer access-apple")
                let corpo = try JSONSerialization.jsonObject(with: corpoAuth(pedido))
                    as? [String: String]
                XCTAssertEqual(corpo?["authorization_code"], "codigo-apple-unico")
                return (200, Data(#"{"stored":true,"reused":false}"#.utf8))
            case "/functions/v1/excluir-conta":
                return (200, Data(#"{"deleted":true,"apple_revocation":"manual_required"}"#.utf8))
            default:
                XCTFail("caminho inesperado: \(pedido.url?.path ?? "sem caminho")")
                return (500, Data())
            }
        }

        let conta = cliente()
        _ = try await conta.entrarComApple("id-token", nonce: "nonce-original",
                                           codigoDeAutorizacao: "codigo-apple-unico")
        let exclusao = try await conta.solicitarExclusao()

        XCTAssertEqual(chamadas.map { $0.url?.path }, [
            "/auth/v1/token",
            "/functions/v1/registrar-credencial-apple",
            "/functions/v1/excluir-conta",
        ])
        XCTAssertTrue(exclusao.exigeRevogacaoManualApple)
    }
}

private func corpoAuth(_ pedido: URLRequest) -> Data {
    if let dados = pedido.httpBody { return dados }
    guard let fluxo = pedido.httpBodyStream else { return Data() }
    fluxo.open()
    defer { fluxo.close() }
    var resultado = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while fluxo.hasBytesAvailable {
        let lidos = fluxo.read(&buffer, maxLength: buffer.count)
        if lidos <= 0 { break }
        resultado.append(buffer, count: lidos)
    }
    return resultado
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
