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
            dimensaoRelaxada: nil,
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

    // MARK: A idade do painel (A57)

    /// Com a coleta de ontem, a frase é a de sempre: nada de ressalva sobre um
    /// dado que está em dia.
    func testColetaDeOntemNaoCarimbaData() {
        var r = resumo()
        r.observadoEm = "2026-09-16"
        r.observadoMaisAntigoEm = "2026-09-16"
        r.diasDesdeAObservacao = 1
        let t = Similares.paragrafo(r, atributos: atributos)
        XCTAssertTrue(t.contains("I found 230 panel items"))
        XCTAssertFalse(t.contains("last seen"))
        XCTAssertNil(Similares.quandoFoiVisto(r))
    }

    /// O caso real de 17/09/2026: painel visto em 02/09, quinze dias atrás. A
    /// frase muda de tempo verbal e leva a data junto -- sem isso a correção
    /// da A57 só trocaria "não existe" por "isto é de hoje".
    func testPainelParadoDizQuandoFoiVisto() {
        var r = resumo()
        r.observadoEm = "2026-09-02"
        r.observadoMaisAntigoEm = "2026-09-02"
        r.diasDesdeAObservacao = 15
        let t = Similares.paragrafo(r, atributos: atributos)
        XCTAssertTrue(t.contains("230 panel items had"))
        XCTAssertTrue(t.contains("when the panel was last seen, on 02/09/2026"))
        XCTAssertTrue(t.contains("2 weeks ago"))
        XCTAssertFalse(t.contains("I found 230"),
                       "presente não pode sobreviver a um painel parado")
    }

    /// Quando as peças não foram todas vistas no mesmo dia, a frase declara o
    /// intervalo em vez de escolher uma ponta.
    func testIntervaloDeObservacaoApareceInteiro() {
        var r = resumo()
        r.observadoEm = "2026-09-02"
        r.observadoMaisAntigoEm = "2026-08-27"
        r.diasDesdeAObservacao = 15
        let t = Similares.paragrafo(r, atributos: atributos)
        XCTAssertTrue(t.contains("between 27/08/2026 and 02/09/2026"))
    }

    /// Banco anterior à A57 não manda as datas. A tela volta ao texto antigo,
    /// que é o certo: ressalva inventada sobre dado que ninguém mediu é pior
    /// do que ressalva nenhuma.
    func testBancoSemAsDatasMantemAFraseAntiga() {
        let t = Similares.paragrafo(resumo(), atributos: atributos)
        XCTAssertTrue(t.contains("I found 230 panel items"))
        XCTAssertFalse(t.contains("last seen"))
    }

    /// O contrato da A57 chega inteiro pelo decodificador -- inclusive o
    /// `visto_em` de cada peça, que sustenta o intervalo declarado.
    func testContratoDaA57ChegaPeloDecodificador() throws {
        let json = #"{"resumo":{"n_similares":20,"n_marcas":3,"atributos_pedidos":2,"minimo_em_comum":2,"n_com_todos":20,"com_preco":18,"exibidos":8,"observado_em":"2026-09-02","observado_mais_antigo_em":"2026-08-27","dias_desde_a_observacao":15},"pecas":[{"id":7,"marca":"Farm","titulo":"Vestido","em_comum":2,"visto_em":"2026-09-02"}]}"#
        let r = try JSONDecoder().decode(
            Similares.Resposta.self, from: Data(json.utf8))
        XCTAssertEqual(r.resumo?.diasDesdeAObservacao, 15)
        XCTAssertEqual(r.resumo?.observadoMaisAntigoEm, "2026-08-27")
        XCTAssertEqual(r.pecas.first?.vistoEm, "2026-09-02")
    }

    /// O caso que a ancora por segmento permite: metade do conjunto visto
    /// ontem, metade ha oito dias, porque a janela de frescor tolera sete dias
    /// a partir da ancora. Se o "agora" olhasse so a ponta nova, uma semana de
    /// atraso passaria por atual.
    func testIdadesMistasNaoPassamPorAtual() {
        var r = resumo()
        r.observadoEm = "2026-09-17"
        r.observadoMaisAntigoEm = "2026-09-10"
        r.diasDesdeAObservacao = 1
        r.diasDesdeAObservacaoMaisAntiga = 8
        XCTAssertFalse(Similares.ehDeAgora(r),
                       "a ponta velha é quem decide")
        let t = Similares.paragrafo(r, atributos: atributos)
        XCTAssertTrue(t.contains("between 10/09/2026 and 17/09/2026"))
        XCTAssertTrue(t.contains("the oldest 8 days ago"))
        // Preço e grade foram lidos NAQUELA observação.
        XCTAssertTrue(t.contains("were at full price then"))
        XCTAssertTrue(t.contains("had missing sizes"))
        XCTAssertTrue(t.contains("The median price then was"))
        XCTAssertFalse(t.contains("remain at full price"))
    }

    /// Com tudo visto ontem, nada de ressalva: o conjunto é do presente e o
    /// texto volta ao tempo presente.
    func testConjuntoInteiroDeOntemContinuaNoPresente() {
        var r = resumo()
        r.observadoEm = "2026-09-17"
        r.observadoMaisAntigoEm = "2026-09-17"
        r.diasDesdeAObservacao = 1
        r.diasDesdeAObservacaoMaisAntiga = 1
        XCTAssertTrue(Similares.ehDeAgora(r))
        let t = Similares.paragrafo(r, atributos: atributos)
        XCTAssertTrue(t.contains("remain at full price"))
        XCTAssertTrue(t.contains("The median price is"))
        XCTAssertFalse(t.contains("last seen"))
    }

    /// Zero também tem época. Sem a data do painel, "não encontrei nenhuma"
    /// vira uma afirmação sobre hoje feita com um painel de duas semanas.
    func testResultadoVazioDeclaraADataDoPainel() {
        var r = resumo(similares: 0, marcas: 0, comTodos: 0, comPreco: 0,
                       cheio: nil, quebrada: nil, esgotada: nil, mediana: nil)
        r.painelObservadoEm = "2026-09-02"
        r.painelDiasDesdeAObservacao = 15
        let t = Similares.paragrafo(r, atributos: atributos)
        XCTAssertTrue(t.contains("no panel item with"))
        XCTAssertTrue(t.contains("when the panel was last seen, on 02/09/2026"))
        XCTAssertTrue(t.contains("2 weeks ago"))
    }

    /// Painel em dia: a frase diz a data sem transformar normalidade em
    /// ressalva.
    func testResultadoVazioComPainelEmDiaDizAData() {
        var r = resumo(similares: 0, marcas: 0, comTodos: 0, comPreco: 0,
                       cheio: nil, quebrada: nil, esgotada: nil, mediana: nil)
        r.painelObservadoEm = "2026-09-17"
        r.painelDiasDesdeAObservacao = 0
        let t = Similares.paragrafo(r, atributos: atributos)
        XCTAssertTrue(t.contains("in the panel seen on 17/09/2026"))
        XCTAssertFalse(t.contains("ago"))
    }

    /// Banco anterior à A57 não manda data nenhuma. A frase fica neutra: não
    /// alegar período é melhor do que alegar o período errado.
    func testResultadoVazioSemDataNaoAlegaPeriodo() {
        let r = resumo(similares: 0, marcas: 0, comTodos: 0, comPreco: 0,
                       cheio: nil, quebrada: nil, esgotada: nil, mediana: nil)
        let t = Similares.paragrafo(r, atributos: atributos)
        XCTAssertTrue(t.contains("I found no panel item with"))
        XCTAssertFalse(t.contains("panel seen on"))
        XCTAssertFalse(t.contains("last seen"))
        XCTAssertNil(Similares.quandoOPainelFoiConsultado(r))
    }

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
    // MARK: O resultado e o critério não podem discordar (27/08)

    private func resumoRelaxado(similares: Int = 9, marcas: Int = 2,
                                dimensoes: Int = 5,
                                minimoDimensoes: Int = 3) -> Similares.Resumo {
        Similares.Resumo(
            nSimilares: similares, nMarcas: marcas, atributosPedidos: 7,
            dimensoesPedidas: dimensoes, minimoEmComum: 3,
            minimoDimensoes: minimoDimensoes, dimensaoRelaxada: "cor",
            nComTodos: 0, comPreco: similares,
            pctPrecoCheio: nil, pctGradeQuebrada: nil, pctEsgotada: nil,
            precoMin: 79, precoMax: 299, precoMediana: 179,
            percentilDoAlvo: nil, exibidos: min(similares, 8))
    }

    /// O defeito que o desenho da tela do relatório expôs.
    ///
    /// Quando o motor afrouxa, os cartões dizem "3 of 5 · no gray or solid" e o
    /// Result dizia, logo acima, que encontrou peças **com** os sete atributos.
    /// Duas partes da mesma tela afirmando coisas opostas — e a pessoa acredita
    /// na primeira, que é a que está em cima.
    func testResultadoNaoAfirmaTodosOsAtributosQuandoOMotorAfrouxou() {
        let r = resumoRelaxado()
        XCTAssertTrue(Similares.afrouxou(r))

        let frases = Similares.frasesDoResumo(r, atributos: atributos)
        let primeira = frases[0]
        XCTAssertTrue(primeira.contains("close to"),
                      "a frase precisa dizer que são aproximações: \(primeira)")
        XCTAssertTrue(primeira.contains("none matches all of them"),
                      "e precisa negar o casamento completo: \(primeira)")
        XCTAssertFalse(primeira.contains("items with Dress"),
                       "não pode anunciar as peças COM a lista inteira")
    }

    /// Sem afrouxamento, a frase antiga continua valendo palavra por palavra.
    func testSemAfrouxamentoAFraseContinuaAAfirmativa() {
        let r = resumo(similares: 230, marcas: 9)
        XCTAssertFalse(Similares.afrouxou(r))
        XCTAssertTrue(Similares.frasesDoResumo(r, atributos: atributos)[0]
            .contains("panel items with"))
    }

    /// Zero resultado precisa dizer que a busca larga já foi tentada. Sem isso,
    /// a pessoa desmarca um atributo à mão achando que resolve — e o motor já
    /// tinha feito exatamente isso por ela.
    func testZeroContaQueAJanelaLargaTambemFalhou() {
        let vazio = Similares.Resumo(
            nSimilares: 0, nMarcas: 0, atributosPedidos: 7,
            dimensoesPedidas: 5, minimoEmComum: 4, minimoDimensoes: 4,
            dimensaoRelaxada: nil, nComTodos: 0, comPreco: 0,
            pctPrecoCheio: nil, pctGradeQuebrada: nil, pctEsgotada: nil,
            precoMin: nil, precoMax: nil, precoMediana: nil,
            percentilDoAlvo: nil, exibidos: 0)
        let frase = Similares.frasesDoResumo(vazio, atributos: atributos)[0]
        XCTAssertTrue(frase.contains("wider match"), frase)
        XCTAssertTrue(frase.contains("cannot distinguish those cases"),
                      "a ressalva da §2 não pode ter sumido: \(frase)")
    }

    /// Com uma dimensão só não há o que largar, e a tela não pode dizer que
    /// tentou uma busca mais larga que nunca existiu.
    func testComUmaDimensaoNaoInventaUmaTentativaQueNaoHouve() {
        let vazio = Similares.Resumo(
            nSimilares: 0, nMarcas: 0, atributosPedidos: 1,
            dimensoesPedidas: 1, minimoEmComum: 1, minimoDimensoes: 1,
            dimensaoRelaxada: nil, nComTodos: 0, comPreco: 0,
            pctPrecoCheio: nil, pctGradeQuebrada: nil, pctEsgotada: nil,
            precoMin: nil, precoMax: nil, precoMediana: nil,
            percentilDoAlvo: nil, exibidos: 0)
        XCTAssertFalse(Similares.frasesDoResumo(vazio, atributos: atributos)[0]
            .contains("wider match"))
    }

}
