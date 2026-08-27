import XCTest
#if canImport(AppKit)
import AppKit
#endif
@testable import CanarioLogica

/// O portão dos ícones da tela de atributos.
///
/// Existe por um modo de falha específico e silencioso: `Image(systemName:)`
/// com um nome que não existe **não** quebra a compilação e **não** lança
/// erro. Ele desenha um espaço vazio. Um `tshirt.fil` no lugar de
/// `tshirt.fill` atravessaria revisão, build, CI e TestFlight, e apareceria
/// como um buraco na grade na mão de quem estivesse usando o app.
///
/// O catálogo do SF Symbols é o mesmo no macOS e no iOS para os símbolos que
/// usamos aqui, então o teste roda no `swift test`, sem simulador.
final class IconesDaTaxonomiaTests: XCTestCase {

    func testTodoSimboloDoSistemaExisteNoCatalogo() throws {
        #if canImport(AppKit)
        let nomes = IconeDaTaxonomia.simbolosDoSistema
        XCTAssertFalse(nomes.isEmpty, "o mapa não citou nenhum SF Symbol")
        for nome in nomes {
            XCTAssertNotNil(
                NSImage(systemSymbolName: nome, accessibilityDescription: nil),
                "SF Symbol inexistente: \(nome). Ele desenharia um vazio na grade.")
        }
        #else
        throw XCTSkip("o catálogo do SF Symbols precisa de AppKit ou UIKit")
        #endif
    }

    /// Cor é o único caso sem ícone, e precisa continuar sendo: um símbolo no
    /// lugar da amostra apagaria a informação que a pessoa está lendo.
    func testTodaCorPedeAmostraENaoSimbolo() {
        for id in ["preto", "branco_cru", "cinza", "azul", "verde",
                   "lilas_roxo", "vermelho_rosa", "amarelo_laranja",
                   "terrosos", "outras_cores"] {
            XCTAssertEqual(IconeDaTaxonomia.para(id: id), .amostraDeCor,
                           "\(id) deveria ser amostra de cor")
        }
    }

    /// `trico_croche` é alias de `malha` desde a A26. Um id canônico e um
    /// alias apontando para desenhos diferentes deixariam a mesma peça com
    /// dois ícones conforme o caminho que a trouxe.
    func testAliasEIdCanonicoCompartilhamOIcone() {
        XCTAssertEqual(IconeDaTaxonomia.para(id: "trico_croche"),
                       IconeDaTaxonomia.para(id: "malha"))
    }

    /// Categoria é a grade que abre a tela. Nenhuma das oito pode ficar sem
    /// desenho, e duas não podem compartilhar o mesmo — numa grade de 60 pt o
    /// rótulo sozinho não resolve a ambiguidade rápido o bastante.
    func testAsOitoCategoriasTemIconesDistintos() {
        let categorias = ["blusa_top", "camisa", "vestido", "saia",
                          "calca", "short", "casaco_jaqueta", "macacao"]
        var vistos: Set<String> = []
        for id in categorias {
            let icone = IconeDaTaxonomia.para(id: id)
            XCTAssertNotNil(icone, "categoria sem ícone: \(id)")
            XCTAssertNotEqual(icone, .amostraDeCor)
            let chave = String(describing: icone)
            XCTAssertTrue(vistos.insert(chave).inserted,
                          "duas categorias com o mesmo ícone: \(id)")
        }
    }

    /// Termo que este app ainda não conhece devolve `nil` de propósito: a tela
    /// mostra o rótulo sem desenho e a opção continua selecionável. Devolver
    /// um símbolo genérico esconderia a falta, e o portão do CSV não teria
    /// como acusá-la.
    func testTermoDesconhecidoNaoGanhaIconeDeConsolacao() {
        XCTAssertNil(IconeDaTaxonomia.para(id: "termo_que_nao_existe"))
    }
}
