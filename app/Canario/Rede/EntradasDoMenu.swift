import Foundation

/// As entradas do menu lateral, separadas pelo que a pessoa faz nelas.
///
/// POR QUE ISTO EXISTE
/// ===================
///
/// O menu listava seis entradas com exatamente o mesmo peso: 29 pt, 104 pt de
/// altura, uma embaixo da outra. Na revisão de UX da 1.0, a mentora apontou que
/// isso mistura duas coisas que não são a mesma:
///
/// * **Favorites, Account e Settings** existem para a pessoa *fazer* algo —
///   abrir uma peça salva, mexer num ajuste.
/// * **Terms, Privacy e Q&A** existem para ela *ler*, quase sempre uma vez na
///   vida, e frequentemente nunca.
///
/// Dar a mesma altura de toque às duas famílias faz o texto jurídico competir
/// com a ação, e é metade da tela gasta com o que quase ninguém abre. A anotação
/// dela foi direta: "muito secundário, não tem por que dar espaço".
///
/// A separação vive aqui, e não dentro da `View`, pelo mesmo motivo de
/// `AbaDoApp`: sem SwiftUI o arquivo entra no pacote `CanarioLogica` e é
/// conferido a cada commit, sem simulador. Uma entrada nova nasce obrigada a
/// declarar a que família pertence — não dá para acrescentar no fim da lista e
/// deixar a hierarquia se desfazer sozinha.
public enum EntradaDoMenu: String, CaseIterable, Sendable {
    case favoritos
    case conta
    case ajustes
    case termos
    case privacidade
    case perguntas

    /// O que a pessoa faz aqui. É esta distinção que a tela desenha.
    public enum Familia: Sendable {
        /// Leva a uma ação: abrir, escolher, mudar.
        case acao
        /// Leva a um texto. Necessário, raramente aberto, nunca urgente.
        case leitura
    }

    public var familia: Familia {
        switch self {
        case .favoritos, .conta, .ajustes: return .acao
        case .termos, .privacidade, .perguntas: return .leitura
        }
    }

    /// O texto na tela. Continua sendo a chave que `TelaDoMenu` usa para
    /// escolher o destino, então mudar aqui muda os dois lados de uma vez.
    public var titulo: String {
        switch self {
        case .favoritos:   return "Favorites"
        case .conta:       return "Account"
        case .ajustes:     return "Settings"
        case .termos:      return "Terms"
        case .privacidade: return "Privacy"
        case .perguntas:   return "Q&A"
        }
    }

    /// As entradas grandes, na ordem em que aparecem.
    public static var acoes: [EntradaDoMenu] {
        allCases.filter { $0.familia == .acao }
    }

    /// As entradas de leitura, que a tela agrupa pequenas no rodapé.
    public static var leituras: [EntradaDoMenu] {
        allCases.filter { $0.familia == .leitura }
    }

    /// Encontra a entrada pelo título exibido. Existe porque a navegação
    /// carrega o título como identificador; devolve `nil` para nome
    /// desconhecido em vez de escolher um destino errado.
    public static func pelaTitulo(_ titulo: String) -> EntradaDoMenu? {
        allCases.first { $0.titulo == titulo }
    }
}
