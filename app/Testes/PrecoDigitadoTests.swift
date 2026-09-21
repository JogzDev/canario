import XCTest
@testable import CanarioLogica

final class PrecoDigitadoTests: XCTestCase {
    private func valor(_ texto: String, file: StaticString = #filePath,
                       line: UInt = #line) -> Double {
        guard case let .valor(valor) = PrecoDigitado.interpretar(texto) else {
            XCTFail("\(texto) não foi reconhecido como preço", file: file,
                    line: line)
            return .nan
        }
        return valor
    }

    func testDecimalPtEEnTemOMesmoValor() {
        XCTAssertEqual(valor("79,90"), 79.90, accuracy: 0.0001)
        XCTAssertEqual(valor("79.90"), 79.90, accuracy: 0.0001)
    }

    func testMilharComCentavosPtEEn() {
        XCTAssertEqual(valor("R$ 1.299,90"), 1_299.90, accuracy: 0.0001)
        XCTAssertEqual(valor("BRL 1,299.90"), 1_299.90, accuracy: 0.0001)
        XCTAssertEqual(valor("1299.90"), 1_299.90, accuracy: 0.0001)
    }

    func testInteiroEGruposDeMilhar() {
        XCTAssertEqual(valor("1299"), 1_299)
        XCTAssertEqual(valor("1.299.000"), 1_299_000)
        XCTAssertEqual(valor("1,299,000"), 1_299_000)
    }

    func testUmSeparadorComTresDigitosNaoEInventado() {
        XCTAssertEqual(PrecoDigitado.interpretar("1.299"), .ambiguo)
        XCTAssertEqual(PrecoDigitado.interpretar("1,299"), .ambiguo)
    }

    func testVazioContinuaOpcionalMasLixoNaoSomeEmSilencio() {
        XCTAssertEqual(PrecoDigitado.interpretar("  "), .vazio)
        for texto in ["R$", "zero", "-10", "0", "12,34.56", "1.234.56"] {
            XCTAssertEqual(PrecoDigitado.interpretar(texto), .invalido, texto)
        }
    }

    func testConfirmacaoMantemCentavosAcimaDeCem() {
        XCTAssertEqual(Formato.dinheiroExato(1_299.90), "R$ 1.299,90")
    }
}
