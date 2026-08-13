import XCTest
@testable import CanarioLogica

/// A correção de "Sem estado" não pode virar um atalho para inventar
/// estabilidade. Ela escolhe somente um estado que já foi sustentado por duas
/// fontes e conserva a data daquela leitura.
final class SelecaoDeEstadoTests: XCTestCase {
    private func leitura(id: Int, termo: String = "preto", semana: String,
                         estado: String?) -> IndiceSemanal {
        IndiceSemanal(id: id, termoId: termo, segmento: Recorte.segmento,
                      semana: semana, indice: 0.8, estado: estado,
                      pernasAtivas: estado == nil ? ["busca"] : ["busca", "editorial_br"],
                      nPernas: estado == nil ? 1 : 2, meta: nil, computadoEm: nil)
    }

    func testEscolheUltimoEstadoMedidoSemTransformarNuloEmEstavel() {
        let escolhido = SelecaoDeEstado.preferida(em: [
            leitura(id: 3, semana: "2026-08-10", estado: nil),
            leitura(id: 2, semana: "2026-08-03", estado: nil),
            leitura(id: 1, semana: "2026-07-27", estado: "em alta"),
        ])
        XCTAssertEqual(escolhido?.estado, "em alta")
        XCTAssertEqual(escolhido?.semana, "2026-07-27")
    }

    func testSemEstadoRealPreservaNuloMaisRecente() {
        let escolhido = SelecaoDeEstado.preferida(em: [
            leitura(id: 2, semana: "2026-08-10", estado: nil),
            leitura(id: 1, semana: "2026-08-03", estado: nil),
        ])
        XCTAssertNil(escolhido?.estado)
        XCTAssertEqual(escolhido?.semana, "2026-08-10")
    }

    func testNaoUsaEstadoVelhoForaDaJanelaDeclarada() {
        var leituras = (0..<SelecaoDeEstado.janelaMaxima).map {
            leitura(id: 100 - $0, semana: String(format: "2026-%02d-01", 12 - $0),
                    estado: nil)
        }
        leituras.append(leitura(id: 1, semana: "2025-01-01", estado: "em queda"))
        XCTAssertNil(SelecaoDeEstado.preferida(em: leituras)?.estado)
    }

    func testAgrupaSemMisturarTermos() {
        let mapa = SelecaoDeEstado.porTermo([
            leitura(id: 4, termo: "preto", semana: "2026-08-10", estado: nil),
            leitura(id: 3, termo: "preto", semana: "2026-08-03", estado: "em alta"),
            leitura(id: 2, termo: "saia", semana: "2026-08-10", estado: nil),
            leitura(id: 1, termo: "saia", semana: "2026-08-03", estado: "em queda"),
        ])
        XCTAssertEqual(mapa["preto"]?.estado, "em alta")
        XCTAssertEqual(mapa["saia"]?.estado, "em queda")
    }

    func testRadarEditorialNaoPromoveNoticiaIncidentalComoModa() {
        XCTAssertFalse(Explicacao.mancheteDeclaraModa(
            "Vini Jr.: De São Gonçalo ao topo do mundo"))
        XCTAssertFalse(Explicacao.mancheteDeclaraModa(
            "Anne Hathaway exibe avanço da terceira gestação durante evento"))
        XCTAssertTrue(Explicacao.mancheteDeclaraModa(
            "O casaco de tweed é alternativa ao blazer: 5 jeitos de usar"))
        XCTAssertTrue(Explicacao.mancheteDeclaraModa(
            "Copenhagen Fashion Week outfits to recreate now"))
        XCTAssertTrue(Explicacao.mancheteDeclaraModa(
            "Os vestidos escolhidos para o verão"))
        XCTAssertFalse(Explicacao.mancheteDeclaraModa(
            "Camisa 7 do Real Madrid decide o clássico"))
    }
}
