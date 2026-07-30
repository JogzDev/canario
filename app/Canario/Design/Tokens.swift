import SwiftUI

/// Tokens de aparência do Canário.
///
/// **Este é o único arquivo que a fase de design precisa tocar.** Nenhuma tela
/// declara cor, espaçamento ou tamanho de fonte diretamente: tudo vem daqui.
/// Quando o Figma ficar pronto, trocar os valores deste arquivo remodela o app
/// inteiro sem mexer em lógica nem em layout.
///
/// A paleta de agora é deliberadamente neutra — preto, branco e cinza para
/// estrutura, verde e vermelho apenas para estado. Não é escolha estética; é
/// para o app poder ser testado sem fingir um design que ainda não existe.
enum Tokens {

    // MARK: - Cor

    enum Cor {
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
