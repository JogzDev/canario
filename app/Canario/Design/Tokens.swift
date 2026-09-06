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

        // MARK: - O substrato da peça (05/09)
        //
        // **Foto de roupa nunca é desenhada sobre cor.** A apresentação para a
        // diretoria bateu exatamente nisto: a peça aparecia sobre o `ceu`
        // (#BBE5ED) no herói do relatório, nas três prévias do importador, nos
        // cards do Closet e nas miniaturas da home. Um fundo cromático desloca
        // a cor percebida da peça na direção COMPLEMENTAR à do fundo — é
        // indução cromática, e num azul claro isso puxa a peça para o quente.
        // Ou seja: o app estava enviesando, contra si mesmo, justamente a
        // dimensão que o `CorDaPeca` mede e pré-marca no formulário.
        //
        // O valor não é gosto. A ISO 3664 (condições de visualização para
        // avaliação de cor) pede entorno **neutro e fosco**; para "avaliação
        // prática" o fator de luminância recomendado é ~60%, que em L* dá
        // 81,8 e em sRGB dá exatamente 203 — daí #CBCBCB. Neutro de verdade
        // (R = G = B), porque qualquer resíduo de matiz reintroduz a indução
        // que este token existe para eliminar.
        //
        // **É `fixa`, e nunca adaptativa.** Superfície de julgamento de cor
        // não pode mudar com o tema do sistema: se ela escurecesse junto com
        // o iPhone, a mesma peça leria diferente em dois aparelhos e a
        // sugestão do formulário deixaria de ser reproduzível. É a mesma razão
        // de `ceuFixo` e `noiteFixa` existirem, aplicada a um problema que
        // não é de contraste, e sim de medição.
        static let substratoDaPeca = fixa(203, 203, 203)

        /// Tinta legível sobre o substrato: o estado vazio ("sem foto") e o
        /// ícone de ausência vivem sobre ele. #4A4A4A dá 6,3:1 contra
        /// #CBCBCB, acima do 4,5:1 da §32, e continua neutro para não pintar
        /// de cor a moldura que existe para não ter cor.
        static let tintaSobreSubstrato = fixa(74, 74, 74)

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

// MARK: - Território

/// Em que metade do app a tela está.
///
/// A divisa é o **assunto**, não a tela: `armario` é a roupa da pessoa,
/// `mercado` é o painel. Uma tela declara o seu território uma vez, na raiz, e
/// todo componente compartilhado abaixo dela se adapta sozinho — que é o que
/// impede a alternativa cara, passar uma cor por parâmetro em cada chamada e
/// descobrir os esquecidos um por um, olhando.
enum Territorio {
    case armario
    case mercado
}

private struct ChaveDoTerritorio: EnvironmentKey {
    /// Claro por padrão: o app nasceu no armário, e uma tela que esquecer de
    /// declarar continua parecendo com ela mesma em vez de escurecer sozinha.
    static let defaultValue = Territorio.armario
}

extension EnvironmentValues {
    var territorio: Territorio {
        get { self[ChaveDoTerritorio.self] }
        set { self[ChaveDoTerritorio.self] = newValue }
    }
}

