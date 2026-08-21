import Foundation
import XCTest
@testable import CanarioLogica

final class SerieDoClusterTests: XCTestCase {
    private func resposta(_ pontos: Int, pedidos: Int = 3,
                          comPeso: Int = 3,
                          pernas: Int? = 2) -> SerieDoCluster.Resposta {
        let itens = (0..<pontos).map { i in
            SerieDoCluster.Ponto(
                semana: String(format: "2026-06-%02d", i + 1),
                indice: Double(i), nAtributos: pedidos,
                nPernasMin: pernas, nAtributosComEstado: pedidos)
        }
        return SerieDoCluster.Resposta(
            unidade: "z combinado", categoriaUsada: "vestido",
            atributosPedidos: pedidos, atributosComPeso: comPeso,
            pontos: itens)
    }

    func testContratoDoRPCEDataISO() throws {
        let json = #"{"unidade":"z combinado","categoria_usada":"vestido","atributos_pedidos":3,"atributos_com_peso":2,"pontos":[{"semana":"2026-08-17","indice":1.25,"n_atributos":2,"n_pernas_min":2,"n_atributos_com_estado":2}]}"#
        let r = try JSONDecoder().decode(
            SerieDoCluster.Resposta.self, from: Data(json.utf8))

        XCTAssertEqual(r.categoriaUsada, "vestido")
        XCTAssertEqual(r.pontos.first?.nAtributos, 2)
        XCTAssertNotNil(r.pontos.first?.data)
    }

    func testGraficoExigeOitoSemanas() {
        XCTAssertTrue(SerieDoCluster.porQueNaoDesenha(resposta(7))?
            .contains("at least 8") == true)
        XCTAssertNil(SerieDoCluster.porQueNaoDesenha(resposta(8)))
    }

    func testCoberturaParcialEUmaFonteFicamExplicitas() {
        let r = resposta(8, pedidos: 3, pernas: 1)
        XCTAssertTrue(SerieDoCluster.ralo(r.pontos[0], de: 3))
        let texto = SerieDoCluster.ressalva(r) ?? ""
        XCTAssertTrue(texto.contains("Every point"))
        XCTAssertTrue(texto.contains("not a directional state"))
    }

    func testSemPesoNaoDesenhaMesmoComHistorico() {
        XCTAssertTrue(SerieDoCluster.porQueNaoDesenha(resposta(12, comPeso: 0))?
            .contains("do not have panel weights") == true)
    }
}
