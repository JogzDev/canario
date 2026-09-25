import XCTest
@testable import CanarioLogica

/// A navegação do app tem duas implementações — o `TabView` nativo do iOS 26 e
/// a barra desenhada à mão do iOS 17–25 — e elas já divergiram em produção: a
/// tela de tendências se chamava "Analytics" num iPhone e "Trends" no outro,
/// enquanto a ficha da App Store dizia "Trends". Ninguém viu porque o texto
/// morava dentro do corpo de duas `View`s, onde nenhum teste alcança.
///
/// Estes testes existem para que o rótulo tenha um dono só. Eles não olham
/// pixel nenhum: conferem a **fonte** que as duas navegações passaram a ler.
/// Tela se verifica olhando; o que é dado se verifica testando, e um nome de
/// aba é dado.
final class AbasDoAppTests: XCTestCase {

    /// O caso concreto que quebrou em 18/08 ("Analytics" num iPhone, "Trends"
    /// no outro). Na 2.0 (Seam) a aba passou a se chamar "This week" / "Esta
    /// semana", e a ficha da 2.0 na App Store tem de usar o mesmo nome — este
    /// teste é onde essa conversa acontece.
    func testTelaDaSemanaSeChamaThisWeekEmQualquerIPhone() {
        XCTAssertEqual(AbaDoApp.dados.titulo, "This week",
                       "A ficha da 2.0 diz 'This week'. Mudar aqui sem mudar "
                       + "lá recria a divergência de 18/08.")
    }

    /// Fonte única quer dizer: toda aba tem exatamente um título e um símbolo,
    /// e ninguém consegue definir metade.
    func testTodaAbaTemTituloESimbolo() {
        for aba in AbaDoApp.allCases {
            XCTAssertFalse(aba.titulo.isEmpty, "aba \(aba.rawValue) sem título")
            XCTAssertFalse(aba.simbolo.isEmpty, "aba \(aba.rawValue) sem símbolo")
        }
    }

    /// Dois rótulos iguais em abas diferentes é o mesmo defeito visto do outro
    /// lado: a pessoa não consegue dizer onde está.
    func testNenhumRotuloSeRepete() {
        let titulos = AbaDoApp.allCases.map(\.titulo)
        XCTAssertEqual(Set(titulos).count, titulos.count,
                       "duas abas com o mesmo nome: \(titulos)")
        let simbolos = AbaDoApp.allCases.map(\.simbolo)
        XCTAssertEqual(Set(simbolos).count, simbolos.count,
                       "duas abas com o mesmo ícone: \(simbolos)")
    }

    /// A barra de compatibilidade mostra `principais` e trata Search como
    /// botão separado; o iOS 26 usa `role: .search`, que também a tira da
    /// fileira. Se Search voltar a ser aba comum, as duas navegações passam a
    /// ter contagens diferentes de novo — foi assim que uma tinha 3 e a outra 4.
    func testBuscaFicaForaDaFileiraDeAbas() {
        XCTAssertTrue(AbaDoApp.buscar.ehBusca)
        XCTAssertFalse(AbaDoApp.principais.contains(.buscar),
                       "Search na fileira faz as duas navegações divergirem "
                       + "em número de abas")
        XCTAssertEqual(AbaDoApp.principais.count, AbaDoApp.allCases.count - 1)
    }

    /// A ordem é a mesma nas duas navegações porque as duas leem esta lista.
    /// Fixar aqui é o que impede a fileira de trocar de ordem só num iPhone.
    func testOrdemDaFileiraEstavel() {
        // 2.0: Esta semana · Acervo · Estúdio, com a Busca à parte.
        XCTAssertEqual(AbaDoApp.principais, [.dados, .armario, .adicionar])
        XCTAssertEqual(AbaDoApp.principais.map(\.titulo),
                       ["This week", "Archive", "Studio"])
    }

    /// O `rawValue` é o que a aba usa como identidade; trocá-lo silenciosamente
    /// quebraria o argumento de inspeção visual (`-CanarioAbrirCloset`).
    func testIdentidadeDasAbasNaoMuda() {
        XCTAssertEqual(AbaDoApp.allCases.map(\.rawValue),
                       ["adicionar", "armario", "dados", "buscar"])
    }
}