extension View {
    /// Declara o território e já pinta o fundo dele.
    ///
    /// As duas coisas juntas de propósito: declarar sem pintar deixaria os
    /// cartões escuros sobre um fundo branco, que é pior que não ter feito
    /// nada. `ignoresSafeArea` porque o fundo do mercado tem de alcançar a
    /// barra de status — metade escura com uma faixa branca em cima parece
    /// defeito, não desenho.
    ///
    /// **O fundo preenche a TELA, não a caixa do conteúdo (30/08).**
    ///
    /// Era `.background(...)`, e `background` toma o tamanho de QUEM ele
    /// modifica. Com a aba carregada isso não aparecia -- o conteúdo é uma
    /// `ScrollView`, que ocupa tudo. Mas no estado de carga o conteúdo é um
    /// `Carregando()` de duas linhas, e o fundo saía do tamanho dele: uma
    /// faixa de `noturno` no meio da tela e **preto puro** em cima e embaixo.
    ///
    /// O JP viu no aparelho e descreveu certo: *"elas ainda aparecem como se
    /// estivessem carregando na base de uma tela preta"*. Medido no quadro de
    /// 1m14 da gravação: (0,0,0) de 20% a 51% da altura e de novo de 59% a
    /// 91%, com a faixa de `noturno` só onde o spinner estava.
    ///
    /// A `ZStack` resolve porque `Color` se estica sozinha para o espaço
    /// disponível, e o conteúdo continua com o tamanho natural dele -- o que
    /// `.frame(maxHeight: .infinity)` estragaria em toda tela empurrada.
    func territorio(_ valor: Territorio) -> some View {
        ZStack {
            Tokens.Cor.fundoDo(valor).ignoresSafeArea()
            self
        }
        .environment(\.territorio, valor)
        // O ESQUEMA DA SUBÁRVORE, e não só a tinta.
        //
        // `foregroundStyle` abaixo cobre o texto solto, mas não alcança o que
        // resolve `Color(.label)` por dentro -- linha de `List`, rótulo de
        // `Picker`, título de barra. Enquanto só a Trends era escura isso não
        // aparecia, porque `Raiz` já punha a CENA em escuro pela aba visível.
        //
        // O Comparar mostrou o buraco: aberto fora daquela aba (o atalho de
        // teste `-CanarioUITestCompare`), o fundo vinha escuro e as linhas
        // vinham pretas, ilegíveis. O território sabe que é escuro; ele não
        // deveria depender de a aba certa estar na frente para dizer isso.
        //
        // Isto NÃO é `preferredColorScheme`, que se propaga até a cena e já
        // brigou com a raiz uma vez -- é o valor local, que só muda como as
        // cores de sistema resolvem daqui para dentro.
        .environment(\.colorScheme, valor == .mercado ? .dark : .light)
        // A tinta padrão da subárvore. Sem isto, todo `Text` fora de um
        // cartão herda `.label` -- que é escuro -- e some no fundo. Na
        // primeira montagem da Trends, "Supply moves" e os carimbos de data
        // ficaram invisíveis exatamente assim.
        .foregroundStyle(Tokens.Cor.tintaDo(valor))
        // O esquema do sistema NÃO é decidido aqui, e a tentativa de decidir
        // foi instrutiva: `preferredColorScheme` se propaga até a cena, e o da
        // raiz do app ganha do de dentro. A hora no topo continuava preta
        // sobre #0A0B1A. Quem manda nisso é `Raiz`, pela aba visível -- ver
        // `CanarioApp.swift`.
    }
}

extension Tokens.Cor {
    static func fundoDo(_ t: Territorio) -> Color {
        t == .mercado ? noturno : fundo
    }
    static func superficieDo(_ t: Territorio) -> Color {
        t == .mercado ? superficieNoturna : superficie
    }
    static func bordaDo(_ t: Territorio) -> Color {
        t == .mercado ? bordaNoturna : borda
    }
    static func tintaDo(_ t: Territorio) -> Color {
        t == .mercado ? tintaNoturna : tinta
    }
    static func tintaFracaDo(_ t: Territorio) -> Color {
        t == .mercado ? tintaFracaNoturna : tintaFraca
    }

    // MARK: - O menu lateral inverte as duas cores da marca (28/08)
    //
    // O menu pintava o painel com `azulMarca` e escrevia por cima com
    // `.white`. `azulMarca` é ADAPTATIVO -- clareia no escuro para continuar
    // legível sobre o céu escurecido --, então na Trends o painel virava
    // #96B4D7 com letra branca por cima. O JP viu a mistura e disse o que
    // faltava: *"a fonte do menu lateral tinha que ser aquele azul escuro pra
    // dar contraste"*.
    //
    // A correção não é escolher UM dos dois visuais, e sim inverter o par:
    // *"quando a tela é mais clara tipo o add, o menu lateral é o azul escuro
    // do app com a letra azul claro. e quando a tela for escura, o menu
    // lateral é o azul claro do app com a letra escura"*. São as mesmas duas
    // cores oficiais trocando de lugar, e as duas combinações estão medidas:
    // 6,6:1 no texto cheio e 5,3:1 / 4,7:1 no rodapé a 85%.
    //
    // Os valores aqui são FIXOS de propósito. Quem decide a inversão é o
    // território, não o tema do sistema; um par adaptativo desfaria a conta
    // acima exatamente como desfez a anterior.

    /// #BBE5ED literal, sem adaptação por tema.
    static let ceuFixo = fixa(187, 229, 237)
    /// #374A67 literal, sem adaptação por tema.
    static let azulMarcaFixo = fixa(55, 74, 103)
    /// #0E1116 literal. É o mesmo valor de `noite`, que é ADAPTATIVO e serve
    /// de tinta sobre o céu; aqui ele é fundo e não pode inverter com o tema.
    static let noiteFixa = fixa(14, 17, 22)

