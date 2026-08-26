import XCTest

final class CanarioUITests: XCTestCase {
    private func aplicativo(argumentos: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = argumentos
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
            app.terminate()
        }
    }

    func testConfirmacaoFinalSalvaSemTelaRepetidaDeClothingDetails() {
        let app = aplicativo(argumentos: ["-CanarioUITestDetalhes"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Confirm your item"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add to Closet"].exists)
        XCTAssertTrue(app.textFields["Clothing name (optional)"].exists)
        XCTAssertTrue(app.buttons["Dress"].exists)
        XCTAssertTrue(app.buttons["Black"].exists)
        XCTAssertTrue(app.buttons["Back"].exists)
        XCTAssertFalse(app.buttons["Open Clothing Details"].exists)
        XCTAssertFalse(app.staticTexts["Keep this item"].exists)
    }

    func testPrivacyAbrePeloCaminhoDeterministico() {
        let app = aplicativo(argumentos: ["-CanarioAbrirPrivacy"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy in this build"].exists)
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    func testImportacaoAbreSemRedeComAsEntradasPrincipais() {
        let app = aplicativo(argumentos: ["-CanarioUITestImportacao"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Analyze an item"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose from Photos"].exists)
        XCTAssertTrue(app.buttons["Choose a file or PDF"].exists)
        XCTAssertTrue(app.staticTexts["Your intended price"].exists)
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    func testCompareNaoFicaReduzidoAUmAtributo() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] == "true",
                      "este teste valida o recorte real e o CI usa Config de exemplo sem rede")
        let app = aplicativo(argumentos: ["-CanarioUITestCompare"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Compare"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Dress"].waitForExistence(timeout: 15))
        XCTAssertGreaterThan(app.buttons.count, 1,
                             "a semana parcial não pode esconder os demais atributos")
    }

    func testStripesMostraCurvaDeTamanhosReal() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] == "true",
                      "este teste valida o recorte real e o CI usa Config de exemplo sem rede")
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
