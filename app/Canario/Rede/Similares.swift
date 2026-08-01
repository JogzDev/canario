import Foundation

/// Similares da peça (§29), e o parágrafo-resumo que se apoia neles.
///
/// ## Por que este arquivo é o coração do projeto
///
/// A §5 proíbe previsão de venda, score e veredito — e lista, no mesmo lugar, o
/// que o app entrega **no lugar disso**. O primeiro item é:
///
/// > "análogos descritivos (as 3 peças mais parecidas e o desfecho delas)"
///
/// Não é um bloco a mais. É a resposta que substitui a pergunta proibida.
/// Em vez de dizer se a peça vai vender, o app mostra o que aconteceu com as
/// peças parecidas que já estão no mercado — preço, remarcação, estado da
/// grade — e deixa a leitura com quem tem o custo e o prazo na mão.
///
/// ## O parágrafo é template fixo, e por quê
///
/// A §29 proíbe LLM na v1 e manda usar "frases pré-escritas com slots
/// preenchidos exclusivamente por valores computados pelo motor". Cada frase
/// aqui só existe se o número que a sustenta existir — nada é preenchido com
/// valor plausível quando falta dado (regra 2).
enum Similares {

    // MARK: O que vem do banco

    struct Resposta: Decodable {
        let resumo: Resumo?
        let pecas: [Peca]
    }

    struct Resumo: Decodable {
        let nSimilares: Int
        let nMarcas: Int
        let atributosPedidos: Int
        let minimoEmComum: Int
        let nComTodos: Int
        let comPreco: Int
        let pctPrecoCheio: Double?
        let pctGradeQuebrada: Double?
        let pctEsgotada: Double?
        let precoMin: Double?
        let precoMax: Double?
        let precoMediana: Double?
        let percentilDoAlvo: Double?
        let exibidos: Int

        enum CodingKeys: String, CodingKey {
            case nSimilares = "n_similares"
            case nMarcas = "n_marcas"
            case atributosPedidos = "atributos_pedidos"
            case minimoEmComum = "minimo_em_comum"
            case nComTodos = "n_com_todos"
            case comPreco = "com_preco"
            case pctPrecoCheio = "pct_preco_cheio"
            case pctGradeQuebrada = "pct_grade_quebrada"
            case pctEsgotada = "pct_esgotada"
            case precoMin = "preco_min"
            case precoMax = "preco_max"
            case precoMediana = "preco_mediana"
            case percentilDoAlvo = "percentil_do_alvo"
            case exibidos
        }
    }

    struct Peca: Decodable, Identifiable, Hashable {
        let id: Int
        let marca: String
        let papelDaMarca: String?
        let titulo: String?
        let url: String?
        let preco: Double?
        let precoDe: Double?
        let quedaPct: Double?
        let emComum: Int
        let grade: Grade?

        enum CodingKeys: String, CodingKey {
            case id, marca, titulo, url, preco, grade
            case papelDaMarca = "papel_da_marca"
            case precoDe = "preco_de"
            case quedaPct = "queda_pct"
            case emComum = "em_comum"
        }

        struct Grade: Decodable, Hashable {
            let degraus: Int
            let disponiveis: Int
            let faltando: [String]
            let quebrada: Bool
            let esgotada: Bool
        }
    }

    // MARK: §8 aplicada aos similares

    /// Abaixo disto o conjunto é pequeno demais para uma porcentagem significar
    /// alguma coisa. Com 4 similares, "25% a preço cheio" é uma peça.
    static let minimoParaPorcentagem = 12

    // MARK: O parágrafo (§29.1)

