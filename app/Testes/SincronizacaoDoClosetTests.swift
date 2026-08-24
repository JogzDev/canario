import Foundation
import XCTest
@testable import CanarioLogica

private final class ProtocoloSyncFalso: URLProtocol {
    static var responder: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let responder = Self.responder else { throw URLError(.unknown) }
            let (codigo, dados) = try responder(request)
            let resposta = HTTPURLResponse(url: request.url!, statusCode: codigo,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resposta, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: dados)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class SincronizacaoDoClosetTests: XCTestCase {
    func testEnviaJWTEMudancaLocalPeloRPCAtomico() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ProtocoloSyncFalso.self]
        let http = URLSession(configuration: cfg)
        let endpoint = URL(string: "https://conta.supabase.co")!
        let auth = Autenticacao(url: endpoint, chave: "publicavel", sessaoHTTP: http)

        let usuario = "715ed5db-f090-4b8c-a067-640ecee36aa0"
        ProtocoloSyncFalso.responder = { pedido in
            XCTAssertEqual(pedido.url?.path, "/auth/v1/token")
            return (200, Data("""
            {"access_token":"access","refresh_token":"refresh","expires_in":3600,
             "user":{"id":"\(usuario)","email":"person@example.com"}}
            """.utf8))
        }
        _ = try await auth.entrar(email: "person@example.com", senha: "senha-bem-segura")

        let arquivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: arquivo)
            try? FileManager.default.removeItem(
                at: arquivo.deletingPathExtension().appendingPathExtension("exclusoes.json"))
            ProtocoloSyncFalso.responder = nil
        }
        let loja = PecasSalvas(arquivo: arquivo)
        let peca = PecaSalva(apelido: "rugby", termoIds: ["camisa", "listra"])
        await loja.salvar(peca)
        let todas = await loja.todas()
        let salva = try XCTUnwrap(todas.first)
        var leituras = 0

        ProtocoloSyncFalso.responder = { pedido in
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "apikey"), "publicavel")
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            if pedido.url?.path == "/rest/v1/closet_items" {
                leituras += 1
                if leituras == 1 { return (200, Data("[]".utf8)) }
                let data = ISO8601DateFormatter().string(from: salva.atualizadaEm ?? salva.criadaEm)
                return (200, Data("""
                [{"id":"\(salva.id.uuidString)","apelido":"rugby",
                  "termo_ids":["camisa","listra"],"criada_em":"\(data)",
                  "atualizado_em":"\(data)"}]
                """.utf8))
            }
            XCTAssertEqual(pedido.url?.path, "/rest/v1/rpc/aplicar_mudancas_closet")
            let corpo = try JSONSerialization.jsonObject(with: corpoSync(pedido))
                as? [String: [[String: Any]]]
            XCTAssertEqual(corpo?["p_mudancas"]?.first?["apelido"] as? String, "rugby")
            XCTAssertNil(corpo?["p_mudancas"]?.first?["miniatura_arquivo"])
            return (204, Data())
        }

        let sync = SincronizacaoDoCloset(http: http, autenticacao: auth, loja: loja)
        let resultado = try await sync.sincronizar()
        XCTAssertEqual(resultado.itens, 1)
        XCTAssertEqual(leituras, 2)
    }
}

private func corpoSync(_ pedido: URLRequest) -> Data {
    if let dados = pedido.httpBody { return dados }
    guard let fluxo = pedido.httpBodyStream else { return Data() }
    fluxo.open()
    defer { fluxo.close() }
    var resultado = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while fluxo.hasBytesAvailable {
        let lidos = fluxo.read(&buffer, maxLength: buffer.count)
        if lidos <= 0 { break }
        resultado.append(buffer, count: lidos)
    }
    return resultado
}
