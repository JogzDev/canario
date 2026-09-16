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

    func testAddAbreComAcaoPrincipalEMenu() {
        let app = aplicativo()
        app.launch()

        XCTAssertTrue(app.staticTexts["Add your clothes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add a clothing item"].exists)

        app.buttons["Open menu"].tap()
        XCTAssertTrue(app.buttons["Privacy"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    func testClosetContinuaAcessivelSemRede() {
        let app = aplicativo(argumentos: ["-CanarioAbrirCloset"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Closet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open menu"].exists)
        XCTAssertTrue(app.buttons["Filter Closet"].exists)
        app.buttons["Filter Closet"].tap()
        XCTAssertTrue(app.navigationBars["Filter Closet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Favorites only"].exists)
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    func testAsTresTelasPrincipaisUsamOMesmoMenu() {
        for argumento in [nil, "-CanarioAbrirCloset", "-CanarioAbrirTrends"] {
            let app = aplicativo(argumentos: argumento.map { [$0] } ?? [])
            app.launch()

            XCTAssertTrue(app.buttons["Open menu"].waitForExistence(timeout: 5))
            app.buttons["Open menu"].tap()
            XCTAssertTrue(app.buttons["Privacy"].waitForExistence(timeout: 2))
            let fechar = app.buttons.matching(identifier: "Close menu")
            XCTAssertEqual(fechar.count, 1,
                           "o botão coberto da barra não pode duplicar o X do painel")
            fechar.element.tap()
            XCTAssertTrue(app.buttons["Open menu"].waitForExistence(timeout: 2))
            app.terminate()
        }
    }

    func testQEAAbreLegivelSobreATrends() {
        let app = aplicativo(argumentos: ["-CanarioAbrirTrends"])
        app.launch()

        XCTAssertTrue(app.buttons["Open menu"].waitForExistence(timeout: 5))
        app.buttons["Open menu"].tap()
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

    func testCompareNaoFicaReduzidoAUmAtributo() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CANARIO_REAL_DATA_UI_TESTS"] == "1",
            "teste com dados reais exige opt-in explícito")
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
            "teste com dados reais exige opt-in explícito")
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
