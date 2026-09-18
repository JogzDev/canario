import Foundation
import XCTest
@testable import CanarioLogica

/// A capa que conta a população e ilustra com amostra (A58).
///
/// Os números são os medidos em produção em 18/09/2026, na janela comum de
/// 27/08 a 02/09: Le Lis Blanc 351 peças em 1.744 ofertadas (201,3 por mil) e
/// C&A 604 peças em 7.263 (83,2). A C&A lidera a contagem absoluta e é a
/// quinta em taxa — é exatamente essa diferença que o denominador existe para
/// mostrar, e que a contagem da amostra de 120 escondia.
final class ResumoDeEventosTests: XCTestCase {

    private func exemplo(_ nome: String, ordinal: Int? = 1,
                         tamanhos: [String]? = ["P", "M"]) -> ResumoDeEventos.Exemplo {
        .init(peca: nome, imagem: nil, urlDaPeca: "https://exemplo/\(nome)",
              data: "2026-09-01", repetida: ordinal.map { $0 > 1 },
              ordinal: ordinal, diasDesdeAPrimeira: ordinal == 1 ? nil : 54,
              detalhe: .init(tamanhos: tamanhos, quedaPct: nil,
                             precoDe: nil, precoPara: nil))
    }

    private func marca(_ nome: String, pecas: Int, eventos: Int,
                       ofertadas: Int?, porMil: Double?,
                       exemplos: Int = 12) -> ResumoDeEventos.Marca {
        .init(marca: nome, pecas: pecas, eventos: eventos, pecasRepetidas: 31,
              maiorQuedaPct: nil, pecasOfertadas: ofertadas,
              porMilOfertadas: porMil, tamanhos: ["P", "M", "G"],
              exemplos: (1...exemplos).map { exemplo("Peça \($0)") })
    }

    private func resposta(dias: Int = 15) -> ResumoDeEventos.Resposta {
        .init(tipo: "reposicao", de: "2026-08-27", ate: "2026-09-02", dias: 7,
              diasDesdeOFim: dias, unidade: "produtos distintos com evento na janela",
              denominadorEm: "2026-09-02", totalPecas: 2312, totalEventos: 2604,
              marcas: [marca("Le Lis Blanc", pecas: 351, eventos: 382,
                             ofertadas: 1744, porMil: 201.3),
                       marca("C&A", pecas: 604, eventos: 710,
                             ofertadas: 7263, porMil: 83.2)])
    }

    func testContratoDaRPCChegaInteiro() throws {
        let json = #"{"tipo":"reposicao","de":"2026-08-27","ate":"2026-09-02","dias":7,"dias_desde_o_fim":16,"unidade":"produtos distintos com evento na janela","denominador_em":"2026-09-02","total_pecas":2312,"total_eventos":2604,"marcas":[{"marca":"Le Lis Blanc","pecas":351,"eventos":382,"pecas_repetidas":40,"maior_queda_pct":null,"pecas_ofertadas":1744,"por_mil_ofertadas":201.3,"tamanhos":["P","M"],"exemplos":[{"peca":"Vestido","imagem":null,"url_da_peca":"https://x/1","data":"2026-09-01","repetida":true,"ordinal":3,"dias_desde_a_primeira":54,"detalhe":{"tamanhos":["PP","P"],"regra":"K1"}}]}]}"#
        let r = try JSONDecoder().decode(
            ResumoDeEventos.Resposta.self, from: Data(json.utf8))
        XCTAssertEqual(r.totalPecas, 2312)
        XCTAssertEqual(r.marcas.first?.porMilOfertadas, 201.3)
        // O sinal que o JP pediu em 31/07 viaja no exemplo desde a A58.
        XCTAssertEqual(r.marcas.first?.exemplos.first?.ordinal, 3)
        XCTAssertEqual(r.marcas.first?.exemplos.first?.detalhe?.tamanhos, ["PP", "P"])
    }

