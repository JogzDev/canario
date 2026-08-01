import XCTest
@testable import CanarioLogica

/// Testes do bloco de similares (§29) e do parágrafo que se apoia neles.
///
/// Os números são os MEDIDOS no painel em 01/08/2026 para "vestido + floral +
/// midi": 230 peças em 9 marcas, 22,2% a preço cheio, 87,8% com grade quebrada,
/// mediana de R$ 129,99.
///
/// Este é o bloco que a §5 lista como **substituto aprovado** da previsão que o
/// projeto proíbe. Por isso os testes cuidam menos de formatação e mais da
/// fronteira: onde o texto para de descrever e começaria a prescrever.
final class SimilaresTests: XCTestCase {

    private func termo(_ id: String, _ rotulo: String, _ dimensao: String) -> Termo {
        Termo(id: id, rotulo: rotulo, dimensao: dimensao, exclusiva: true,
              sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    private var atributos: [Termo] {
        [termo("vestido", "Vestido", "categoria"),
         termo("floral", "Floral", "estampa"),
         termo("midi", "Midi", "comprimento")]
    }

    private func resumo(similares: Int = 230, marcas: Int = 9,
                        pedidos: Int = 3, minimo: Int = 3, comTodos: Int = 230,
                        comPreco: Int = 230,
                        cheio: Double? = 22.2, quebrada: Double? = 87.8,
                        esgotada: Double? = 31.0, mediana: Double? = 129.99,
                        percentil: Double? = nil) -> Similares.Resumo {
        Similares.Resumo(
            nSimilares: similares, nMarcas: marcas, atributosPedidos: pedidos,
            minimoEmComum: minimo, nComTodos: comTodos, comPreco: comPreco,
            pctPrecoCheio: cheio, pctGradeQuebrada: quebrada, pctEsgotada: esgotada,
            precoMin: 29.99, precoMax: 12998, precoMediana: mediana,
            percentilDoAlvo: percentil, exibidos: 8)
    }

    private func peca(_ marca: String, preco: Double?, queda: Double?,
                      disponiveis: Int, degraus: Int,
                      faltando: [String] = []) -> Similares.Peca {
        Similares.Peca(
            id: 1, marca: marca, papelDaMarca: "nucleo", titulo: "Vestido Midi Floral",
            url: "https://exemplo/1", preco: preco, precoDe: nil, quedaPct: queda,
            emComum: 3,
            grade: .init(degraus: degraus, disponiveis: disponiveis,
                         faltando: faltando,
                         quebrada: disponiveis < degraus,
                         esgotada: degraus > 0 && disponiveis == 0))
    }

    // MARK: O parágrafo da §29

    func testParagrafoTrazOsNumerosDoPainel() {
        let t = Similares.paragrafo(resumo(), atributos: atributos)
        XCTAssertTrue(t.contains("9 marcas"))
        XCTAssertTrue(t.contains("230 peças"))
        XCTAssertTrue(t.contains("Vestido + Floral + Midi"))
        XCTAssertTrue(t.contains("22% seguem a preço cheio"))
        XCTAssertTrue(t.contains("88% estão com a grade quebrada"))
        XCTAssertTrue(t.contains("R$ 130"), "o preço do meio entra na frase")
    }

    func testParagrafoNaoPrometeNada() {
        let t = Similares.paragrafo(resumo(), atributos: atributos).lowercased()
        // A §6 lista o vocabulário proibido; a §5 proíbe o veredito.
        for proibido in ["vai vender", "sucesso", "chance", "probabilidade",
                         "previsão", "prevê", "potencial", "recomendo", "aposte"] {
            XCTAssertFalse(t.contains(proibido), "o parágrafo não pode conter \"\(proibido)\"")
        }
    }

    func testConjuntoPequenoNaoGanhaPorcentagem() {
        // Com 4 similares, "25% a preço cheio" é uma peça. A §8 existe
        // exatamente para impedir esse tipo de número.
        let t = Similares.paragrafo(resumo(similares: 4, comTodos: 4, comPreco: 4),
                                    atributos: atributos)
        XCTAssertTrue(t.contains("4 peças"))
        XCTAssertFalse(t.contains("%"), "porcentagem sobre 4 peças não se sustenta")
        XCTAssertTrue(t.contains("prefiro mostrar as peças"))
    }

    func testNenhumSimilarDizOsDoisMotivosPossiveis() {
        // Silêncio honesto: pode ser combinação rara ou lacuna do painel, e o
        // app não sabe distinguir — então diz as duas.
        let t = Similares.paragrafo(resumo(similares: 0, comTodos: 0, comPreco: 0,
                                           cheio: nil, quebrada: nil,
                                           esgotada: nil, mediana: nil),
                                    atributos: atributos)
        XCTAssertTrue(t.contains("combinação rara"))
        XCTAssertTrue(t.contains("não sei distinguir"))
    }

    // MARK: O critério, que precisa ser auditável (regra 3)

    func testCriterioDizQuandoExigiuTodos() {
        let t = Similares.criterio(resumo(pedidos: 3, minimo: 3))
        XCTAssertTrue(t.contains("os 3 atributos"))
    }

    func testCriterioDizQuandoTolerouDiferenca() {
        // 6 atributos marcados exigem 5 (70% arredondado para cima).
        let t = Similares.criterio(resumo(similares: 34, pedidos: 6, minimo: 5, comTodos: 4))
        XCTAssertTrue(t.contains("pelo menos 5 dos 6"))
        XCTAssertTrue(t.contains("4 tem"), "quantos batem em todos é o número mais forte")
    }

    // MARK: A fronteira da regra 1, no percentil de preço

    func testPercentilDescrevePosicaoSemJulgarOPreco() {
        let t = Similares.leituraDoPreco(resumo(percentil: 78), alvo: 450) ?? ""
        XCTAssertTrue(t.contains("percentil 78"))
        XCTAssertTrue(t.contains("acima da maior parte"))
        XCTAssertTrue(t.contains("não julgamento do seu preço"),
                      "sem esta ressalva o percentil vira conselho de precificação")
        for proibido in ["caro", "barato", "deveria", "ideal", "recomendo"] {
            XCTAssertFalse(t.lowercased().contains(proibido))
        }
    }

    func testPercentilSoAparecePreenchidoEComBase() {
        XCTAssertNil(Similares.leituraDoPreco(resumo(percentil: 78), alvo: nil),
                     "sem preço informado não há o que posicionar")
        XCTAssertNil(Similares.leituraDoPreco(resumo(comPreco: 5, percentil: 78), alvo: 450),
                     "percentil sobre 5 peças não se sustenta")
    }

    // MARK: O desfecho de cada peça — é o "e o desfecho delas" da §5

    func testDesfechoDaPecaEsgotada() {
        let t = Similares.desfecho(peca("Dress To", preco: 429, queda: 50,
                                        disponiveis: 0, degraus: 5))
        XCTAssertTrue(t.contains("sem nenhum tamanho disponível"))
        XCTAssertTrue(t.contains("remarcada 50%"))
    }

    func testDesfechoDaGradeCheiaAPrecoCheio() {
        // §23: preço cheio + grade cheia é o continuativo saudável OU a peça
        // parada. A tela mostra o fato; a desambiguação é do flag, que não
        // existe ainda (A1).
        let t = Similares.desfecho(peca("Cantao", preco: 1199, queda: nil,
                                        disponiveis: 5, degraus: 5))
        XCTAssertTrue(t.contains("grade cheia, 5 tamanhos"))
        XCTAssertTrue(t.contains("a preço cheio"))
    }

    func testDesfechoNomeiaOsTamanhosQueFaltam() {
        let t = Similares.desfecho(peca("Farm", preco: 297, queda: 38,
                                        disponiveis: 2, degraus: 5,
                                        faltando: ["PP", "P", "M"]))
        XCTAssertTrue(t.contains("2 de 5 tamanhos"))
        XCTAssertTrue(t.contains("faltando PP, P, M"))
    }

    func testDesfechoSemDadoNaoInventa() {
        let t = Similares.desfecho(peca("X", preco: nil, queda: nil,
                                        disponiveis: 0, degraus: 0))
        XCTAssertEqual(t, "sem dado de preço nem de grade")
    }

    // MARK: Dinheiro em português

    func testDinheiroUsaVirgulaEArredondaAcimaDeCem() {
        XCTAssertTrue(Formato.dinheiro(129.99).contains("130"))
        XCTAssertTrue(Formato.dinheiro(79.9).contains(","), "abaixo de 100 mostra centavos")
        XCTAssertTrue(Formato.dinheiro(1199).contains("1.199"))
    }
}
