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

    /// O texto na tela — **e só isso**.
    ///
    /// Ele era também a chave que `TelaDoMenu` usava para escolher o destino:
    /// a navegação carregava a String "Settings" e a tela de destino fazia
    /// `switch nome { case "Settings": ... }`. Funcionou enquanto existia um
    /// idioma só, e teria virado defeito silencioso no primeiro toque em
    /// português — o `switch` cairia no `default` e todo item do menu abriria
    /// o Q&A. Nenhum teste pegaria: os dois lados liam o mesmo literal.
    ///
    /// Agora a identidade é o `case` (que não traduz) e o título é texto. As
    /// duas coisas deixaram de poder divergir porque deixaram de ser a mesma.
    public var titulo: String {
        switch self {
        case .favoritos:   return frase("Favorites")
        case .conta:       return frase("Account")
        case .ajustes:     return frase("Settings")
        case .termos:      return frase("Terms")
        case .privacidade: return frase("Privacy")
        case .perguntas:   return frase("Q&A")
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

    /// Encontra a entrada pela chave estável, não pelo texto exibido.
    ///
    /// Substitui `pelaTitulo(_:)`, que casava contra o rótulo traduzível e
    /// devolveria `nil` para todo mundo assim que a interface saísse do inglês.
    public static func pelaChave(_ chave: String) -> EntradaDoMenu? {
        EntradaDoMenu(rawValue: chave)
    }
}
