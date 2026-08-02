import XCTest
@testable import CanarioLogica

final class ElegibilidadeTests: XCTestCase {
    private func indice(termo: String = "preto", semana: String = "2026-07-27",
                        segmento: String = Recorte.segmento) -> IndiceSemanal {
        IndiceSemanal(id: 1, termoId: termo, segmento: segmento, semana: semana,
                      indice: 1.2, estado: "em alta", pernasAtivas: ["busca", "editorial_br"],
                      nPernas: 2, meta: nil, computadoEm: nil)
    }

    private func cobertura(termo: String = "preto", semana: String = "2026-07-27",
                           segmento: String = Recorte.segmento,
                           suficiente: Bool = true) -> Cobertura {
        Cobertura(termoId: termo, segmento: segmento, semana: semana,
                  pecasNaCelula: 100, marcasExternas: 12,
                  minimoPecas: 30, minimoMarcas: 8, suficiente: suficiente)
    }

    private func varejo(termo: String = "preto", semana: String = "2026-07-27") -> PontoSerie {
        PontoSerie(id: 1, termoId: termo, fonte: "varejo", semana: semana,
                   valorBruto: 10, z: nil, nAmostra: 100, meta: nil)
    }

    func testCoberturaAusenteReprova() {
        XCTAssertFalse(Elegibilidade.indice(indice(), cobertura: nil))
    }

    func testCoberturaInsuficienteReprova() {
        XCTAssertFalse(Elegibilidade.indice(indice(), cobertura: cobertura(suficiente: false)))
    }

    func testSemanaSegmentoETermoPrecisamCoincidir() {
        XCTAssertFalse(Elegibilidade.indice(indice(), cobertura: cobertura(semana: "2026-07-20")))
        XCTAssertFalse(Elegibilidade.indice(indice(), cobertura: cobertura(segmento: "outro")))
        XCTAssertFalse(Elegibilidade.indice(indice(), cobertura: cobertura(termo: "branco")))
        XCTAssertTrue(Elegibilidade.indice(indice(), cobertura: cobertura()))
    }

    func testComparacaoRecusaSemanasDiferentes() {
        XCTAssertFalse(Elegibilidade.comparacao(
            indice: indice(), varejo: varejo(semana: "2026-07-20"),
            cobertura: cobertura()))
    }

    func testEscolheUltimaSemanaComumAsTresSuperficies() {
        let indices = [indice(semana: "2026-07-27"), indice(semana: "2026-07-20")]
        let varejo = [varejo(semana: "2026-07-20"), varejo(semana: "2026-07-13")]
        let coberturas = [cobertura(semana: "2026-07-27"), cobertura(semana: "2026-07-20")]
        XCTAssertEqual(Elegibilidade.semanaComum(
            indices: indices, varejo: varejo, coberturas: coberturas), "2026-07-20")
    }
}
