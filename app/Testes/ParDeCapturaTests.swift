import CoreGraphics
import XCTest
@testable import CanarioLogica

/// A separação entre "a foto que se olha" e "a foto que se mede".
///
/// Depois do teste em aparelho de 05/09 — *"senti que o flash deixou mais
/// difícil até de definir a cor"*, junto com *"acertou a cor marcada sim"* — a
/// rota de cor constante passou a devolver as duas fotos da mesma captura. A
/// natural é a que a pessoa vê, recorta e guarda; a de cor constante só mede.
///
/// O risco desta separação é sutil e não aparece na tela: medir a cor numa
/// imagem que **não corresponde** ao que a pessoa escolheu. Estes testes
/// guardam a regra que impede isso.
final class ParDeCapturaTests: XCTestCase {

    /// Um retângulo de uma cor só, para a leitura ser previsível.
    private func imagem(vermelho: Double, verde: Double, azul: Double) -> CGImage {
        let lado = 64
        var bytes = [UInt8](repeating: 0, count: lado * lado * 4)
        for pixel in 0..<(lado * lado) {
            bytes[pixel * 4] = UInt8(vermelho * 255)
            bytes[pixel * 4 + 1] = UInt8(verde * 255)
            bytes[pixel * 4 + 2] = UInt8(azul * 255)
            bytes[pixel * 4 + 3] = 255
        }
        let contexto = CGContext(
            data: &bytes, width: lado, height: lado, bitsPerComponent: 8,
            bytesPerRow: lado * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return contexto.makeImage()!
    }

    /// O caso que motivou tudo: a foto exibida está enviesada pela luz e a de
    /// medição não. A cor gravada tem de sair da segunda.
    func testACorSaiDaImagemDeMedicaoEnaoDaExibida() async {
        // Exibida: puxada para o quente, como sob lâmpada amarela.
        let exibida = imagem(vermelho: 0.86, verde: 0.72, azul: 0.30)
        // Medida: a mesma peça, cinza de verdade.
        let medida = imagem(vermelho: 0.55, verde: 0.55, azul: 0.56)

        let semPar = await LeitorDeArquivo.ler(exibida)
        let comPar = await LeitorDeArquivo.ler(exibida, imagemParaCor: medida,
                                               confiancaDaCaptura: 0.9)

        // `terrosos`, e não `amarelo_laranja`: nesta luminosidade o corte do
        // `CorDaPeca` separa caramelo/mostarda de amarelo puro. O ponto do
        // teste não é qual dos dois quentes sai — é que sai um quente onde a
        // peça é cinza.
        XCTAssertEqual(semPar.cor?.termoId, "terrosos",
                       "sem par, a leitura acompanha a luz da sala")
        XCTAssertEqual(comPar.cor?.termoId, "cinza",
                       "com par, a leitura acompanha a peça")
    }

    /// `nil` continua sendo o caminho de quase todas as fotos: fototeca,
    /// arquivo, PDF e câmera comum. Ele não pode ter mudado.
    func testSemImagemDeMedicaoTudoAcontecenaMesmaImagem() async {
        let unica = imagem(vermelho: 0.10, verde: 0.10, azul: 0.11)
        let leitura = await LeitorDeArquivo.ler(unica)
        XCTAssertEqual(leitura.cor?.termoId, "preto")
        XCTAssertNil(leitura.cor?.confiancaDaCaptura,
                     "sem rota de cor constante, a confiança é não medida")
        XCTAssertTrue(leitura.cor?.podeSugerirCor ?? false,
                      "e o formulário continua sugerindo como sempre sugeriu")
    }

    /// A confiança viaja com a medição, não com a imagem exibida: é o portão
    /// que decide se a cor chega pré-marcada.
    func testConfiancaBaixaFechaOPortaoMesmoComParValido() async {
        let exibida = imagem(vermelho: 0.55, verde: 0.55, azul: 0.56)
        let medida = imagem(vermelho: 0.55, verde: 0.55, azul: 0.56)
        let leitura = await LeitorDeArquivo.ler(exibida, imagemParaCor: medida,
                                                confiancaDaCaptura: 0.2)
        XCTAssertEqual(leitura.cor?.termoId, "cinza")
        XCTAssertFalse(leitura.cor?.podeSugerirCor ?? true,
                       "medida ruim não pré-marca, mesmo com o par correto")
    }
}
