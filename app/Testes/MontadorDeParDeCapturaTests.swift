import XCTest
@testable import CanarioLogica

/// O AVFoundation não promete que a foto natural chega antes da constante.
/// Estes testes mantêm a regra independente de câmera e tornam a corrida
/// reproduzível no CI.
final class MontadorDeParDeCapturaTests: XCTestCase {
    private func captura(
        _ montador: inout MontadorDeParDeCaptura<String>,
        file: StaticString = #filePath, line: UInt = #line
    ) -> MontadorDeParDeCaptura<String>.Par {
        guard case let .captura(par) = montador.concluir() else {
            XCTFail("o disparo deveria produzir uma captura", file: file,
                    line: line)
            fatalError("captura ausente")
        }
        return par
    }

    func testNaturalAntesDaConstanteProduzOParCerto() {
        var montador = MontadorDeParDeCaptura<String>()
        montador.registrarNatural("natural")
        montador.registrarConstante("constante", confianca: 0.91)

        let par = captura(&montador)
        XCTAssertEqual(par.imagem, "natural")
        XCTAssertEqual(par.imagemDeMedicao, "constante")
        XCTAssertEqual(par.confianca, 0.91)
    }

    func testConstanteAntesDaNaturalProduzOMesmoPar() {
        var montador = MontadorDeParDeCaptura<String>()
        montador.registrarConstante("constante", confianca: 0.91)
        montador.registrarNatural("natural")

        let par = captura(&montador)
        XCTAssertEqual(par.imagem, "natural")
        XCTAssertEqual(par.imagemDeMedicao, "constante")
        XCTAssertEqual(par.confianca, 0.91)
    }

    func testSoANaturalPreservaAFotoSemInventarMedicao() {
        var montador = MontadorDeParDeCaptura<String>()
        montador.registrarNatural("natural")

        let par = captura(&montador)
        XCTAssertEqual(par.imagem, "natural")
        XCTAssertNil(par.imagemDeMedicao)
        XCTAssertNil(par.confianca)
    }

    func testSoAConstanteAindaPreservaODisparo() {
        var montador = MontadorDeParDeCaptura<String>()
        montador.registrarConstante("constante", confianca: 0.72)

        let par = captura(&montador)
        XCTAssertEqual(par.imagem, "constante")
        XCTAssertEqual(par.imagemDeMedicao, "constante")
        XCTAssertEqual(par.confianca, 0.72)
    }

    func testNenhumaImagemPermiteTentarNovamente() {
        var montador = MontadorDeParDeCaptura<String>()
        guard case .tentarNovamente = montador.concluir() else {
            return XCTFail("falha sem imagem não deve fechar a câmera")
        }
    }

    func testCancelamentoBloqueiaCallbacksTardiosESegundaSaida() {
        var montador = MontadorDeParDeCaptura<String>()
        XCTAssertTrue(montador.cancelar())
        XCTAssertFalse(montador.registrarNatural("tardia"))
        XCTAssertFalse(montador.registrarConstante("tardia", confianca: 1))
        XCTAssertFalse(montador.cancelar())
        guard case .ignorar = montador.concluir() else {
            return XCTFail("callback posterior ao cancelamento foi aceito")
        }
    }

    func testConclusaoAconteceUmaUnicaVez() {
        var montador = MontadorDeParDeCaptura<String>()
        montador.registrarNatural("natural")
        _ = captura(&montador)
        guard case .ignorar = montador.concluir() else {
            return XCTFail("o mesmo disparo produziu duas saídas")
        }
        XCTAssertFalse(montador.registrarNatural("tardia"))
    }
}
