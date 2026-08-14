import CoreVideo
import XCTest
@testable import CanarioLogica

/// Regressão do defeito de 14/08/2026: o app exigia `OneComponent8` e o Vision
/// devolvia `OneComponent32Float`. Toda máscara era descartada em silêncio, o
/// recorte nunca acontecia e a foto crua — com fundo — seguia para a análise.
/// O teste trava o contrato nos dois formatos e o rejeito explícito de um
/// terceiro, que não pode voltar a virar "não achei peça".
final class MascaraDeInstanciaTests: XCTestCase {
    private let largura = 40
    private let altura = 60

    /// Retângulo central cobrindo 25% da área.
    private func desenho(_ x: Int, _ y: Int) -> Bool {
        (10..<30).contains(x) && (15..<45).contains(y)
    }

    private func buffer(formato: OSType) -> CVPixelBuffer {
        var saida: CVPixelBuffer?
        CVPixelBufferCreate(nil, largura, altura, formato, nil, &saida)
        let buffer = saida!
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let passo = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<altura {
            for x in 0..<largura {
                let dentro = desenho(x, y)
                if formato == kCVPixelFormatType_OneComponent8 {
                    base.advanced(by: y * passo)
                        .assumingMemoryBound(to: UInt8.self)[x] = dentro ? 255 : 0
                } else {
                    base.advanced(by: y * passo)
                        .assumingMemoryBound(to: Float.self)[x] = dentro ? 1 : 0
                }
            }
        }
        return buffer
    }

    func testLeOitoBitsETrintaEDoisFloatComOMesmoResultado() throws {
        let oito = try MascaraDeInstancia.medir(
            MascaraDeInstancia.ler(buffer(formato: kCVPixelFormatType_OneComponent8)))
        let float = try MascaraDeInstancia.medir(
            MascaraDeInstancia.ler(buffer(formato: kCVPixelFormatType_OneComponent32Float)))

        let medida = try XCTUnwrap(oito, "OneComponent8 precisa produzir medida")
        XCTAssertEqual(float, medida,
                       "OneComponent32Float é o formato que o Vision devolve hoje")
        XCTAssertEqual(medida.limites, CGRect(x: 10, y: 15, width: 20, height: 30))
        XCTAssertEqual(medida.cobertura, 0.25, accuracy: 0.001)
    }

    func testFormatoDesconhecidoEErroENaoMascaraVazia() {
        var saida: CVPixelBuffer?
        CVPixelBufferCreate(nil, largura, altura, kCVPixelFormatType_32BGRA, nil, &saida)
        XCTAssertThrowsError(try MascaraDeInstancia.ler(saida!)) { erro in
            guard case MascaraDeInstancia.Falha.formatoDesconhecido = erro else {
                return XCTFail("formato novo precisa ser distinguível de máscara vazia")
            }
        }
    }

    func testMascaraQuaseVaziaEQuaseTotalSaoRecusadas() throws {
        let vazia = MascaraDeInstancia.Leitura(
            valores: [Float](repeating: 0, count: largura * altura),
            largura: largura, altura: altura)
        XCTAssertNil(MascaraDeInstancia.medir(vazia), "ruído não é peça")

        let total = MascaraDeInstancia.Leitura(
            valores: [Float](repeating: 1, count: largura * altura),
            largura: largura, altura: altura)
        XCTAssertNil(MascaraDeInstancia.medir(total),
                     "cobrir a foto inteira não é remover fundo")
    }
}
