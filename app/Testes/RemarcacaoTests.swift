import XCTest
@testable import CanarioLogica

/// O Davi e a Bianca abriram peças na tela de Markdowns e compararam com o
/// site: "tem um vestido que disse que desceu 50% mas mostra 79% no site",
/// "outro que mostra 33.3% e no site tá 80%", "metade dos que eu cliquei não tá
/// batendo".
///
/// Os dois números estavam certos. `computar_eventos` (regra K4) mede o corte
/// desta semana contra o **preço anterior observado**; o selo da loja desconta
/// do **preço de tabela**. A peça 5572 da PatBo caiu de R$ 799,20 para R$ 400
/// -- 50% de corte -- sobre uma tabela de R$ 1.998, que dá os 79% do site.
///
/// Coincidem só quando a peça nunca tinha sido remarcada: foi o caso da calça
/// pantalona (R$ 4.950 → R$ 3.465, 30% nos dois lugares), e é por isso que
/// "alguns estavam corretos".
///
/// Estes testes travam a frase para ela nunca mais sair sem dizer contra o quê
/// mede.
final class RemarcacaoTests: XCTestCase {

    private func remarcacao(pct: Double?, de: Double?, para: Double?) -> EventoVarejo {
        EventoVarejo(
            id: 1, tipo: "remarcacao", data: "2026-08-19", semana: "2026-08-17",
            marca: "PatBo", peca: "VESTIDO MÍDI RECORTES CREPE EDIE OFF WHITE",
            urlDaPeca: nil, imagem: nil,
            detalhe: .init(tamanhos: nil, quedaPct: pct, precoDe: de, precoPara: para),
            ordinal: 1, diasDesdeAPrimeira: nil)
    }

    /// O caso real que gerou a queixa.
    func testDizContraQualPrecoAQuedaFoiMedida() {
        let texto = remarcacao(pct: 49.95, de: 799.20, para: 400).resumo
        XCTAssertTrue(texto.contains("previous price"),
                      "a frase não diz contra o que mede: \(texto)")
        XCTAssertTrue(texto.contains("400"), texto)
        XCTAssertTrue(texto.contains("799"), texto)
    }

    /// A frase antiga afirmava um desconto. Ela não media desconto.
    func testNaoAfirmaDescontoSobreOPrecoDeTabela() {
        for (pct, de, para) in [(49.95, 799.20, 400.0),
                                (33.3, 765.0, 510.0),
                                (30.0, 4950.0, 3465.0)] {
            let texto = remarcacao(pct: pct, de: de, para: para).resumo.lowercased()
            XCTAssertFalse(texto.contains("off"),
                           "\"off\" lê como desconto de tabela: \(texto)")
            XCTAssertFalse(texto.contains("price dropped"), texto)
        }
    }

    /// Sem os dois preços a frase encolhe, mas não volta a mentir.
    func testSemOsPrecosAindaNomeiaABase() {
        let texto = remarcacao(pct: 33.3, de: nil, para: nil).resumo
        XCTAssertTrue(texto.contains("previous price"), texto)
        XCTAssertTrue(texto.contains("33.3"), texto)
    }

    /// Sem número nenhum a linha continua existindo e continua honesta: houve
    /// corte, não sabemos de quanto.
    func testSemNumeroNaoInventaPorcentagem() {
        let texto = remarcacao(pct: nil, de: nil, para: nil).resumo
        XCTAssertFalse(texto.contains("%"), texto)
        XCTAssertFalse(texto.isEmpty)
    }

    /// A peça que bate com o site bate porque nunca tinha sido remarcada, não
    /// porque o app usa outra conta ali. Mesma frase, mesma base.
    func testPecaNuncaRemarcadaUsaAMesmaFrase() {
        let pantalona = remarcacao(pct: 30, de: 4950, para: 3465).resumo
        XCTAssertTrue(pantalona.contains("previous price"), pantalona)
        XCTAssertTrue(pantalona.contains("30%"), pantalona)
    }

    /// Reposição e saída de linha não podem ser afetadas por esta mudança.
    func testOutrosEventosSeguemIntactos() {
        var evento = remarcacao(pct: 50, de: 100, para: 50)
        evento = EventoVarejo(
            id: evento.id, tipo: "reposicao", data: evento.data,
            semana: evento.semana, marca: evento.marca, peca: evento.peca,
            urlDaPeca: nil, imagem: nil,
            detalhe: .init(tamanhos: ["P", "M"], quedaPct: nil,
                           precoDe: nil, precoPara: nil),
            ordinal: 1, diasDesdeAPrimeira: nil)
        XCTAssertTrue(evento.resumo.contains("P, M"), evento.resumo)
    }
}
