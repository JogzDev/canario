import XCTest
@testable import CanarioLogica

/// Testes de "Minhas peças" — e da linha da §34.
///
/// O teste central aqui não é de comportamento, é de **promessa**: a §34 exclui
/// closet e monitoramento contínuo por peça, e a diferença entre "lista de
/// trabalho" e "armário" mora inteira em *o que a peça guarda*. Se um dia
/// alguém acrescentar `indice`, `estado`, `z` ou `ultimaLeitura` a `PecaSalva`,
/// o app passa a poder dizer "sua peça caiu desde a semana passada" — que é
/// exatamente o produto que a §34 proíbe, e que o dado não sustenta.
///
/// `testPecaSalvaNaoGuardaNumeroCalculado` é essa trava.
final class PecasSalvasTests: XCTestCase {

    private func arquivoTemporario() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pecas-\(UUID().uuidString).json")
    }

    private func pastaTemporaria() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("miniaturas-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - A linha da §34

    func testPecaSalvaNaoGuardaNumeroCalculado() throws {
        let peca = PecaSalva(termoIds: ["vestido", "floral"])
        let dados = try JSONEncoder().encode(peca)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: dados) as? [String: Any])

        // A peça guarda só o que o usuário digitou. Todo número é recalculado
        // do dado de hoje quando a tela abre.
        let proibidos = ["indice", "estado", "z", "ultimaLeitura", "semana",
                         "variacao", "pernas", "nPernas", "indiceAnterior"]
        for campo in proibidos {
            XCTAssertNil(
                json[campo],
                """
                `PecaSalva` ganhou o campo `\(campo)`. Guardar número calculado \
                transforma a lista de trabalho em armário, e a §34 exclui \
                monitoramento contínuo por peça — o app passaria a poder dizer \
                "sua peça caiu desde a semana passada" sobre uma peça que não \
                está no painel.
                """)
        }
        XCTAssertEqual(Set(json.keys),
                       ["id", "apelido", "termoIds", "criadaEm"],
                       "campos opcionais nulos não são gravados; o resto é o que o usuário digitou")
    }

    // MARK: - Nome

    func testNomeUsaOsRotulosDoServidor() {
        let p = PecaSalva(termoIds: ["vestido", "floral"])
        XCTAssertEqual(
            p.nome(comRotulos: ["vestido": "Vestido", "floral": "Floral"]),
            "Vestido · Floral")
    }

    func testApelidoDoUsuarioGanhaDoRotuloDerivado() {
        let p = PecaSalva(apelido: "a do desfile", termoIds: ["vestido"])
        XCTAssertEqual(p.nome(comRotulos: ["vestido": "Vestido"]), "a do desfile")
    }

    func testSemTaxonomiaCarregadaCaiNoId() {
        // Não inventa rótulo: mostra o id, que é feio e verdadeiro.
        let p = PecaSalva(termoIds: ["viscose_fluido"])
        XCTAssertEqual(p.nome(comRotulos: [:]), "viscose_fluido")
    }

    func testPecaSemAtributosTemNomeHonesto() {
        let p = PecaSalva(termoIds: [])
        XCTAssertEqual(p.nome(comRotulos: [:]), "Item without attributes")
    }

    // MARK: - Persistência

    func testSalvaRecarregaEApaga() async throws {
        let arquivo = arquivoTemporario()
        defer { try? FileManager.default.removeItem(at: arquivo) }

        let loja = PecasSalvas(arquivo: arquivo)
        let p = PecaSalva(apelido: "camisa listrada", termoIds: ["camisa", "listra"])
        await loja.salvar(p)
        let salvas = await loja.todas()
        XCTAssertEqual(salvas.count, 1)
        XCTAssertEqual(salvas.first?.apelido, "camisa listrada")

        // Outra instância lendo o mesmo arquivo: é o que acontece ao reabrir
        // o app.
        let outra = PecasSalvas(arquivo: arquivo)
        let daOutra = await outra.todas()
        XCTAssertEqual(daOutra.count, 1)

        await loja.apagar(p.id)
        let depoisDeApagar = await loja.todas()
        XCTAssertEqual(depoisDeApagar.count, 0)
    }

    func testSalvarDuasVezesAtualizaEmVezDeDuplicar() async throws {
        let arquivo = arquivoTemporario()
        defer { try? FileManager.default.removeItem(at: arquivo) }
        let loja = PecasSalvas(arquivo: arquivo)

        var p = PecaSalva(apelido: "primeira", termoIds: ["camisa"])
        await loja.salvar(p)
        p.apelido = "corrigida"
        await loja.salvar(p)

        let todas = await loja.todas()
        XCTAssertEqual(todas.count, 1, "editar não pode criar peça nova")
        XCTAssertEqual(todas.first?.apelido, "corrigida")
    }

    func testMergeRemotoMaisNovoGanhaSemDuplicar() async throws {
        let arquivo = arquivoTemporario()
        defer {
            try? FileManager.default.removeItem(at: arquivo)
            try? FileManager.default.removeItem(
                at: arquivo.deletingPathExtension().appendingPathExtension("exclusoes.json"))
        }
        let loja = PecasSalvas(arquivo: arquivo)
        let id = UUID()
        await loja.salvar(PecaSalva(id: id, apelido: "local", termoIds: ["camisa"]))
        let remoto = PecaSalva(
            id: id, apelido: "outro iPhone", termoIds: ["camisa", "listra"],
            criadaEm: Date(timeIntervalSince1970: 1_000),
            atualizadaEm: Date().addingTimeInterval(60))

        await loja.aplicarRemotos([remoto], removidos: [:])
        let todas = await loja.todas()
        XCTAssertEqual(todas.count, 1)
        XCTAssertEqual(todas.first?.apelido, "outro iPhone")
        XCTAssertEqual(todas.first?.termoIds, ["camisa", "listra"])
    }

    func testExclusaoOfflinePersisteComoVersaoParaNaoRenascer() async throws {
        let arquivo = arquivoTemporario()
        let exclusoes = arquivo.deletingPathExtension().appendingPathExtension("exclusoes.json")
        defer {
            try? FileManager.default.removeItem(at: arquivo)
            try? FileManager.default.removeItem(at: exclusoes)
        }
        let id = UUID()
        let loja = PecasSalvas(arquivo: arquivo)
        await loja.salvar(PecaSalva(id: id, termoIds: ["vestido"]))
        await loja.apagar(id)

        let reaberta = PecasSalvas(arquivo: arquivo)
        let estado = await reaberta.estadoParaSincronizar()
        XCTAssertTrue(estado.itens.isEmpty)
        XCTAssertNotNil(estado.exclusoes[id],
                        "ausência de linha não basta: outro aparelho faria a peça renascer")
    }

    func testFavoritoPersisteSemGuardarLeituraCalculada() async throws {
        let arquivo = arquivoTemporario()
        defer { try? FileManager.default.removeItem(at: arquivo) }
        let loja = PecasSalvas(arquivo: arquivo)
        let peca = PecaSalva(apelido: "favorita", termoIds: ["vestido"],
                             favorita: true)
        await loja.salvar(peca)

        let reaberta = PecasSalvas(arquivo: arquivo)
        let todas = await reaberta.todas()
        let salva = try XCTUnwrap(todas.first)
        XCTAssertEqual(salva.favorita, true)
        let dados = try JSONEncoder().encode(salva)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: dados) as? [String: Any])
        XCTAssertEqual(json["favorita"] as? Bool, true)
        XCTAssertNil(json["estado"])
        XCTAssertNil(json["indice"])
    }

    func testRejeicaoDosSimilaresEPrefenciaDoUsuario() async throws {
        let arquivo = arquivoTemporario()
        defer { try? FileManager.default.removeItem(at: arquivo) }
        let loja = PecasSalvas(arquivo: arquivo)
        let peca = PecaSalva(termoIds: ["vestido"], similaresRejeitados: true)
        await loja.salvar(peca)

        let reaberta = PecasSalvas(arquivo: arquivo)
        let todas = await reaberta.todas()
        let salva = try XCTUnwrap(todas.first)
        XCTAssertEqual(salva.similaresRejeitados, true)
        let dados = try JSONEncoder().encode(salva)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: dados) as? [String: Any])
        XCTAssertNil(json["estado"])
        XCTAssertNil(json["indice"])
    }

    func testMaisRecentePrimeiro() async throws {
        let arquivo = arquivoTemporario()
        defer { try? FileManager.default.removeItem(at: arquivo) }
        let loja = PecasSalvas(arquivo: arquivo)

        let antiga = PecaSalva(apelido: "antiga", termoIds: ["saia"],
                               criadaEm: Date(timeIntervalSince1970: 1_000))
        let nova = PecaSalva(apelido: "nova", termoIds: ["calca"],
                             criadaEm: Date(timeIntervalSince1970: 2_000))
        await loja.salvar(antiga)
        await loja.salvar(nova)
        let ordenadas = await loja.todas()
        XCTAssertEqual(ordenadas.map(\.apelido), ["nova", "antiga"])
    }

    func testTetoRecusaEmVezDeDescartarSilenciosamente() async throws {
        let arquivo = arquivoTemporario()
        defer { try? FileManager.default.removeItem(at: arquivo) }
        let loja = PecasSalvas(arquivo: arquivo)

        for i in 0..<PecasSalvas.teto {
            await loja.salvar(PecaSalva(apelido: "p\(i)", termoIds: ["camisa"]))
        }
        let coube = await loja.salvar(PecaSalva(apelido: "excedente", termoIds: ["camisa"]))
        XCTAssertFalse(coube, "o teto tem que ser dito, e não engolir a peça")
        let noTeto = await loja.todas()
        XCTAssertEqual(noTeto.count, PecasSalvas.teto)
    }

    func testArquivoCorrompidoNaoDerrubaNemApaga() async throws {
        let arquivo = arquivoTemporario()
        defer { try? FileManager.default.removeItem(at: arquivo) }
        try Data("isto nao e json".utf8).write(to: arquivo)

        let loja = PecasSalvas(arquivo: arquivo)
        let vazia = await loja.todas()
        XCTAssertEqual(vazia.count, 0, "começa vazio em vez de estourar")

        // E volta a funcionar: a próxima gravação reescreve o arquivo.
        await loja.salvar(PecaSalva(apelido: "depois", termoIds: ["saia"]))
        let depois = await loja.todas()
        XCTAssertEqual(depois.count, 1)
    }

    func testMiniaturaLocalSobreviveReaberturaESomeComAPeca() async throws {
        let arquivo = arquivoTemporario()
        let pasta = pastaTemporaria()
        defer {
            try? FileManager.default.removeItem(at: arquivo)
            try? FileManager.default.removeItem(at: pasta)
        }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let peca = PecaSalva(apelido: "visual", termoIds: ["vestido"])
        let loja = PecasSalvas(arquivo: arquivo, pastaDeMiniaturas: pasta)
        let salvou = await loja.salvar(peca, miniaturaDados: jpeg)
        XCTAssertTrue(salvou)

        let todas = await loja.todas()
        let salva = try XCTUnwrap(todas.first)
        let miniaturaSalva = await loja.miniatura(de: salva)
        XCTAssertEqual(miniaturaSalva, jpeg)
        XCTAssertNotNil(salva.miniaturaArquivo)

        let reaberta = PecasSalvas(arquivo: arquivo, pastaDeMiniaturas: pasta)
        let todasReabertas = await reaberta.todas()
        let recarregada = try XCTUnwrap(todasReabertas.first)
        let miniaturaReaberta = await reaberta.miniatura(de: recarregada)
        XCTAssertEqual(miniaturaReaberta, jpeg)

        await reaberta.apagar(recarregada.id)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: pasta.appendingPathComponent(
                try XCTUnwrap(recarregada.miniaturaArquivo)).path))
    }

    func testAtualizarSemNovaImagemPreservaMiniatura() async throws {
        let arquivo = arquivoTemporario()
        let pasta = pastaTemporaria()
        defer {
            try? FileManager.default.removeItem(at: arquivo)
            try? FileManager.default.removeItem(at: pasta)
        }
        let jpeg = Data([1, 2, 3])
        let loja = PecasSalvas(arquivo: arquivo, pastaDeMiniaturas: pasta)
        var peca = PecaSalva(apelido: "antes", termoIds: ["camisa"])
        await loja.salvar(peca, miniaturaDados: jpeg)
        peca.apelido = "depois"
        await loja.salvar(peca)
        let todas = await loja.todas()
        let salva = try XCTUnwrap(todas.first)
        let miniatura = await loja.miniatura(de: salva)
        XCTAssertEqual(miniatura, jpeg)
    }

    func testPNGTransparenteMantemExtensaoEImagemSubstituiAJPEG() async throws {
        let arquivo = arquivoTemporario()
        let pasta = pastaTemporaria()
        defer {
            try? FileManager.default.removeItem(at: arquivo)
            try? FileManager.default.removeItem(at: pasta)
        }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x01])
        let loja = PecasSalvas(arquivo: arquivo, pastaDeMiniaturas: pasta)
        let peca = PecaSalva(apelido: "recortada", termoIds: ["vestido"])

        await loja.salvar(peca, miniaturaDados: jpeg)
        let depoisDoJPEG = await loja.todas()
        let nomeJPEG = try XCTUnwrap(depoisDoJPEG.first?.miniaturaArquivo)
        XCTAssertTrue(nomeJPEG.hasSuffix(".jpg"))

        await loja.salvar(peca, miniaturaDados: png)
        let depoisDoPNG = await loja.todas()
        let atual = try XCTUnwrap(depoisDoPNG.first)
        XCTAssertTrue(try XCTUnwrap(atual.miniaturaArquivo).hasSuffix(".png"))
        let dadosAtuais = await loja.miniatura(de: atual)
        XCTAssertEqual(dadosAtuais, png)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: pasta.appendingPathComponent(nomeJPEG).path),
            "substituir a foto não pode deixar a JPEG anterior órfã")
    }

    func testEdicaoRemotaPreservaMiniaturaExclusivaDesteAparelho() async throws {
        let arquivo = arquivoTemporario()
        let pasta = pastaTemporaria()
        defer {
            try? FileManager.default.removeItem(at: arquivo)
            try? FileManager.default.removeItem(at: pasta)
        }
        let loja = PecasSalvas(arquivo: arquivo, pastaDeMiniaturas: pasta)
        let original = PecaSalva(apelido: "local", termoIds: ["camisa"])
        await loja.salvar(original, miniaturaDados: Data([1, 2, 3]))
        let antes = await loja.todas()
        let salva = try XCTUnwrap(antes.first)
        let nome = try XCTUnwrap(salva.miniaturaArquivo)
        let remota = PecaSalva(
            id: salva.id, apelido: "remota", termoIds: ["camisa", "verde"],
            criadaEm: salva.criadaEm, atualizadaEm: Date().addingTimeInterval(5))

        await loja.aplicarRemotos([remota], removidos: [:])

        let depois = await loja.todas()
        let mesclada = try XCTUnwrap(depois.first)
        XCTAssertEqual(mesclada.apelido, "remota")
        XCTAssertEqual(mesclada.miniaturaArquivo, nome)
        let miniatura = await loja.miniatura(de: mesclada)
        XCTAssertEqual(miniatura, Data([1, 2, 3]))
    }

    func testExclusaoRemotaApagaMiniaturaLocal() async throws {
        let arquivo = arquivoTemporario()
        let pasta = pastaTemporaria()
        defer {
            try? FileManager.default.removeItem(at: arquivo)
            try? FileManager.default.removeItem(at: pasta)
        }
        let loja = PecasSalvas(arquivo: arquivo, pastaDeMiniaturas: pasta)
        let original = PecaSalva(apelido: "apagar", termoIds: ["saia"])
        await loja.salvar(original, miniaturaDados: Data([4, 5, 6]))
        let antes = await loja.todas()
        let salva = try XCTUnwrap(antes.first)
        let caminho = pasta.appendingPathComponent(try XCTUnwrap(salva.miniaturaArquivo))

        await loja.aplicarRemotos(
            [], removidos: [salva.id: Date().addingTimeInterval(5)])

        let depois = await loja.todas()
        XCTAssertTrue(depois.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: caminho.path))
    }
}
