import XCTest

final class CanarioUITests: XCTestCase {
    /// Todo fluxo abre o app **em inglês**, e isso é fixado aqui.
    ///
    /// Desde a A53 a interface segue o idioma do iPhone por padrão, e estas
    /// asserções procuram rótulos em inglês ("Add your clothes", "Filter
    /// Closet"). Num simulador em português elas falhariam sem que nada
    /// estivesse quebrado — e, pior, num simulador em inglês continuariam
    /// verdes escondendo uma regressão de tradução. Fixar o idioma separa as
    /// duas perguntas: aqui se testa NAVEGAÇÃO, e a tradução tem portão
    /// próprio (`ferramentas/extrair_frases.py --conferir`).
    ///
    /// `-chave valor` no argumento de lançamento entra no `UserDefaults` do
    /// processo, que é de onde o `GestorDeIdioma` lê. Não grava nada no
    /// aparelho: vale só para esta execução.
    private static let idiomaFixo = ["-idioma_da_interface", "ingles"]

    private func aplicativo(argumentos: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Self.idiomaFixo + argumentos
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // 2.0: o manequim saiu; o Estúdio abre com a pergunta e a ação principal,
    // e a conta é uma sheet do sistema no lugar do menu lateral.
    func testEstudioAbreComAcaoPrincipalEConta() {
        let app = aplicativo(argumentos: ["-CanarioAbrirEstudio"])
        app.launch()

        XCTAssertTrue(app.staticTexts["What do you have in hand?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add a clothing item"].exists)

        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Privacy"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    func testClosetContinuaAcessivelSemRede() {
        let app = aplicativo(argumentos: ["-CanarioAbrirCloset"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Archive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Account"].exists)
        XCTAssertTrue(app.buttons["Filter Archive"].exists)
        app.buttons["Filter Archive"].tap()
        XCTAssertTrue(app.navigationBars["Filter Archive"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Favorites only"].exists)
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    func testAsTresTelasPrincipaisAbremAMesmaConta() {
        // Esta semana (padrão), Acervo e Estúdio.
        for argumento in [nil, "-CanarioAbrirCloset", "-CanarioAbrirEstudio"] {
            let app = aplicativo(argumentos: argumento.map { [$0] } ?? [])
            app.launch()

            XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
            app.buttons["Account"].tap()
            XCTAssertTrue(app.buttons["Privacy"].waitForExistence(timeout: 2))
            let pronto = app.buttons.matching(identifier: "Done")
            XCTAssertEqual(pronto.count, 1, "a sheet da conta tem uma saída só")
            pronto.element.tap()
            XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 2))
            app.terminate()
        }
    }

    // MARK: O bloco editorial da busca (A58)
    //
    // A RPC `buscar_referencia_editorial` ainda não está publicada, e os
    // fluxos do CI rodam sem rede. `-CanarioUITestImprensa <caso>` troca a
    // fonte da resposta por uma fixture em memória: nada aqui fala com o
    // servidor, e os quatro estados que interessam são todos de tela.

    private func abrirBusca(_ caso: String) -> XCUIApplication {
        let app = aplicativo(argumentos: ["-CanarioAbrirBusca",
                                          "-CanarioUITestImprensa", caso])
        app.launch()
        let campo = app.searchFields.firstMatch
        XCTAssertTrue(campo.waitForExistence(timeout: 10),
                      "a busca deveria abrir direto com -CanarioAbrirBusca")
        campo.tap()
        return app
    }

    func testBuscaDaEdicaoEnsinaVocabularioSemInventarMedia() {
        let app = aplicativo(argumentos: ["-CanarioAbrirBusca",
                                          "-CanarioUITestBuscaVocabulario",
                                          "-CanarioUITestImprensa", "vazio"])
        app.launch()

        XCTAssertTrue(app.staticTexts["Start with a word"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Dress"].exists)
        XCTAssertTrue(app.buttons["Black"].exists)
        let vazia = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vazia.name = "busca-v4-vazia"
        vazia.lifetime = .keepAlways
        add(vazia)

        let campo = app.searchFields.firstMatch
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.tap()
        campo.typeText("black dress")

        XCTAssertTrue(app.staticTexts["See similar pieces, attributes and the combined reading."]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Attributes"].exists)
        XCTAssertFalse(app.staticTexts["Combined reading"].exists,
                       "a busca nao pode fabricar a media dos indices dos atributos")
        let resultado = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resultado.name = "busca-v4-com-termos"
        resultado.lifetime = .keepAlways
        add(resultado)
    }

    func testBuscaSemTermoAindaOfereceLeituraDoTextoInteiro() {
        let app = aplicativo(argumentos: ["-CanarioAbrirBusca",
                                          "-CanarioUITestBuscaVocabulario",
                                          "-CanarioUITestImprensa", "vazio"])
        app.launch()
        let campo = app.searchFields.firstMatch
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.tap()
        campo.typeText("Napoleon Jacket")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Read “Napoleon Jacket” in the panel")
        ).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Attributes"].exists)
        let semTermo = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        semTermo.name = "busca-v4-sem-vocabulario"
        semTermo.lifetime = .keepAlways
        add(semTermo)
    }

    func testBuscaV4EmPortuguesMostraVocabularioELeitura() {
        let app = XCUIApplication()
        app.launchArguments = ["-idioma_da_interface", "portugues",
                               "-CanarioAbrirBusca", "-CanarioUITestBuscaVocabulario",
                               "-CanarioUITestImprensa", "vazio"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Comece por uma palavra"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Vestido"].exists)
        let vazia = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        vazia.name = "busca-v4-pt-vazia"
        vazia.lifetime = .keepAlways
        add(vazia)

        let campo = app.searchFields.firstMatch
        campo.tap()
        campo.typeText("vestido preto")
        XCTAssertTrue(app.staticTexts["Atributos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Ler “vestido preto” no painel")
        ).firstMatch.exists)
        app.swipeUp()
        let resultado = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resultado.name = "busca-v4-pt-resultado"
        resultado.lifetime = .keepAlways
        add(resultado)
    }

    func testEnviarBuscaAbreLeituraDoTextoSemUsarCota() {
        let app = XCUIApplication()
        app.launchArguments = ["-idioma_da_interface", "portugues",
                               "-CanarioUITestLeituraBusca", "-CanarioUITestBuscaVocabulario",
                               "-CanarioUITestImprensa", "vazio"]
        app.launch()

        let campo = app.searchFields.firstMatch
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.tap()
        campo.typeText("Napoleon Jacket\n")
        XCTAssertTrue(app.staticTexts["Uma peça do painel corresponde ao pedido."]
            .waitForExistence(timeout: 5))
    }

    func testImprensaMostraAMateriaQueContemAExpressao() {
        let app = abrirBusca("sucesso")
        app.searchFields.firstMatch.typeText("Napoleon Jacket")

        XCTAssertTrue(app.staticTexts["In the press"].waitForExistence(timeout: 10),
                      "o bloco editorial deveria aparecer com a matéria")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(
                format: "label CONTAINS 'Napoleon Jacket Is Making A Comeback'"))
                .firstMatch.exists,
            "o título gravado precisa aparecer inteiro, não reduzido a taxonomia")
    }

    func testImprensaSemMateriaNaoAbreBlocoVazio() {
        let app = abrirBusca("vazio")
        app.searchFields.firstMatch.typeText("Napoleon Jacket")

        // Dois segundos são mais que a pausa de 350 ms: se o bloco fosse
        // aparecer, já teria aparecido.
        XCTAssertFalse(app.staticTexts["In the press"].waitForExistence(timeout: 2),
                       "cabeçalho com 'nada encontrado' embaixo ocupa a tela para não dizer nada")
        XCTAssertFalse(app.staticTexts["imprensa-falhou"].exists)
    }

    func testImprensaDeclaraFalhaDeRedeEmVozBaixa() {
        let app = abrirBusca("erro")
        app.searchFields.firstMatch.typeText("Napoleon Jacket")

        XCTAssertTrue(app.staticTexts["imprensa-falhou"].waitForExistence(timeout: 10),
                      "falha de rede é declarada, não engolida")
        XCTAssertFalse(app.staticTexts["In the press"].exists)
    }

    func testImprensaCalaQuandoAFuncaoAindaNaoExiste() {
        let app = abrirBusca("ausente")
        app.searchFields.firstMatch.typeText("Napoleon Jacket")

        // PGRST202 é "a A58 ainda não subiu". Nesse caso, e só nesse, o bloco
        // não existe e não avisa nada: o app é publicado depois do banco, e
        // durante a janela de um aparelho adiantado o aviso seria ruído.
        XCTAssertFalse(app.staticTexts["imprensa-falhou"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["In the press"].exists)
    }

    /// A pergunta A responde DEPOIS da B. A tela tem de mostrar a B.
    func testRespostaLentaNaoSobrescreveAPerguntaNova() {
        let app = abrirBusca("troca")
        let campo = app.searchFields.firstMatch

        // Primeiro, A ja esta visivel quando B comeca. A troca e atomica pelo
        // controle de teste para nao passar por uma string com menos de tres
        // letras (esse caminho ja limpava o card e mascararia a regressao).
        campo.typeText("primeira")
        let visivelA = app.staticTexts["Resposta visivel da pergunta A"]
        XCTAssertTrue(visivelA.waitForExistence(timeout: 10))

        let trocar = app.buttons["trocar-consulta-editorial"]
        XCTAssertTrue(trocar.exists)
        trocar.tap()
        XCTAssertTrue(visivelA.waitForNonExistence(timeout: 1),
                      "A precisa sumir durante o debounce/rede de B")
        let tardiaB = app.staticTexts["Resposta tardia da pergunta B"]
        XCTAssertFalse(tardiaB.exists,
                       "o intervalo testado precisa ser anterior a resposta de B")
        XCTAssertTrue(tardiaB.waitForExistence(timeout: 10))

        // Agora preserva a segunda metade do contrato: uma A que ficou em voo
        // nao pode chegar depois e sobrescrever a B mais nova.
        app.terminate()
        let appDaCorrida = abrirBusca("troca")
        let campoDaCorrida = appDaCorrida.searchFields.firstMatch
        campoDaCorrida.typeText("lenta")
        // A resposta de "lenta" leva 1,5 s. A troca acontece dentro disso.
        campoDaCorrida.typeText(
            XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue
            + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue
            + XCUIKeyboardKey.delete.rawValue)
        campoDaCorrida.typeText("rapida")

        let rapida = appDaCorrida.staticTexts["Resposta rapida da pergunta B"]
        XCTAssertTrue(rapida.waitForExistence(timeout: 10),
                      "a resposta da pergunta atual deveria estar na tela")

        // E continua sendo a B depois que a A chega: 3 s cobre o 1,5 s da
        // resposta lenta com folga.
        let lenta = appDaCorrida.staticTexts["Resposta lenta da pergunta A"]
        XCTAssertFalse(lenta.waitForExistence(timeout: 3),
                       "resposta antiga não pode sobrescrever a nova")
        XCTAssertTrue(rapida.exists)
    }

    func testQEAAbreLegivelSobreEstaSemana() {
        let app = aplicativo()
        app.launch()

        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Q&A"].waitForExistence(timeout: 2))
        app.buttons["Q&A"].tap()

        XCTAssertTrue(app.staticTexts["What is a confirmed movement?"]
            .waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Why can two dates be different?"].exists)
        XCTAssertTrue(app.buttons["Back"].exists)
    }

    func testConfirmacaoFinalSalvaSemTelaRepetidaDeClothingDetails() {
        let app = aplicativo(argumentos: ["-CanarioUITestDetalhes"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Fill the info"]
            .waitForExistence(timeout: 5))
        // Guardar deixou de ser o fim do preenchimento em 27/08: o botão desta
        // tela leva ao mercado, e o Closet é a decisão da tela seguinte.
        XCTAssertTrue(app.buttons["Show me the market"].exists)
        XCTAssertFalse(app.buttons["Add to Closet"].exists)
        XCTAssertTrue(app.textFields["Clothing name (optional)"].exists)
        XCTAssertTrue(app.buttons["Dress"].exists)
        // A cor não se anuncia só como marcada: ela anuncia a POSIÇÃO. Quem
        // usa VoiceOver não vê o número dentro do círculo, e "preta" e
        // "preta, cor principal" são informações diferentes.
        XCTAssertTrue(app.buttons["Black, primary color"].exists)
        XCTAssertFalse(app.buttons["Black"].exists,
                       "sem a posição, o número na tela não teria equivalente falado")
        // O preço mudou de tela em 26/08: saiu da entrada e desceu para o fim
        // desta, depois dos atributos.
        XCTAssertTrue(app.staticTexts["Your intended price"].exists)
        XCTAssertTrue(app.buttons["Back"].exists)
        XCTAssertFalse(app.buttons["Open Clothing Details"].exists)
        XCTAssertFalse(app.staticTexts["Keep this item"].exists)

        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Photo options"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Back"].exists)

        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Choose from Photos"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Your intended price"].exists,
                       "o preço não mora mais na tela de entrada")
    }

    func testPrivacyAbrePeloCaminhoDeterministico() {
        let app = aplicativo(argumentos: ["-CanarioAbrirPrivacy"])
        app.launch()

        XCTAssertTrue(app.staticTexts["Privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy in this build"].exists)
        XCTAssertTrue(app.buttons["Back"].exists)
    }

    func testImportacaoAbreSemRedeComAsEntradasPrincipais() {
        let app = aplicativo(argumentos: ["-CanarioUITestImportacao"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Analyze an item"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose from Photos"].exists)
        XCTAssertTrue(app.buttons["Choose a file or PDF"].exists)
        // Três entradas e nada mais. O preço desceu para a tela de atributos.
        XCTAssertFalse(app.staticTexts["Your intended price"].exists)
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    func testAtributosAbremLeituraAntesDeSalvarSemUsarCota() {
        let app = aplicativo(argumentos: ["-CanarioUITestLeituraDaFoto"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Fill the info"].waitForExistence(timeout: 5))
        app.buttons["Show me the market"].tap()

        let ler = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Read this piece in the panel")
        ).firstMatch
        XCTAssertTrue(ler.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add to Closet"].exists,
                      "ler e salvar são escolhas separadas")
        ler.tap()
        XCTAssertTrue(app.staticTexts["Uma peça do painel corresponde ao pedido."]
            .waitForExistence(timeout: 5))
    }

    func testLeituraDaFotoEmPortuguesMostraAProva() {
        let app = XCUIApplication()
        app.launchArguments = ["-idioma_da_interface", "portugues", "-CanarioUITestLeituraDaFoto"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Preencha os dados"].waitForExistence(timeout: 5))
        app.buttons["Me mostre o mercado"].tap()
        let ler = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Ler esta peça no painel")
        ).firstMatch
        XCTAssertTrue(ler.waitForExistence(timeout: 5))
        let antes = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        antes.name = "foto-leitura-antes-de-salvar"
        antes.lifetime = .keepAlways
        add(antes)

        ler.tap()
        XCTAssertTrue(app.staticTexts["Uma peça do painel corresponde ao pedido."]
            .waitForExistence(timeout: 5))
        let leitura = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        leitura.name = "foto-leitura-com-prova"
        leitura.lifetime = .keepAlways
        add(leitura)

        app.buttons["Uma peça do painel corresponde ao pedido."].tap()
        XCTAssertTrue(app.navigationBars["Prova"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 peça do painel sustenta esta frase."].exists)
        XCTAssertTrue(app.staticTexts["Marca de teste"].exists)
        let prova = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        prova.name = "foto-leitura-prova-aberta"
        prova.lifetime = .keepAlways
        add(prova)
    }

    func testAtributoConfirmadoAbreRelatorio() {
        let app = XCUIApplication()
        app.launchArguments = ["-idioma_da_interface", "portugues", "-CanarioUITestLeituraDaFoto"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Preencha os dados"].waitForExistence(timeout: 5))
        app.buttons["Me mostre o mercado"].tap()
        let atributo = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                        "Vestido", "Categoria")
        ).firstMatch
        XCTAssertTrue(atributo.waitForExistence(timeout: 5))
        atributo.tap()
        XCTAssertTrue(app.staticTexts["Vestido"].waitForExistence(timeout: 10))

        let captura = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        captura.name = "relatorio-do-atributo"
        captura.lifetime = .keepAlways
        add(captura)
    }

    func testEstudioMostraLeituraFeitaSemChamarARede() {
        let app = XCUIApplication()
        app.launchArguments = ["-idioma_da_interface", "portugues",
                               "-CanarioAbrirEstudio", "-CanarioUITestLeiturasFeitas"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Leituras feitas"].waitForExistence(timeout: 5))
        let registro = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "saia midi plissada")
        ).firstMatch
        XCTAssertTrue(registro.exists)
        XCTAssertTrue(app.staticTexts["Peças: 1 · marcas: 1"].exists)
        let lista = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        lista.name = "estudio-leituras-feitas"
        lista.lifetime = .keepAlways
        add(lista)

        registro.tap()
        XCTAssertTrue(app.buttons["Ler de novo com o painel de hoje"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Há uma peça do painel neste recorte."].exists)
    }

    func testRefinamentoEPrecoRefazemLeituraComProva() {
        let app = XCUIApplication()
        app.launchArguments = ["-idioma_da_interface", "portugues", "-CanarioUITestLeituraDaFoto"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Preencha os dados"].waitForExistence(timeout: 5))
        app.buttons["Me mostre o mercado"].tap()
        let ler = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Ler esta peça no painel")
        ).firstMatch
        XCTAssertTrue(ler.waitForExistence(timeout: 5))
        ler.tap()

        XCTAssertTrue(app.buttons["cetim"].waitForExistence(timeout: 5))
        app.buttons["cetim"].tap()
        XCTAssertTrue(app.staticTexts["O recorte foi refinado para cetim."].waitForExistence(timeout: 5))

        let campo = app.textFields.firstMatch
        XCTAssertTrue(campo.waitForExistence(timeout: 5))
        campo.tap()
        campo.typeText("450")
        app.buttons["Comparar"].tap()
        let posicao = app.buttons["1 peça custa menos que a sua de R$ 450."]
        XCTAssertTrue(posicao.waitForExistence(timeout: 5))
        let captura = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        captura.name = "leitura-refinada-com-posicao-de-preco"
        captura.lifetime = .keepAlways
        add(captura)

        posicao.tap()
        XCTAssertTrue(app.navigationBars["Prova"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Marca de teste"].exists)
    }

    func testCompareNaoFicaReduzidoAUmAtributo() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CANARIO_REAL_DATA_UI_TESTS"] == "1",
            "este teste exige opt-in e configuração real; a automação usa placeholders")
        let app = aplicativo(argumentos: ["-CanarioUITestCompare"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Compare"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Dress"].waitForExistence(timeout: 15))
        XCTAssertGreaterThan(app.buttons.count, 1,
                             "a semana parcial não pode esconder os demais atributos")
    }

    func testStripesMostraCurvaDeTamanhosReal() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CANARIO_REAL_DATA_UI_TESTS"] == "1",
            "este teste exige opt-in e configuração real; a automação usa placeholders")
        let app = aplicativo(argumentos: ["-CanarioUITestSizesStripes"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Sizes · Stripes"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["What panel sizing is showing"]
            .waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Availability loss by size"].exists)
        XCTAssertTrue(app.staticTexts["PP"].exists)
        XCTAssertTrue(app.staticTexts["GG"].exists)
    }
}
