import Foundation
import CryptoKit
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
        let peca = PecaSalva(apelido: "rugby", termoIds: ["camisa", "listra"],
                             detalhesVisuais: ["abotoamento duplo"])
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
            XCTAssertNil(corpo?["p_mudancas"]?.first?["detalhesVisuais"])
            XCTAssertNil(corpo?["p_mudancas"]?.first?["detalhes_visuais"])
            return (204, Data())
        }

        let sync = SincronizacaoDoCloset(http: http, autenticacao: auth, loja: loja)
        let resultado = try await sync.sincronizar()
        XCTAssertEqual(resultado.itens, 1)
        XCTAssertEqual(leituras, 2)
    }

    func testEnviaMiniaturaPrivadaUmaVezEIncluiHashNoContrato() async throws {
        let ambiente = try await prepararAmbiente()
        defer { ambiente.limpar() }
        let dadosDaFoto = Data([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4])
        let peca = PecaSalva(apelido: "rugby", termoIds: ["camisa"])
        let foiSalva = await ambiente.loja.salvar(peca, miniaturaDados: dadosDaFoto)
        XCTAssertTrue(foiSalva)
        let todasDepoisDeSalvar = await ambiente.loja.todas()
        let salva = try XCTUnwrap(todasDepoisDeSalvar.first)
        var leituras = 0
        var uploads = 0

        ProtocoloSyncFalso.responder = { pedido in
            if pedido.url?.path == "/rest/v1/closet_items" {
                leituras += 1
                if leituras == 1 { return (200, Data("[]".utf8)) }
                let atualizada = ISO8601DateFormatter().string(
                    from: salva.atualizadaEm ?? salva.criadaEm)
                return (200, Data("""
                [{"id":"\(salva.id.uuidString)","apelido":"rugby",
                  "termo_ids":["camisa"],"criada_em":"\(atualizada)",
                  "miniatura_hash":"\(hashTeste(dadosDaFoto))",
                  "miniatura_extensao":"png","atualizado_em":"\(atualizada)"}]
                """.utf8))
            }
            if pedido.url?.path.contains("/storage/v1/object/closet-thumbnails/") == true {
                uploads += 1
                XCTAssertEqual(pedido.httpMethod, "POST")
                XCTAssertEqual(corpoSync(pedido), dadosDaFoto)
                XCTAssertEqual(pedido.value(forHTTPHeaderField: "x-upsert"), "true")
                return (200, Data("{}".utf8))
            }
            let corpo = try JSONSerialization.jsonObject(with: corpoSync(pedido))
                as? [String: [[String: Any]]]
            let primeira = corpo?["p_mudancas"]?.first
            XCTAssertEqual(primeira?["miniatura_extensao"] as? String, "png")
            XCTAssertEqual((primeira?["miniatura_hash"] as? String)?.count, 64)
            return (204, Data())
        }

        let sync = SincronizacaoDoCloset(
            http: ambiente.http, autenticacao: ambiente.auth, loja: ambiente.loja)
        _ = try await sync.sincronizar()
        XCTAssertEqual(uploads, 1)
    }

    func testRestauraMiniaturaPrivadaQuandoOArquivoLocalNaoExiste() async throws {
        let ambiente = try await prepararAmbiente()
        defer { ambiente.limpar() }
        let dadosDaFoto = Data([0xFF, 0xD8, 0xFF, 0xE0, 8, 7, 6, 5])
        let id = UUID()
        let agora = ISO8601DateFormatter().string(from: Date())
        let remoto = Data("""
        [{"id":"\(id.uuidString)","apelido":"restored",
          "termo_ids":["camisa"],"criada_em":"\(agora)",
          "miniatura_hash":"\(hashTeste(dadosDaFoto))",
          "miniatura_extensao":"jpg","atualizado_em":"\(agora)"}]
        """.utf8)
        var downloads = 0

        ProtocoloSyncFalso.responder = { pedido in
            if pedido.url?.path == "/rest/v1/closet_items" { return (200, remoto) }
            if pedido.url?.path.contains("/storage/v1/object/authenticated/") == true {
                downloads += 1
                XCTAssertEqual(pedido.httpMethod, "GET")
                return (200, dadosDaFoto)
            }
            return (204, Data())
        }

        let sync = SincronizacaoDoCloset(
            http: ambiente.http, autenticacao: ambiente.auth, loja: ambiente.loja)
        _ = try await sync.sincronizar()
        let restauradas = await ambiente.loja.todas()
        let peca = try XCTUnwrap(restauradas.first)
        let miniatura = await ambiente.loja.miniatura(de: peca)
        XCTAssertEqual(miniatura, dadosDaFoto)
        XCTAssertEqual(downloads, 1)
    }

    private func prepararAmbiente() async throws -> AmbienteDeSync {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ProtocoloSyncFalso.self]
        let http = URLSession(configuration: cfg)
        let auth = Autenticacao(url: URL(string: "https://conta.supabase.co")!,
                                chave: "publicavel", sessaoHTTP: http)
        let usuario = "715ed5db-f090-4b8c-a067-640ecee36aa0"
        ProtocoloSyncFalso.responder = { _ in
            (200, Data("""
            {"access_token":"access","refresh_token":"refresh","expires_in":3600,
             "user":{"id":"\(usuario)","email":"person@example.com"}}
            """.utf8))
        }
        _ = try await auth.entrar(email: "person@example.com", senha: "senha-bem-segura")
        let arquivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-photo-\(UUID().uuidString).json")
        let pasta = arquivo.deletingLastPathComponent()
            .appendingPathComponent("thumbs-\(UUID().uuidString)", isDirectory: true)
        return AmbienteDeSync(http: http, auth: auth,
                              loja: PecasSalvas(arquivo: arquivo, pastaDeMiniaturas: pasta),
                              arquivo: arquivo, pasta: pasta)
    }
}

private struct AmbienteDeSync {
    let http: URLSession
    let auth: Autenticacao
    let loja: PecasSalvas
    let arquivo: URL
    let pasta: URL

    func limpar() {
        try? FileManager.default.removeItem(at: arquivo)
        try? FileManager.default.removeItem(
            at: arquivo.deletingPathExtension().appendingPathExtension("exclusoes.json"))
        try? FileManager.default.removeItem(at: pasta)
        ProtocoloSyncFalso.responder = nil
    }
}

private func hashTeste(_ dados: Data) -> String {
    SHA256.hash(data: dados).map { String(format: "%02x", $0) }.joined()
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
