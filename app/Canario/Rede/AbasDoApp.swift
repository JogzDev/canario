import Foundation

/// As abas do app, escritas uma vez só.
///
/// POR QUE ISTO EXISTE
/// ===================
///
/// A navegação estava escrita duas vezes: o `TabView` nativo do iOS 26, em
/// `CanarioApp.swift`, e a barra desenhada à mão do iOS 17–25, em
/// `BarraPrincipal.swift`. Cada uma trazia seus próprios títulos e símbolos.
///
/// Elas divergiram sem que nada percebesse. A mesma tela se chamava **Trends**
/// num iPhone e **Analytics** no outro, e a ficha da App Store dizia "Trends".
/// Não foi código descuidado: foi a mesma informação escrita em dois lugares,
/// o que é só uma questão de tempo até discordarem. Nenhum teste podia pegar
/// isso, porque não havia nada para um teste ler — o texto morava dentro do
/// corpo de duas `View`s.
///
/// Aqui não há SwiftUI de propósito. Sem SwiftUI este arquivo entra no pacote
/// `CanarioLogica` e é conferido a cada commit, em macOS, sem simulador —
/// que é a diferença entre uma regra escrita e uma regra que se sustenta.
///
/// As duas navegações continuam existindo, e devem continuar: cada sistema tem
/// seu idioma, e imitar Liquid Glass à mão no iOS 17 seria pior que a barra
/// atual. O que deixa de existir é a segunda cópia dos rótulos.
public enum AbaDoApp: String, CaseIterable, Sendable {
    case adicionar
    case armario
    case dados
    case buscar

    /// O texto que a pessoa lê. É este o valor que divergiu entre as duas
    /// navegações, e é por isso que ele agora tem um dono só.
    public var titulo: String {
        switch self {
        case .adicionar: return "Add"
        case .armario: return "Closet"
        case .dados: return "Trends"
        case .buscar: return "Search"
        }
    }

    /// Nome do símbolo do SF Symbols. Fica junto do título porque os dois
    /// identificam a mesma aba e separá-los recria o problema pela metade.
    public var simbolo: String {
        switch self {
        case .adicionar: return "hanger"
        case .armario: return "tshirt.fill"
        case .dados: return "chart.line.uptrend.xyaxis"
        case .buscar: return "magnifyingglass"
        }
    }

    /// Busca não é uma aba comum em nenhuma das duas navegações: no iOS 26 ela
    /// tem papel próprio no sistema (`role: .search`, que rende o gesto e a
    /// posição que a Apple padronizou) e no iOS 17–25 vira o botão redondo
    /// separado. Marcar isso aqui evita que alguém a alinhe com as outras
    /// "para ficar consistente" e perca o comportamento nativo.
    public var ehBusca: Bool { self == .buscar }

    /// As abas que aparecem lado a lado nas duas navegações, na mesma ordem.
    public static var principais: [AbaDoApp] {
        allCases.filter { !$0.ehBusca }
    }
}
