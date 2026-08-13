import SwiftUI

/// Tokens de aparência do Canário.
///
/// **Este é o único arquivo que a fase de design precisa tocar.** Nenhuma tela
/// declara cor, espaçamento ou tamanho de fonte diretamente: tudo vem daqui.
/// Quando o Figma ficar pronto, trocar os valores deste arquivo remodela o app
/// inteiro sem mexer em lógica nem em layout.
///
/// A18 fixou a primeira paleta da Bianca/Fadul. As telas legadas ainda usam os
/// tons semânticos do sistema; a raiz nova usa os três tokens de marca abaixo.
enum Tokens {

    // MARK: - Cor

    enum Cor {
        /// Paleta aprovada em 12/08/2026.
        static let ceu = Color(red: 187 / 255, green: 229 / 255, blue: 237 / 255)
        static let noite = Color(red: 14 / 255, green: 17 / 255, blue: 22 / 255)
        static let azulMarca = Color(red: 55 / 255, green: 74 / 255, blue: 103 / 255)
        /// Azul de ação com contraste suficiente tanto no fundo claro quanto
        /// no escuro. `azulMarca` é identidade sobre o céu da Home; usá-lo
        /// como link em cards pretos tornava texto e ícone ilegíveis.
        static let acao = Color.accentColor
        /// Fundo da tela.
        static let fundo = Color(.systemBackground)
        /// Fundo de cartão, um degrau acima do fundo.
        static let superficie = Color(.secondarySystemBackground)
        /// Texto principal.
        static let tinta = Color(.label)
        /// Texto de apoio: legendas, insumos, datas de coleta.
        static let tintaFraca = Color(.secondaryLabel)
        /// Linha divisória.
        static let borda = Color(.separator)

        // Estado. §32 é explícita: estado nunca é comunicado só por cor —
        // sempre acompanha ícone ou texto. Estas cores são reforço, não sinal.
        static let alta = Color.green
        static let queda = Color.red
        static let pico = Color.orange
        static let estavel = Color(.secondaryLabel)
        /// Sem cobertura para afirmar. Cinza de propósito: silêncio, não alarme.
        static let semDado = Color(.tertiaryLabel)
    }

    // MARK: - Espaçamento

    enum Espaco {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let g: CGFloat = 24
        static let xg: CGFloat = 32
    }

    // MARK: - Raio de canto

    enum Raio {
        static let cartao: CGFloat = 12
        static let etiqueta: CGFloat = 6
    }

    // MARK: - Tipografia
    //
    // Tudo via estilos do sistema, nunca tamanho fixo: é o que faz o Dynamic
    // Type funcionar, que a §32 exige.

    enum Fonte {
        // `Font.system` já é San Francisco nas plataformas Apple. Manter os
        // estilos sem nomear uma fonte empacotada preserva Dynamic Type e usa
        // SF Pro com o peso semântico de cada nível.
        static let titulo = Font.title2.weight(.semibold)
        static let secao = Font.headline
        static let corpo = Font.body
        static let apoio = Font.subheadline
        static let miudo = Font.footnote
        /// Números que o usuário compara entre si: largura fixa evita o texto
        /// "pular" quando o valor muda.
        static let numero = Font.title3.monospacedDigit().weight(.semibold)
    }
}