    /// O template determinístico da §29, montado só com o que existe.
    ///
    /// A §29 dá o exemplo: *"No painel de {n_marcas} marcas, encontrei
    /// {n_similares} similares: {pct_preco_cheio}% a preço cheio e
    /// {pct_grade_quebrada}% com grade quebrando {formato}."*
    static func paragrafo(_ r: Resumo, atributos: [Termo]) -> String {
        var frases: [String] = []

        let nomes = atributos.map(\.rotulo).joined(separator: " + ")
        if r.nSimilares == 0 {
            return "Não encontrei nenhuma peça no painel com \(nomes). "
                 + "Pode ser combinação rara, ou pode ser que o painel ainda não tenha alcançado — as duas coisas são possíveis e não sei distinguir."
        }

        frases.append("No painel de \(r.nMarcas) marca\(r.nMarcas == 1 ? "" : "s"), "
                    + "encontrei \(r.nSimilares) peça\(r.nSimilares == 1 ? "" : "s") com \(nomes).")

        // A porcentagem só entra quando o conjunto a sustenta.
        if r.nSimilares >= minimoParaPorcentagem {
            if let cheio = r.pctPrecoCheio {
                frases.append("\(Leitura.numero(cheio, casas: 0))% seguem a preço cheio.")
            }
            if let quebrada = r.pctGradeQuebrada {
                var f = "\(Leitura.numero(quebrada, casas: 0))% estão com a grade quebrada"
                if let esgotada = r.pctEsgotada, esgotada >= 5 {
                    f += ", e \(Leitura.numero(esgotada, casas: 0))% já sem nenhum tamanho"
                }
                frases.append(f + ".")
            }
        } else {
            frases.append("São poucas para porcentagem significar algo — abaixo de \(minimoParaPorcentagem) similares, prefiro mostrar as peças e não a estatística.")
        }

        if let mediana = r.precoMediana {
            frases.append("O preço do meio é \(Formato.dinheiro(mediana)).")
        }
        return frases.joined(separator: " ")
    }

    /// §5 autoriza percentil de preço como substituto da previsão proibida:
    /// *"seu preço-alvo está no percentil 78 dos similares"*.
    static func leituraDoPreco(_ r: Resumo, alvo: Double?) -> String? {
        guard let alvo, let p = r.percentilDoAlvo, r.comPreco >= minimoParaPorcentagem
        else { return nil }
        let pct = Int(p.rounded())
        let posicao: String
        switch pct {
        case ..<25:  posicao = "abaixo da maior parte deles"
        case 25..<45: posicao = "na metade de baixo"
        case 45..<55: posicao = "bem no meio"
        case 55..<75: posicao = "na metade de cima"
        default:      posicao = "acima da maior parte deles"
        }
        return "\(Formato.dinheiro(alvo)) fica no percentil \(pct) dos similares com preço — \(posicao). "
             + "É posição de preço no painel, não julgamento do seu preço: margem e custo são seus."
    }

    /// Como o limiar de semelhança foi aplicado. Regra 3: o usuário precisa
    /// poder auditar o que "parecida" significou nesta tela.
    static func criterio(_ r: Resumo) -> String {
        if r.minimoEmComum == r.atributosPedidos {
            return "Peças que têm os \(r.atributosPedidos) atributos que você marcou."
        }
        return "Peças com pelo menos \(r.minimoEmComum) dos \(r.atributosPedidos) atributos marcados; "
             + "\(r.nComTodos) tem\(r.nComTodos == 1 ? "" : "êm") todos."
    }

    /// Uma linha de desfecho por peça — o "e o desfecho delas" da §5.
    static func desfecho(_ p: Peca) -> String {
        var partes: [String] = []
        if let g = p.grade, g.degraus > 0 {
            if g.esgotada {
                partes.append("sem nenhum tamanho disponível")
            } else if g.quebrada {
                let faltam = g.faltando.prefix(3).joined(separator: ", ")
                partes.append("\(g.disponiveis) de \(g.degraus) tamanhos, faltando \(faltam)")
            } else {
                partes.append("grade cheia, \(g.degraus) tamanhos")
            }
        }
        if let q = p.quedaPct {
            partes.append("remarcada \(Leitura.numero(q, casas: 0))%")
        } else if p.preco != nil {
            partes.append("a preço cheio")
        }
        return partes.isEmpty ? "sem dado de preço nem de grade" : partes.joined(separator: " · ")
    }
}
