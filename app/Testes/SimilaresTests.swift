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
            dimensoesPedidas: nil, minimoEmComum: minimo, minimoDimensoes: nil,
            nComTodos: comTodos, comPreco: comPreco,
            pctPrecoCheio: cheio, pctGradeQuebrada: quebrada, pctEsgotada: esgotada,
            precoMin: 29.99, precoMax: 12998, precoMediana: mediana,
            percentilDoAlvo: percentil, exibidos: 8)
    }

    private func peca(_ marca: String, preco: Double?, queda: Double?,
                      disponiveis: Int, degraus: Int,
                      faltando: [String] = [],
                      imagem: String? = nil) -> Similares.Peca {
        // `imagem` nasce nil de propósito: peça sem foto tem que continuar
        // funcionando em todo lugar. É o caso da loja que tirou a imagem do ar,
        // e o parágrafo da §29 não pode depender dela.
        Similares.Peca(
            id: 1, marca: marca, papelDaMarca: "nucleo", titulo: "Vestido Midi Floral",
            url: "https://exemplo/1", imagem: imagem,
            preco: preco, precoDe: nil, quedaPct: queda,
            emComum: 3, termosEmComum: nil,
            grade: .init(degraus: degraus, disponiveis: disponiveis,
                         faltando: faltando,
                         quebrada: disponiveis < degraus,
                         esgotada: degraus > 0 && disponiveis == 0))
    }

    // MARK: O parágrafo da §29

    func testParagrafoTrazOsNumerosDoPainel() {
        let t = Similares.paragrafo(resumo(), atributos: atributos)
        XCTAssertTrue(t.contains("9 brands"))
        XCTAssertTrue(t.contains("230 panel items"))
        XCTAssertTrue(t.contains("Dress + Floral + Midi"))
        XCTAssertTrue(t.contains("22% remain at full price"))
        XCTAssertTrue(t.contains("88% have missing sizes"))
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
        XCTAssertTrue(t.contains("4 panel items"))
        XCTAssertFalse(t.contains("%"), "porcentagem sobre 4 peças não se sustenta")
        XCTAssertTrue(t.contains("items are shown without a summary statistic"))
    }

    func testNenhumSimilarDizOsDoisMotivosPossiveis() {
        // Silêncio honesto: pode ser combinação rara ou lacuna do painel, e o
        // app não sabe distinguir — então diz as duas.
        let t = Similares.paragrafo(resumo(similares: 0, comTodos: 0, comPreco: 0,
                                           cheio: nil, quebrada: nil,
                                           esgotada: nil, mediana: nil),
                                    atributos: atributos)
        XCTAssertTrue(t.contains("uncommon combination"))
        XCTAssertTrue(t.contains("cannot distinguish"))
    }

    // MARK: O critério, que precisa ser auditável (regra 3)

    func testCriterioDizQuandoExigiuTodos() {
        let t = Similares.criterio(resumo(pedidos: 3, minimo: 3))
        XCTAssertTrue(t.contains("All 3 attributes"))
    }

    /// A regra 3 exige que o critério seja auditável: os DOIS números têm de
    /// aparecer -- quantas peças batem em tudo, e qual foi o mínimo aceito.
    /// A revisão de UX de 19/08 pediu menos texto e menos tom negativo, e o
    /// teste passa a travar a informação em vez da redação, para a próxima
    /// reescrita de copy não poder apagar a auditabilidade sem quebrar aqui.
    func testCriterioDizQuandoTolerouDiferenca() {
        // 6 atributos marcados exigem 5 (70% arredondado para cima).
        let t = Similares.criterio(resumo(similares: 34, pedidos: 6, minimo: 5, comTodos: 4))
        XCTAssertTrue(t.contains("4 piece"), "quantas batem em todos")
        XCTAssertTrue(t.contains("all 6 attributes"), "em quantos atributos")
        XCTAssertTrue(t.contains("at least 5"), "qual foi o mínimo aceito")
    }

    /// Quando nada bate em tudo, a frase antiga imprimia literalmente
    /// "0 match all of them" -- anunciar a ausência, que é a forma mais
    /// desanimadora de dizer a mesma coisa, e foi o que a mentora apontou.
    /// O critério continua auditável: diz o melhor que existe.
    func testCriterioNaoAnunciaAusenciaQuandoNadaBateEmTudo() {
        let t = Similares.criterio(resumo(similares: 12, pedidos: 4, minimo: 3, comTodos: 0))
        XCTAssertFalse(t.contains("0 "), "não anuncia zero: \(t)")
        XCTAssertTrue(t.contains("3 of your 4"), "diz o melhor disponível")
        XCTAssertTrue(t.contains("differs"), "aponta onde a diferença está explicada")
    }

    // MARK: A fronteira da regra 1, no percentil de preço

    func testPercentilDescrevePosicaoSemJulgarOPreco() {
        let t = Similares.leituraDoPreco(resumo(percentil: 78), alvo: 450) ?? ""
        XCTAssertTrue(t.contains("78th percentile"))
        XCTAssertTrue(t.contains("above most"))
        XCTAssertTrue(t.contains("not a judgment of your price"),
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
        XCTAssertTrue(t.contains("no size available"))
        XCTAssertTrue(t.contains("marked down 50%"))
    }

    func testDesfechoDaGradeCheiaAPrecoCheio() {
        // §23: preço cheio + grade cheia é o continuativo saudável OU a peça
        // parada. A tela mostra o fato; a desambiguação é do flag, que não
        // existe ainda (A1).
        let t = Similares.desfecho(peca("Cantao", preco: 1199, queda: nil,
                                        disponiveis: 5, degraus: 5))
        XCTAssertTrue(t.contains("full size range, 5 sizes"))
        XCTAssertTrue(t.contains("at full price"))
    }

    func testDesfechoNomeiaOsTamanhosQueFaltam() {
        let t = Similares.desfecho(peca("Farm", preco: 297, queda: 38,
                                        disponiveis: 2, degraus: 5,
                                        faltando: ["PP", "P", "M"]))
        XCTAssertTrue(t.contains("2 of 5 sizes"))
        XCTAssertTrue(t.contains("missing PP, P, M"))
    }

    func testDesfechoSemDadoNaoInventa() {
        let t = Similares.desfecho(peca("X", preco: nil, queda: nil,
                                        disponiveis: 0, degraus: 0))
        XCTAssertEqual(t, "no price or size data")
    }

    func testVitrineNaoOfereceProdutoExplicitamenteEsgotado() {
        XCTAssertFalse(Similares.podeExibir(
            peca("Hering", preco: 129, queda: 40, disponiveis: 0, degraus: 5)))
        XCTAssertTrue(Similares.podeExibir(
            peca("Dress To", preco: 429, queda: nil, disponiveis: 3, degraus: 5)))
        XCTAssertTrue(Similares.podeExibir(
            peca("Sem grade", preco: 429, queda: nil, disponiveis: 0, degraus: 0)),
            "ausência de medição não pode ser convertida em esgotado")
    }

    // MARK: Dinheiro em português

    func testDinheiroUsaVirgulaEArredondaAcimaDeCem() {
        XCTAssertTrue(Formato.dinheiro(129.99).contains("130"))
        XCTAssertTrue(Formato.dinheiro(79.9).contains(","), "abaixo de 100 mostra centavos")
        XCTAssertTrue(Formato.dinheiro(1199).contains("1.199"))
    }
}