    // MARK: - As quatro pernas ganham cor (30/08)
    //
    // A Bianca desenhou o bloco de Sources com um tom por perna, e o JP
    // comprou a ideia pelo motivo certo: *"é um aplicativo de moda feminina,
    // acho que ela podia enfeitar mais... sair da mesmice pode ser bom"*. Ele
    // duvidou das cores dela, não da ideia, então os valores aqui são meus.
    //
    // **A REGRA QUE FAZ ISTO NÃO VIRAR CONFUSÃO: cor de perna é IDENTIDADE,
    // nunca ESTADO.** O app já comunica direção por cor -- os sete selos de
    // faixa, verde acima e laranja abaixo. Se um cartão de fonte fosse verde,
    // ele leria como "acima da faixa" antes de ler como "editorial". Por isso
    // nenhum destes quatro tons é da família dos selos: âmbar, rosa, azul da
    // marca e verde-água. Quem diz a direção dentro do cartão continua sendo a
    // seta mais o sinal, como manda a §32.
    //
    // Medidos: a tinta de cada perna sobre o próprio cartão dá de 7,6:1 a
    // 9,1:1, e o cartão se separa do `noturno` mais do que `superficieNoturna`
    // se separa (1,32-1,45:1 contra 1,12:1), que é o que faz eles saltarem no
    // desenho dela.

    /// Fundo e tinta de cada perna. `nil` para fonte desconhecida -- perna nova
    /// aparece com a superfície de sempre em vez de inventar um tom.
    static func corDaPerna(_ fonte: String) -> (fundo: Color, tinta: Color)? {
        switch fonte {
        case "busca":
            return (fixa(58, 43, 22), fixa(247, 202, 132))
        case "editorial_br":
            return (fixa(60, 30, 47), fixa(246, 176, 208))
        case "editorial_intl":
            return (fixa(29, 41, 68), fixa(156, 192, 230))
        case "varejo":
            return (fixa(18, 52, 51), fixa(144, 228, 218))
        default:
            return nil
        }
    }

    /// O painel do menu no território claro é #0E1116, e não `azulMarca`.
    ///
    /// Eu tinha lido "o azul escuro do app" como #374A67 e mudei só a letra.
    /// O JP corrigiu com o número na mão: *"eu já tinha dito que a cor nova
    /// desse menu deveria ser o azul escuro (0E1116), o que é estranho porque
    /// a cor da fonte você já tinha mudado, mas a do fundo não"*. Ele está
    /// certo sobre a incoerência -- a letra virou `ceuFixo` e o fundo ficou
    /// onde estava, então o par saiu pela metade.
    static func fundoDoMenu(_ t: Territorio) -> Color {
        t == .mercado ? ceuFixo : noiteFixa
    }
    static func tintaDoMenu(_ t: Territorio) -> Color {
        t == .mercado ? azulMarcaFixo : ceuFixo
    }
}

extension Tokens.Cor {
    /// O acento de cada território.
    ///
    /// No armário é o azul de ação do sistema, que já era. No mercado é o
    /// **céu da marca** — pedido do JP em 27/08, e ele tem razão pelo motivo
    /// certo: sobre `#0A0B1A` o `azulMarca` (#374A67) quase não se separa do
    /// fundo, e o azul de sistema puxa a tela para fora da identidade. O céu
    /// resolve as duas coisas ao mesmo tempo: contraste alto e a cor que a
    /// pessoa já associa ao app do outro lado da divisa.
    ///
    /// **`ceuFixo`, e não `ceu` (29/08).** `ceu` é adaptativo: no escuro ele
    /// vira #10262C, quase o próprio fundo. E o território de mercado roda com
    /// o sistema em escuro, então o acento "azul claro da marca" chegava à
    /// tela como um teal quase preto -- visível na primeira montagem da curva
    /// de tamanhos, onde as barras destacadas sumiram dentro do cartão.
    ///
    /// É o mesmo erro que o menu lateral tinha com `azulMarca`, e a mesma
    /// correção: cor de território não pergunta o tema ao sistema, porque
    /// quem já escolheu foi o território.
    static func acentoDo(_ t: Territorio) -> Color {
        t == .mercado ? ceuFixo : acao
    }
}

extension View {
    /// Fixa também a superfície que o UIKit anima entre duas telas de mercado.
    /// `territorio(.mercado)` já colore o conteúdo, mas um `NavigationLink`
    /// não herda o fundo da barra durante alguns frames do gesto de voltar. A
    /// barra padrão clara chegava a piscar no alto, sobretudo à direita, antes
    /// do destino reaparecer. Esta é a borda da transição, não só a aparência
    /// da tela já estável.
    func navegacaoDoMercado() -> some View {
        toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Tokens.Cor.noturno, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
