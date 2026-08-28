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

        // MARK: - O território escuro (27/08)
        //
        // O app passa a ter dois territórios, e a divisa é o ASSUNTO, não a
        // tela: **claro é a sua roupa, escuro é o mercado**. Add, Closet e o
        // painel de uma peça sua continuam claros; Trends, o relatório de um
        // termo e as listas de mercado ficam escuros.
        //
        // Isso saiu do Figma da Bianca, onde a divisão já estava feita sem
        // estar nomeada: todas as telas de mercado que ela desenhou são
        // escuras e todas as do armário são claras.
        //
        // **`#0A0B1A` é a terceira cor oficial da marca**, ao lado de `ceu`
        // (#BBE5ED) e `azulMarca` (#374A67) — e era a única das três que nunca
        // tinha entrado no código. Cuidado com o nome: `noite`, logo acima, é
        // outro quase-preto (#0E1116) e serve de TINTA sobre o céu. São coisas
        // diferentes e não devem ser trocadas uma pela outra.
        //
        // Os quatro tons derivados abaixo não são escolha de gosto: cada um é
        // uma mistura medida entre `noturno` e `azulMarca` (ou o branco frio da
        // tinta). É isso que faz o escuro parecer da mesma marca que o claro,
        // em vez de um cinza genérico de sistema.

        /// Fundo do território de mercado. A terceira cor oficial.
        static let noturno = fixa(10, 11, 26)
        /// Cartão sobre o fundo noturno: `noturno` 22% na direção do azul.
        static let superficieNoturna = fixa(20, 25, 43)
        /// Borda e divisor no escuro: 40% na mesma direção.
        static let bordaNoturna = fixa(28, 36, 57)
        /// Tinta sobre o escuro. Branco frio, não branco puro: puro vibra
        /// sobre fundo azulado e cansa em tela de leitura.
        static let tintaNoturna = fixa(234, 242, 245)
        /// Tinta de apoio no escuro, a 62% do caminho entre fundo e tinta.
        static let tintaFracaNoturna = fixa(149, 154, 162)

        /// Cor que NÃO se adapta ao tema do sistema.
        ///
        /// O território escuro é escuro por decisão de produto, e não porque o
        /// iPhone está no modo escuro. Se estes tons fossem adaptativos, a tela
        /// de mercado clarearia junto com o resto no modo claro — que é
        /// exatamente o contrário do que ela existe para fazer.
        static func fixa(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(red: r / 255, green: g / 255, blue: b / 255)
        }

        /// Uma cor por tema, resolvida pelo sistema no momento de desenhar --
        /// e não uma vez na inicialização. Isso é o que faz a tela responder a
        /// quem troca de tema com o app aberto.
        static func adaptativa(claro: (Double, Double, Double),
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
        /// Cartão grande de escolha -- a foto, o seletor. O raio maior é o que
        /// separa "superfície tocável" de "caixa de conteúdo" no desenho novo.
        static let cartaoGrande: CGFloat = 28
    }

    // MARK: - Sombra

    /// A sombra de cartão do idioma da Apple: difusa, deslocamento pequeno,
    /// opacidade baixa. Ela não desenha uma borda -- desenha a **distância**
    /// entre o cartão e o fundo, que é o que faz um retângulo parecer tocável
    /// em vez de pintado.
    ///
    /// O tom não é preto: puxa para o cinza frio do céu da marca, que foi o
    /// pedido do JP em 27/08 ("sombra meio acinzentada/gelo atrás"). Preto
    /// puro sobre fundo branco suja; cinza frio afasta.
    enum Sombra {
        static let cor = Color(red: 0.36, green: 0.47, blue: 0.53).opacity(0.20)
        static let raio: CGFloat = 14
        static let deslocamentoY: CGFloat = 6
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
        /// Título de um GRUPO de cartões, não de um cartão.
        ///
        /// "Result" fica dentro de um cartão e "By attribute" fica fora, porque
        /// o segundo encabeça vários cartões. Com a mesma fonte nos dois a
        /// diferença de posição lia como descuido -- foi relatado assim. Um
        /// rótulo pequeno, versalete e espaçado é o cabeçalho de grupo que o
        /// iOS usa em lista agrupada: o leitor reconhece o nível na hora.
        static let grupo = Font.caption.weight(.semibold)
        static let corpo = Font.body
        static let apoio = Font.subheadline
        static let miudo = Font.footnote
        /// Números que o usuário compara entre si: largura fixa evita o texto
        /// "pular" quando o valor muda.
        static let numero = Font.title3.monospacedDigit().weight(.semibold)
    }
}

extension View {
    /// Levanta um cartão do fundo. Uma linha só, para os cartões da mesma tela
    /// não divergirem em raio, cor e deslocamento -- que foi como a paleta
    /// acabou redigitada em literal na primeira aplicação do Figma.
    func sombraDeCartao() -> some View {
        shadow(color: Tokens.Sombra.cor, radius: Tokens.Sombra.raio,
               x: 0, y: Tokens.Sombra.deslocamentoY)
    }
}
