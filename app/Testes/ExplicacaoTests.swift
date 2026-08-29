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

    /// Uma fonte só não vira "1 sources". A contagem saiu do cartão de
    /// estável em 28/08 e hoje só aparece onde ela é a medição do estado --
    /// nas duas semanas seguidas de alta e de queda --, então é lá que a
    /// concordância de número passa a ser conferida.
    func testContagemDeFontesConcordaComOSingular() {
        let uma = IndiceSemanal(
            id: 1, termoId: "calca", segmento: Recorte.segmento,
            semana: "2026-08-10", indice: 1.4, estado: "em alta",
            pernasAtivas: ["busca"], nPernas: 1,
            meta: .init(indiceSemanaAnterior: 1.2, pernasAcimaDe1: 1,
                        pernasAbaixoDe1: 0),
            computadoEm: nil)
        let frase = Explicacao.porQue(estado: "em alta", indice: uma, series: [])
        XCTAssertTrue(frase.contains("1 source agreeing"), frase)
        XCTAssertFalse(frase.contains("1 sources"))
    }

    /// O cartão conta o que foi MEDIDO; o método mora no Q&A.
    ///
    /// A regra da §22 vinha impressa em toda linha da lista, sempre igual, e
    /// era isso que o JP tinha em mãos ao pedir para tirá-la: *"é aquele tipo
    /// de coisa que é bom que o user saiba mas não vai ser uma vida se ele não
    /// souber"*. Este teste guarda a decisão nos dois sentidos: a leitura
    /// desta semana continua no cartão, e a receita de como se confirma um
    /// movimento não volta para ele por descuido.
    func testCartaoNaoRepeteAReceitaDeComoSeConfirmaUmMovimento() {
        for z in [-1.4, -0.6, 1.1] {
            let frase = Explicacao.porQue(estado: "estavel",
                                          indice: indice(z, estado: "estavel"),
                                          series: [])
            XCTAssertFalse(frase.lowercased().contains("two consecutive weeks"),
                           "a regra geral saiu do cartão e mora no Q&A: \(frase)")
            XCTAssertFalse(frase.lowercased().contains("takes"), frase)
            XCTAssertTrue(frase.contains("on the statistical scale"),
                          "o que fica é a leitura desta semana: \(frase)")
        }
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
