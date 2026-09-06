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

    /// Os títulos são o TEXTO da tela; a chave de navegação é o `rawValue`.
    ///
    /// Este teste roda no pacote de lógica, fora do bundle do app, e por isso
    /// `frase(_:)` devolve a própria chave — ou seja, o inglês do catálogo. É
    /// exatamente o que se quer conferir aqui: o idioma-fonte não mudou. Que a
    /// tradução chega à tela é assunto do app, não deste alvo.
    func testTitulosSaoOsDestinosConhecidos() {
        XCTAssertEqual(EntradaDoMenu.allCases.map(\.titulo),
                       ["Favorites", "Account", "Settings",
                        "Terms", "Privacy", "Q&A"])
    }

    func testNenhumTituloSeRepete() {
        let titulos = EntradaDoMenu.allCases.map(\.titulo)
        XCTAssertEqual(Set(titulos).count, titulos.count)
    }

    /// A busca é pela CHAVE, e a chave não traduz.
    ///
    /// O teste antigo casava contra o rótulo exibido, que era também o
    /// identificador. Em português esse casamento devolveria `nil` para todas
    /// as entradas e cada item do menu abriria o destino errado — sem erro,
    /// sem crash e sem nenhum teste falhando, porque os dois lados liam o
    /// mesmo literal. A chave separada é o que torna isso impossível.
    func testBuscaPelaChaveEncontraEDevolveNilNoDesconhecido() {
        XCTAssertEqual(EntradaDoMenu.pelaChave("privacidade"), .privacidade)
        XCTAssertEqual(EntradaDoMenu.pelaChave("favoritos"), .favoritos)
        XCTAssertNil(EntradaDoMenu.pelaChave("Privacy"),
                     "rótulo exibido não pode voltar a servir de chave")
        XCTAssertNil(EntradaDoMenu.pelaChave(""))
    }

    /// As chaves são contrato de navegação: mudá-las quebra os atalhos de
    /// inspeção visual e qualquer estado restaurado.
    func testChavesDeNavegacaoNaoMudam() {
        XCTAssertEqual(EntradaDoMenu.allCases.map(\.rawValue),
                       ["favoritos", "conta", "ajustes",
                        "termos", "privacidade", "perguntas"])
    }

    /// O texto jurídico continua alcançável. Escondê-lo de vez seria trocar um
    /// problema de interface por um de conformidade.
    func testTextosObrigatoriosContinuamNoMenu() {
        for exigido in ["termos", "privacidade"] {
            XCTAssertNotNil(EntradaDoMenu.pelaChave(exigido),
                            "\(exigido) não pode sumir do menu")
        }
    }
}
