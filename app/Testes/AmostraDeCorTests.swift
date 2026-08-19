import XCTest
@testable import CanarioLogica

/// A amostra de cor que aparece no chip tem de ser fiel ao classificador.
///
/// Se o quadradinho mostrasse um verde que o próprio app classificaria como
/// azul, ele estaria ensinando a taxonomia errada — e ninguém perceberia,
/// porque as duas coisas moram em lugares diferentes da tela.
final class AmostraDeCorTests: XCTestCase {

    private let coresDaTaxonomia = [
        "vermelho_rosa", "amarelo_laranja", "terrosos", "verde",
        "azul", "lilas_roxo", "preto", "branco_cru", "cinza",
    ]

    /// O teste que sustenta a ideia inteira: pintar a amostra e pedir ao
    /// classificador que a nomeie tem de devolver o termo de onde ela saiu.
    func testCadaAmostraReclassificaEmSiMesma() {
        for id in coresDaTaxonomia {
            guard let rgb = CorDaPeca.rgbRepresentativo(de: id) else {
                XCTFail("\(id) não tem amostra")
                continue
            }
            let devolvido = CorDaPeca.termo(paraRGB: [rgb.0, rgb.1, rgb.2])
            XCTAssertEqual(devolvido, id,
                           "a amostra de \(id) é classificada como \(devolvido)")
        }
    }

    /// `outras_cores` é a categoria residual, não uma cor. Inventar um
    /// quadradinho para ela seria afirmar o que não se sabe.
    func testCategoriaResidualNaoTemAmostra() {
        XCTAssertNil(CorDaPeca.rgbRepresentativo(de: "outras_cores"))
    }

    /// Termo que não é de cor nenhuma também não tem amostra.
    func testTermoDeOutraDimensaoNaoTemAmostra() {
        for id in ["listra", "vestido", "algodao", ""] {
            XCTAssertNil(CorDaPeca.rgbRepresentativo(de: id))
        }
    }

    /// Componentes fora de [0,1] gerariam cor inválida na tela.
    func testAmostrasEstaoNaFaixaValida() {
        for id in coresDaTaxonomia {
            let rgb = CorDaPeca.rgbRepresentativo(de: id)!
            for c in [rgb.0, rgb.1, rgb.2] {
                XCTAssertTrue((0...1).contains(c), "\(id) fora da faixa: \(c)")
            }
        }
    }
}