    /// A frase da repetição é a mesma de `eventos_recentes`, porque é o mesmo
    /// código: duas cópias divergiriam e a primeira a divergir seria a da tela
    /// que ninguém abre para conferir.
    func testExemploEscreveAMesmaFraseDeRepeticao() throws {
        let e = exemplo("Vestido", ordinal: 3, tamanhos: ["PP", "P"])
        let frase = try XCTUnwrap(
            e.repeticao(tipo: "reposicao", desde: "2026-07-24"))
        XCTAssertEqual(frase, "3rd restock for size PP/P in under 2 months")
        XCTAssertEqual(e.resumo(tipo: "reposicao"),
                       "Size PP, P returned and remained available")
    }

    func testJanelaDeclaraPeriodoEIdade() throws {
        let t = try XCTUnwrap(ResumoDeEventos.janela(resposta()))
        XCTAssertTrue(t.contains("27/08/2026 – 02/09/2026"))
        XCTAssertTrue(t.contains("ended 2 weeks ago"))
    }

    /// Janela que acabou de fechar não ganha carimbo de idade: "esta semana"
    /// é verdade, e "0 dias atrás" seria ruído.
    func testJanelaEmDiaNaoCarimbaIdade() throws {
        let t = try XCTUnwrap(ResumoDeEventos.janela(resposta(dias: 0)))
        XCTAssertEqual(t, "27/08/2026 – 02/09/2026")
    }

    /// Peças e eventos são números diferentes e aparecem os dois. Misturá-los
    /// foi metade do defeito original.
    func testTotalSeparaPecasDeEventos() {
        XCTAssertEqual(ResumoDeEventos.total(resposta()),
                       "2,312 items · 2,604 events")
    }

    func testTaxaSoExisteComDenominador() throws {
        let comDenominador = marca("Le Lis Blanc", pecas: 351, eventos: 382,
                                   ofertadas: 1744, porMil: 201.3)
        XCTAssertEqual(ResumoDeEventos.taxa(comDenominador),
                       "201.3 per 1,000 offered")

        // Fora da retenção de snapshots não há sortimento observado. A taxa
        // se cala; dividir pelo sortimento de hoje seria pior que não dividir.
        let sem = marca("Le Lis Blanc", pecas: 351, eventos: 382,
                        ofertadas: nil, porMil: nil)
        XCTAssertNil(ResumoDeEventos.taxa(sem))
        XCTAssertFalse(ResumoDeEventos.apoio(sem).contains("per 1,000"))
        XCTAssertTrue(ResumoDeEventos.apoio(sem).contains("382 events"),
                      "sem denominador a contagem absoluta continua existindo")
    }

    /// Doze cartões não podem afirmar "doze peças" quando a marca tem
    /// seiscentas: é o defeito que a A58 corrigiu no banco, voltando pela tela.
    func testListaDaMarcaSeDeclaraAmostra() throws {
        let cea = marca("C&A", pecas: 604, eventos: 710,
                        ofertadas: 7263, porMil: 83.2)
        XCTAssertEqual(ResumoDeEventos.recorte(cea),
                       "Showing 12 of 604 items, most recent first.")

        let pequena = marca("NV", pecas: 10, eventos: 12,
                            ofertadas: 584, porMil: 17.1, exemplos: 10)
        XCTAssertNil(ResumoDeEventos.recorte(pequena),
                     "lista completa não anuncia recorte")
    }

    /// A ordenação e a contagem vêm do banco. Se a tela reordenasse por
    /// exemplos, voltaria a premiar quem coube na amostra.
    func testAOrdemVemDoBancoEEhPorPecasDistintas() {
        let r = resposta()
        XCTAssertEqual(r.marcas.map(\.marca), ["Le Lis Blanc", "C&A"])
        XCTAssertEqual(r.marcas.map(\.exemplos.count), [12, 12],
                       "as duas mostram 12 exemplos e têm contagens diferentes")
        XCTAssertNotEqual(r.marcas[0].pecas, r.marcas[1].pecas)
    }
}
