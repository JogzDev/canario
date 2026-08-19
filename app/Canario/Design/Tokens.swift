import SwiftUI
import UIKit

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
        // PALETA DA MARCA -- aprovada em 12/08/2026, e adaptativa desde 19/08.
        //
        // As três nasceram como cores FIXAS, e por isso as telas Add e Closet
        // ignoravam o modo escuro: elas pintam o fundo com `ceu`, que nunca
        // escurecia. Quem usa o iPhone no escuro abria o app e levava um fundo
        // azul claro na cara. Os outros tokens daqui já se adaptavam, porque
        // vêm do sistema (`systemBackground`, `label`); só a marca não.
        //
        // A correção NÃO troca a paleta aprovada: os valores do modo claro são
        // os mesmos de 12/08, byte a byte. O que existe agora é um segundo
        // valor para o escuro, escolhido no MESMO matiz -- escurecer mantendo
        // a identidade, em vez de cair no cinza do sistema e a marca sumir.
        //
        // Se a Bianca e o Fadul quiserem outros tons de escuro, é aqui e só
        // aqui que se mexe.

        /// Céu da marca: fundo das telas Add e Closet.
        static let ceu = adaptativa(claro: (187, 229, 237), escuro: (16, 38, 44))
        /// Tinta sobre o céu. Precisa inverter junto com ele, ou o texto some.
        static let noite = adaptativa(claro: (14, 17, 22), escuro: (232, 240, 242))
        /// Azul de identidade sobre o céu; clareia no escuro para manter
        /// contraste de leitura sobre o fundo escurecido.
        static let azulMarca = adaptativa(claro: (55, 74, 103),
                                          escuro: (150, 180, 215))

        /// Uma cor por tema, resolvida pelo sistema no momento de desenhar --
        /// e não uma vez na inicialização. Isso é o que faz a tela responder a
        /// quem troca de tema com o app aberto.
        private static func adaptativa(claro: (Double, Double, Double),
                                       escuro: (Double, Double, Double)) -> Color {
            Color(UIColor { tracos in
                let (r, g, b) = tracos.userInterfaceStyle == .dark ? escuro : claro
                return UIColor(red: r / 255, green: g / 255, blue: b / 255,
                               alpha: 1)
            })
        }
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
