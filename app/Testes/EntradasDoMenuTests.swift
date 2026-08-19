import XCTest
@testable import CanarioLogica

/// O menu misturava ação e leitura com o mesmo peso visual: seis entradas de
/// 29 pt e 104 pt de altura, uma embaixo da outra. Metade da tela ia para
/// Terms, Privacy e Q&A — textos que se abrem uma vez na vida, quando se abrem.
///
/// A revisão de UX da 1.0 apontou isso, e a separação virou dado em vez de
/// ordem numa lista, para uma entrada nova não poder desfazer a hierarquia
/// sozinha.
final class EntradasDoMenuTests: XCTestCase {

    func testAcaoELeituraEstaoSeparadas() {
        XCTAssertEqual(EntradaDoMenu.acoes, [.favoritos, .conta, .ajustes])
        XCTAssertEqual(EntradaDoMenu.leituras, [.termos, .privacidade, .perguntas])
    }

    /// Toda entrada pertence a exatamente uma família — nenhuma fica de fora
    /// das duas listas que a tela desenha, e nenhuma aparece nas duas.
    func testTodaEntradaAparaceEmExatamenteUmaFamilia() {
        let juntas = EntradaDoMenu.acoes + EntradaDoMenu.leituras
        XCTAssertEqual(juntas.count, EntradaDoMenu.allCases.count)
        XCTAssertEqual(Set(juntas), Set(EntradaDoMenu.allCases))
    }

    /// Os títulos são a chave que a navegação usa para escolher o destino.
    /// Se um mudar aqui sem mudar lá, a pessoa toca e não abre nada.
    func testTitulosSaoOsDestinosConhecidos() {
        XCTAssertEqual(EntradaDoMenu.allCases.map(\.titulo),
                       ["Favorites", "Account", "Settings",
                        "Terms", "Privacy", "Q&A"])
    }

    func testNenhumTituloSeRepete() {
        let titulos = EntradaDoMenu.allCases.map(\.titulo)
        XCTAssertEqual(Set(titulos).count, titulos.count)
    }

    func testBuscaPeloTituloEncontraEDevolveNilNoDesconhecido() {
        XCTAssertEqual(EntradaDoMenu.pelaTitulo("Privacy"), .privacidade)
        XCTAssertEqual(EntradaDoMenu.pelaTitulo("Favorites"), .favoritos)
        XCTAssertNil(EntradaDoMenu.pelaTitulo("Configurações"))
        XCTAssertNil(EntradaDoMenu.pelaTitulo(""))
    }

    /// O texto jurídico continua alcançável. Escondê-lo de vez seria trocar um
    /// problema de interface por um de conformidade.
    func testTextosObrigatoriosContinuamNoMenu() {
        for exigido in ["Terms", "Privacy"] {
            XCTAssertNotNil(EntradaDoMenu.pelaTitulo(exigido),
                            "\(exigido) não pode sumir do menu")
        }
    }
}
