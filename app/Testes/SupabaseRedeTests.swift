import Foundation
import XCTest
@testable import CanarioLogica

private final class ProtocoloHTTPFalso: URLProtocol {
    static var responder: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let responder = Self.responder else {
                throw URLError(.unknown)
            }
            let (codigo, dados) = try responder(request)
            let resposta = HTTPURLResponse(
                url: request.url!, statusCode: codigo,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resposta,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: dados)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func corpoDaRequisicao(_ pedido: URLRequest) -> Data {
    if let dados = pedido.httpBody { return dados }
    guard let fluxo = pedido.httpBodyStream else { return Data() }
    fluxo.open()
    defer { fluxo.close() }
    var dados = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }
    while fluxo.hasBytesAvailable {
        let lidos = fluxo.read(buffer, maxLength: 1024)
        if lidos <= 0 { break }
        dados.append(buffer, count: lidos)
    }
    return dados
}

final class SupabaseRedeTests: XCTestCase {
    private struct Linha: Decodable, Equatable {
        let id: Int
        let nome: String
    }

    private func cliente() -> Supabase {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ProtocoloHTTPFalso.self]
        return Supabase(
            url: URL(string: "https://projeto.supabase.co")!,
            chave: "publicavel-teste",
            sessao: URLSession(configuration: cfg),
            esperaEntreTentativas: 0)
    }

    override func tearDown() {
        ProtocoloHTTPFalso.responder = nil
        super.tearDown()
    }

    func testBuscarMontaGETAutenticadoECodificaQuery() async throws {
        ProtocoloHTTPFalso.responder = { pedido in
            XCTAssertEqual(pedido.httpMethod, "GET")
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "apikey"),
                           "publicavel-teste")
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "Authorization"),
                           "Bearer publicavel-teste")
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "Accept"),
                           "application/json")
            XCTAssertEqual(pedido.url?.path, "/rest/v1/itens")
            XCTAssertTrue(pedido.url?.absoluteString.contains("nome=eq.vestido%20midi") == true)
            return (200, Data(#"[{"id":7,"nome":"Midi"}]"#.utf8))
        }

        let linhas: [Linha] = try await cliente().buscar(
            "itens", "select=*&nome=eq.vestido midi")
        XCTAssertEqual(linhas, [Linha(id: 7, nome: "Midi")])
    }

    func testCincoXXRecebeUmaSegundaChance() async throws {
        var chamadas = 0
        ProtocoloHTTPFalso.responder = { _ in
            chamadas += 1
            if chamadas == 1 { return (503, Data(#"{"error":"temporario"}"#.utf8)) }
            return (200, Data(#"[{"id":8,"nome":"Voltou"}]"#.utf8))
        }

        let linhas: [Linha] = try await cliente().buscar("itens", "select=*")
        XCTAssertEqual(chamadas, 2)
        XCTAssertEqual(linhas.first?.nome, "Voltou")
    }

    func testQuatroXXNaoRepeteEPreservaCorpo() async {
        var chamadas = 0
        ProtocoloHTTPFalso.responder = { _ in
            chamadas += 1
            return (401, Data(#"{"error":"negado"}"#.utf8))
        }

        do {
            let _: [Linha] = try await cliente().buscar("itens", "select=*")
            XCTFail("401 deveria falhar")
        } catch Supabase.Falha.resposta(let codigo, let corpo) {
            XCTAssertEqual(codigo, 401)
            XCTAssertTrue(corpo.contains("negado"))
        } catch {
            XCTFail("erro inesperado: \(error)")
        }
        XCTAssertEqual(chamadas, 1)
    }

    func testRPCUsaPOSTJSONEMesmaAutenticacao() async throws {
        ProtocoloHTTPFalso.responder = { pedido in
            XCTAssertEqual(pedido.httpMethod, "POST")
            XCTAssertEqual(pedido.url?.path, "/rest/v1/rpc/resumir")
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "Content-Type"),
                           "application/json")
            XCTAssertEqual(pedido.value(forHTTPHeaderField: "apikey"),
                           "publicavel-teste")
            let corpo = try JSONSerialization.jsonObject(with: corpoDaRequisicao(pedido))
                as? [String: Int]
            XCTAssertEqual(corpo, ["limite": 3])
            return (200, Data(#"{"id":9,"nome":"Resumo"}"#.utf8))
        }

        let linha: Linha = try await cliente().chamar("resumir", ["limite": 3])
        XCTAssertEqual(linha, Linha(id: 9, nome: "Resumo"))
    }

    func testRPCCanceladaContinuaSendoCancelamento() async {
        var chamadas = 0
        ProtocoloHTTPFalso.responder = { _ in
            chamadas += 1
            // Reproduz o erro que URLSession entrega quando a tarefa HTTP e
            // cancelada. Ele atravessa a sessao e `comUmaSegundaChance`; a
            // fronteira publica da RPC nao pode embrulha-lo em `Falha.rede`.
            throw URLError(.cancelled)
        }

        do {
            let _: Linha = try await cliente().chamar("resumir", ["limite": 3])
            XCTFail("uma RPC cancelada deveria interromper o fluxo")
        } catch is CancellationError {
            // Contrato esperado: a tela consegue calar o cancelamento.
        } catch {
            XCTFail("cancelamento foi transformado em falha: \(error)")
        }
        XCTAssertEqual(chamadas, 1, "cancelamento nao pode receber retry")
    }
}
