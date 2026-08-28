import XCTest
@testable import CanarioLogica

/// O cartão do "What changed?" e a contradição que ele carregava.
///
/// O selo e a frase liam campos **diferentes** do mesmo índice: o selo mostra a
/// faixa do z desta semana, e a frase lia `estado`, que é a classificação de
/// movimento confirmado da §22 — duas semanas seguidas, duas fontes
/// concordando. As duas podem divergir sem que nenhuma esteja errada. O que não
/// pode é o cartão apresentá-las como uma afirmação só, que era o que fazia
/// "Under the usual range" conviver com "Within this attribute's usual range"
/// a três linhas de distância.
final class ExplicacaoTests: XCTestCase {

    private func indice(_ z: Double?, estado: String?, pernas: Int = 2)
        -> IndiceSemanal {
        IndiceSemanal(id: 1, termoId: "calca", segmento: Recorte.segmento,
                      semana: "2026-08-10", indice: z, estado: estado,
                      pernasAtivas: ["busca", "editorial_br"],
                      nPernas: pernas, meta: nil, computadoEm: nil)
    }

    /// O caso que o JP viu no aparelho: estável, mas com o z fora da faixa.
    func testEstavelComZForaDaFaixaExplicaAPosicaoDaSemana() {
        let frase = Explicacao.porQue(estado: "estavel",
                                      indice: indice(-1.2, estado: "estavel"),
                                      series: [])
        XCTAssertTrue(frase.contains("-1.2"),
                      "o número desta semana precisa aparecer: \(frase)")
        XCTAssertTrue(frase.contains("one week is not a movement"),
                      "e precisa dizer por que ainda não é movimento: \(frase)")
        XCTAssertFalse(frase.contains("Within this attribute's usual range"),
                       "não pode afirmar que está dentro da faixa quando não está")
    }

    /// Estável de verdade — o z dentro da faixa — mantém a frase de sempre.
    /// "Estável é resultado medido, não dado faltando" é da regra 2 e não some.
    func testEstavelDeVerdadeMantemAFraseQueDizQueEhMedicao() {
        let frase = Explicacao.porQue(estado: "estavel",
                                      indice: indice(0.1, estado: "estavel"),
                                      series: [])
        XCTAssertTrue(frase.contains("Stable is a measured result, not missing data."),
                      frase)
    }

    /// Dois termos igualmente "estáveis" e com z diferente não podem receber a
    /// mesma frase. Era esse o sintoma: "não vejo valor em tudo ter o mesmo
    /// texto".
    func testDoisTermosEstaveisComZDiferenteNaoRecebemAMesmaFrase() {
        let calca = Explicacao.porQue(estado: "estavel",
                                      indice: indice(-1.2, estado: "estavel"),
                                      series: [])
        let jeans = Explicacao.porQue(estado: "estavel",
                                      indice: indice(-0.6, estado: "estavel"),
                                      series: [])
        XCTAssertNotEqual(calca, jeans)
    }

    /// Uma fonte só não vira "1 sources".
    func testContagemDeFontesConcordaComOSingular() {
        let frase = Explicacao.porQue(estado: "estavel",
                                      indice: indice(-1.4, estado: "estavel",
                                                     pernas: 1),
                                      series: [])
        XCTAssertTrue(frase.contains("1 source."), frase)
        XCTAssertFalse(frase.contains("1 sources"))
    }

    /// Sem estado, a frase continua sendo a de "duas fontes ainda não
    /// concordam" — ela não passa pelo caminho novo.
    func testSemEstadoContinuaDizendoQueAsFontesNaoConcordam() {
        let frase = Explicacao.porQue(estado: nil,
                                      indice: indice(-1.2, estado: nil),
                                      series: [])
        XCTAssertTrue(frase.contains("do not yet agree"), frase)
    }
}
