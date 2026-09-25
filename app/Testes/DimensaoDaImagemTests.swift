import XCTest
@testable import CanarioLogica

final class DimensaoDaImagemTests: XCTestCase {
    func testFotoDeCameraCabeNoTetoSemMudarAProporcao() {
        let pixels = DimensaoDaImagem.limitada(
            largura: 4_032, altura: 3_024, ladoMaximo: 2_400)
        XCTAssertEqual(pixels, .init(largura: 2_400, altura: 1_800))
        XCTAssertEqual(pixels?.bytesRGBA, 17_280_000)
    }

    func testRetratoUsaOMesmoTetoNoOutroEixo() {
        XCTAssertEqual(
            DimensaoDaImagem.limitada(
                largura: 3_024, altura: 4_032, ladoMaximo: 2_400),
            .init(largura: 1_800, altura: 2_400))
    }

    func testImagemMenorNuncaEAmpliada() {
        XCTAssertEqual(
            DimensaoDaImagem.limitada(
                largura: 1_200, altura: 900, ladoMaximo: 2_400),
            .init(largura: 1_200, altura: 900))
    }

    func testTetoQuadradoFicaAbaixoDeVinteETresMegabytesRGBA() {
        let pixels = DimensaoDaImagem.limitada(
            largura: 12_096, altura: 12_096, ladoMaximo: 2_400)
        XCTAssertLessThanOrEqual(pixels?.bytesRGBA ?? .max, 23_040_000)
    }

    func testDimensaoInvalidaNaoViraBitmapPlausivel() {
        XCTAssertNil(DimensaoDaImagem.limitada(
            largura: 0, altura: 3_024, ladoMaximo: 2_400))
        XCTAssertNil(DimensaoDaImagem.limitada(
            largura: 4_032, altura: -1, ladoMaximo: 2_400))
        XCTAssertNil(DimensaoDaImagem.limitada(
            largura: 4_032, altura: 3_024, ladoMaximo: 0))
    }
}
