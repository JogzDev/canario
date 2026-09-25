import Foundation
import XCTest
@testable import CanarioLogica

final class LeiturasSalvasTests: XCTestCase {
    private func leitura(_ ids: [Int], mediana: Double, esgotadas: Int) throws -> LeituraEspecifica {
        let pecas = ids.map { id in
            ["id": id, "titulo": "Peça \(id)", "marca": "Marca", "preco": mediana] as [String: Any]
        }
        let bruto: [String: Any] = [
            "nome": "saia midi plissada",
            "painel_observado_em": "2026-09-24",
            "frases": [["texto": "Há peças no painel.", "fatos": ["total"]]],
            "fatos": [
                "total": ["pecas": ids.count, "marcas": 1, "provas": ids],
                "preco": ["minimo": mediana, "mediana": mediana, "maximo": mediana, "provas": ids],
                "remarcadas": ["pecas": 0, "provas": []],
                "grade": ["com_tamanho_esgotado": esgotadas, "provas": ids],
            ],
            "pecas": pecas, "parecidas": [], "perguntas": [],
        ]
        return try LeituraEspecifica.decodificar(JSONSerialization.data(withJSONObject: bruto))
    }

    func testComparacaoUsaDuasObservacoesEIdsConfirmados() throws {
        let antes = try leitura([1, 2], mediana: 629, esgotadas: 0)
        let depois = try leitura([2, 3, 4], mediana: 599, esgotadas: 1)
        let delta = ComparacaoDeLeituras(antes: antes, depois: depois)
        XCTAssertEqual(delta.antes.pecas, 2)
        XCTAssertEqual(delta.depois.pecas, 3)
        XCTAssertEqual(delta.antes.precoMediano, 629)
        XCTAssertEqual(delta.depois.precoMediano, 599)
        XCTAssertEqual(delta.painelAntes, "2026-09-24")
        XCTAssertEqual(delta.painelDepois, "2026-09-24")
        XCTAssertEqual(delta.entraramNoRecorte, 2)
        XCTAssertEqual(delta.sairamDoRecorte, 1)
        XCTAssertEqual(delta.depois.comTamanhoEsgotado, 1)
    }

    func testArquivoAntigoSemResumoNemRefinamentoContinuaAbrindo() throws {
        let registro = LeituraGuardada(pedido: "saia", descricao: nil,
                                       precoDaPessoa: 450, leitura: try leitura([17], mediana: 299, esgotadas: 0))
        var bruto = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(registro))
                                   as? [String: Any])
        bruto.removeValue(forKey: "resumo")
        bruto.removeValue(forKey: "refinamento")
        let antigo = try JSONDecoder().decode(LeituraGuardada.self,
                                             from: JSONSerialization.data(withJSONObject: bruto))
        XCTAssertEqual(antigo.resumo.pecas, 1)
        XCTAssertEqual(antigo.resumo.precoMediano, 299)
        XCTAssertNil(antigo.refinamento)
        XCTAssertEqual(antigo.leitura.provas(de: antigo.leitura.frases[0]).map(\.id), [17])
    }

    func testGuardaAteCinquentaEReabreNaOrdem() async throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        let arquivo = pasta.appendingPathComponent("leituras.json")
        let loja = LeiturasSalvas(arquivo: arquivo)
        let resposta = try leitura([17], mediana: 299, esgotadas: 0)
        for i in 0..<52 {
            await loja.guardar(LeituraGuardada(feitaEm: Date(timeIntervalSince1970: Double(i)),
                                               pedido: "pedido \(i)", descricao: nil,
                                               precoDaPessoa: nil, leitura: resposta))
        }
        let reaberta = LeiturasSalvas(arquivo: arquivo)
        let itens = await reaberta.todas()
        XCTAssertEqual(itens.count, 50)
        XCTAssertEqual(itens.first?.pedido, "pedido 51")
        XCTAssertEqual(itens.last?.pedido, "pedido 2")
    }
}
