import Foundation

/// O ícone de cada termo da taxonomia, resolvido fora do SwiftUI.
///
/// Mora aqui, e não dentro da View, por dois motivos concretos:
///
/// 1. **Nome errado de SF Symbol não quebra compilação.** `Image(systemName:)`
///    com um nome inexistente desenha um retângulo vazio e segue em frente.
///    Fora da View, um teste consegue perguntar ao catálogo do sistema se cada
///    nome existe — que é a única forma de descobrir o erro antes de alguém
///    abrir a tela.
/// 2. **Termo novo nasce sem ícone.** A taxonomia cresce (couro entrou assim,
///    e os motivos de estampa também), e um portão consegue exigir que todo
///    termo aprovado do CSV apareça neste arquivo.
///
/// A cor é o único caso sem ícone: um círculo com a própria cor diz mais do
/// que qualquer símbolo diria, e a amostra já existe em `CorDaPeca`.
public enum IconeDaTaxonomia: Equatable, Sendable {

    /// Um símbolo do SF Symbols, pelo nome exato do catálogo.
    case sistema(String)

    /// Um glifo desenhado por nós.
    ///
    /// O SF Symbols tem `tshirt`, `jacket`, `coat` e `hanger` — e para de aí.
    /// Não existe calça, saia, vestido, macacão nem camisa de colarinho. As
    /// alternativas seriam pedir emprestado um símbolo de outro assunto
    /// (`triangle` para saia) ou usar a família `figure.*`, que desenha uma
    /// **pessoa** vestindo a peça e destoa de uma grade onde todo o resto é a
    /// peça sozinha. Desenhar é o que mantém a grade coerente.
    case desenhado(Glifo)

    /// Cor não usa ícone: usa a própria cor.
    case amostraDeCor

    /// Os glifos que desenhamos, no mesmo peso de traço do SF Symbols.
    public enum Glifo: String, CaseIterable, Sendable {
        case camisa, vestido, saia, calca, short, macacao
        case jeans, couro, malha
        case comprimentoCurto, comprimentoMidi, comprimentoLongo
        case silhuetaFlare, silhuetaReta
        case cinturaAlta, cinturaMedia, cinturaBaixa
        case tomate, cereja, morango, banana, abacaxi, melancia
    }

    /// O ícone de um termo, ou `nil` se ele ainda não tem um.
    ///
    /// Devolver `nil` em vez de um símbolo genérico é deliberado: a tela
    /// precisa poder mostrar o termo mesmo sem ícone (um termo novo continua
    /// selecionável), e o portão precisa poder acusar a falta.
    public static func para(id: String) -> IconeDaTaxonomia? {
        mapa[Traducao.idsCanonicos([id]).first ?? id]
    }

    private static let mapa: [String: IconeDaTaxonomia] = [
        // MARK: Categoria
        // Os três que o SF Symbols cobre bem ficam com ele: peça pela peça,
        // no mesmo peso do resto do sistema.
        "blusa_top": .sistema("tshirt"),
        "casaco_jaqueta": .sistema("jacket"),
        // Camisa é `tshirt` com colarinho e botões. Usar `tshirt` nos dois
        // deixaria duas categorias com o mesmo desenho na mesma grade.
        "camisa": .desenhado(.camisa),
        "vestido": .desenhado(.vestido),
        "saia": .desenhado(.saia),
        "calca": .desenhado(.calca),
        "short": .desenhado(.short),
        "macacao": .desenhado(.macacao),

        // MARK: Estampa
        // Aqui o SF Symbols acerta quase tudo, e o desenho do Figma já usava
        // exatamente estes: folha para floral, pata para animal print.
        "liso": .sistema("square"),
        "listra": .sistema("line.3.horizontal"),
        "floral": .sistema("leaf"),
        // `checkerboard.rectangle` é preenchido e, ao lado de Solid, Stripes e
        // Floral, que são contornos, ele vira o único bloco preto da
        // fileira. A grade tem que ter um peso só.
        "xadrez": .sistema("square.grid.3x3"),
        "geometrica": .sistema("circle.hexagongrid"),
        "animal_print": .sistema("pawprint"),
        // Estampa conversacional é a que "conta" alguma coisa — objeto, fruta,
        // bicho. O balão é a metáfora do próprio nome.
        "conversacional": .sistema("text.bubble"),

        // MARK: Motivo de estampa
        // Fruta não existe no SF Symbols, e substituir por um símbolo genérico
        // apagaria justamente o que distingue um motivo do outro.
        "tomate_print": .desenhado(.tomate),
        "cereja_print": .desenhado(.cereja),
        "morango_print": .desenhado(.morango),
        "banana_print": .desenhado(.banana),
        "abacaxi_print": .desenhado(.abacaxi),
        "melancia_print": .desenhado(.melancia),

        // MARK: Estética
        "romantico": .sistema("heart"),
        // Cabide, e não um quadrado preenchido: além de o quadrado cheio ser o
        // desenho mais pesado da tela inteira, básico é a peça que fica
        // pendurada esperando combinar com o resto.
        "basico": .sistema("hanger"),
        "boho_artesanal": .sistema("hand.raised"),
        // Régua, e não tesoura: alfaiataria é medida. A tesoura fica livre e
        // não compete com nenhum tecido.
        "alfaiataria": .sistema("ruler"),
        "festa_brilho": .sistema("sparkles"),

        // MARK: Tecido
        // `camera.macro` desenha uma tulipa, e tulipa já é floral duas seções
        // acima. Nuvem diz a propriedade que interessa no algodão: macio.
        "algodao": .sistema("cloud"),
        "linho": .sistema("wind"),
        "viscose_fluido": .sistema("water.waves"),
        "jeans": .desenhado(.jeans),
        "couro": .desenhado(.couro),
        "malha": .desenhado(.malha),

        // MARK: Comprimento, silhueta e cintura
        // São proporções, não objetos. Cada um desenha a MESMA silhueta com a
        // marca em altura diferente, que é o que a pessoa está comparando.
        "curto": .desenhado(.comprimentoCurto),
        "midi": .desenhado(.comprimentoMidi),
        "longo": .desenhado(.comprimentoLongo),
        "flare": .desenhado(.silhuetaFlare),
        "reta_wide": .desenhado(.silhuetaReta),
        "cintura_alta": .desenhado(.cinturaAlta),
        "cintura_media": .desenhado(.cinturaMedia),
        "cintura_baixa": .desenhado(.cinturaBaixa),

        // MARK: Cor
        "preto": .amostraDeCor, "branco_cru": .amostraDeCor,
        "cinza": .amostraDeCor, "azul": .amostraDeCor,
        "verde": .amostraDeCor, "lilas_roxo": .amostraDeCor,
        "vermelho_rosa": .amostraDeCor, "amarelo_laranja": .amostraDeCor,
        "terrosos": .amostraDeCor, "outras_cores": .amostraDeCor,
    ]

    /// Todos os nomes de SF Symbol citados aqui, para o teste conferir contra
    /// o catálogo do sistema.
    public static var simbolosDoSistema: [String] {
        mapa.values.compactMap {
            if case .sistema(let nome) = $0 { return nome }
            return nil
        }
    }

    /// Todos os ids mapeados, para o portão conferir contra a taxonomia.
    public static var idsMapeados: Set<String> { Set(mapa.keys) }
}
