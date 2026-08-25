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
                           suficiente: Bool = true,
                           coberturaDimensao: Double? = 60) -> Cobertura {
        Cobertura(termoId: termo, segmento: segmento, semana: semana,
                  pecasNaCelula: 100, marcasExternas: 12,
                  minimoPecas: 30, minimoMarcas: 8,
                  pecasNaDimensao: 60,
                  coberturaDimensaoPct: coberturaDimensao,
                  minimoCoberturaDimensaoPct: 30,
                  suficiente: suficiente)
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

    func testExplicaDimensaoPoucoObservavel() {
        let c = cobertura(suficiente: false, coberturaDimensao: 6.3)
        XCTAssertTrue(c.oQueFalta.contains("6.3%"))
        XCTAssertTrue(c.oQueFalta.contains("minimum 30%"))
    }

    func testAusenciaDeMedicaoDaDimensaoFalhaFechado() {
        let c = cobertura(suficiente: false, coberturaDimensao: nil)
        XCTAssertTrue(c.oQueFalta.contains("has not been measured"))
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
        let indices = [indice(semana: "2026-07-27"),
                       indice(termo: "preto", semana: "2026-07-20"),
                       indice(termo: "branco", semana: "2026-07-20")]
        let varejo = [varejo(termo: "preto", semana: "2026-07-20"),
                      varejo(termo: "branco", semana: "2026-07-20"),
                      varejo(semana: "2026-07-13")]
        let coberturas = [cobertura(semana: "2026-07-27"),
                          cobertura(termo: "preto", semana: "2026-07-20"),
                          cobertura(termo: "branco", semana: "2026-07-20")]
        XCTAssertEqual(Elegibilidade.semanaComum(
            indices: indices, varejo: varejo, coberturas: coberturas), "2026-07-20")
    }

    func testCompararIgnoraSemanaParcialComUmTermo() {
        let indices = [indice(termo: "vestido", semana: "2026-08-17"),
                       indice(termo: "preto", semana: "2026-08-10"),
                       indice(termo: "branco", semana: "2026-08-10")]
        let varejo = [varejo(termo: "vestido", semana: "2026-08-17"),
                      varejo(termo: "preto", semana: "2026-08-10"),
                      varejo(termo: "branco", semana: "2026-08-10")]
        let coberturas = [cobertura(termo: "vestido", semana: "2026-08-17"),
                          cobertura(termo: "preto", semana: "2026-08-10"),
                          cobertura(termo: "branco", semana: "2026-08-10")]
        XCTAssertEqual(Elegibilidade.semanaComum(
            indices: indices, varejo: varejo, coberturas: coberturas), "2026-08-10")
    }

    func testCatalogoDoCompararNaoSomeQuandoIndiceFalta() {
        XCTAssertTrue(Elegibilidade.varejoComparavel(varejo()))
        XCTAssertTrue(Elegibilidade.varejoComparavel(varejo(termo: "floral")))
        XCTAssertEqual(Elegibilidade.semanaComVarejo([
            varejo(termo: "isolado", semana: "2026-08-24"),
            varejo(termo: "preto", semana: "2026-08-17"),
            varejo(termo: "floral", semana: "2026-08-17")
        ]), "2026-08-17")
    }

    func testCompararPrefereSemanaRicaSemEsconderVarejo() {
        var indices = [indice(termo: "unico", semana: "2026-08-24")]
        var varejos = [varejo(termo: "unico", semana: "2026-08-24"),
                       varejo(termo: "outro", semana: "2026-08-24")]
        var coberturas = [cobertura(termo: "unico", semana: "2026-08-24")]
        for n in 0..<8 {
            let id = "termo_\(n)"
            indices.append(indice(termo: id, semana: "2026-08-10"))
            varejos.append(varejo(termo: id, semana: "2026-08-10"))
            coberturas.append(cobertura(termo: id, semana: "2026-08-10"))
        }
        XCTAssertEqual(Elegibilidade.semanaDeComparacao(
            indices: indices, varejo: varejos, coberturas: coberturas), "2026-08-10")
    }
}
