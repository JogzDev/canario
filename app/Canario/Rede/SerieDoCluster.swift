import Foundation

/// A série semanal do índice dos atributos da peça (A14).
///
/// **O que ela é, e o que ela não é.** O Figma pedia "Métricas da peça" com um
/// gráfico ao longo do tempo. Lido ao pé da letra, aquilo prometia acompanhar
/// *a peça do usuário* — o closet que a §34 exclui, e que o dado não sustenta:
/// a peça é do cliente, não está no painel, nenhuma marca que medimos vende
/// ela. Decisão do JP em 07/08: o gráfico é dos **atributos** dela. A tela fica
/// igual e a afirmação vira verdadeira.
///
/// **Por que cada ponto carrega `nAtributos`.** Semana em que só um dos três
/// atributos teve leitura não é comparável com semana em que os três tiveram, e
/// desenhar as duas com a mesma linha finge uma cobertura constante que não
/// existe. A regra 3 pede o caminho até a origem; aqui ele é quantos atributos
/// sustentaram cada ponto.
enum SerieDoCluster {

    struct Resposta: Decodable {
        let unidade: String?
        let categoriaUsada: String?
        let atributosPedidos: Int
        let atributosComPeso: Int
        let pontos: [Ponto]

        enum CodingKeys: String, CodingKey {
            case unidade, pontos
            case categoriaUsada = "categoria_usada"
            case atributosPedidos = "atributos_pedidos"
            case atributosComPeso = "atributos_com_peso"
        }
    }

    struct Ponto: Decodable, Identifiable, Hashable {
        let semana: String
        let indice: Double
        let nAtributos: Int
        /// Menor número de fontes entre os atributos que formaram o ponto.
        /// Um não invalida o índice, mas não sustenta estado direcional.
        let nPernasMin: Int?
        let nAtributosComEstado: Int?

        var id: String { semana }

        enum CodingKeys: String, CodingKey {
            case semana, indice
            case nAtributos = "n_atributos"
            case nPernasMin = "n_pernas_min"
            case nAtributosComEstado = "n_atributos_com_estado"
        }

        /// `Date` para o eixo do gráfico. `nil` numa semana malformada, que a
        /// tela descarta em vez de desenhar no lugar errado.
        var data: Date? {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .iso8601)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "America/Sao_Paulo")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: semana)
        }
    }

    /// Abaixo disto o gráfico não é desenhado: três pontos não são uma série, e
    /// uma linha entre eles sugere uma tendência que ninguém mediu.
    static let pontosMinimos = 8

    /// Ponto sustentado por menos atributos que isto é marcado na tela.
    ///
    /// A regra é relativa ao que foi pedido, e não um número fixo: numa peça de
    /// um atributo só, um atributo É a cobertura inteira.
    static func ralo(_ p: Ponto, de pedidos: Int) -> Bool {
        (pedidos > 1 && p.nAtributos < pedidos) || (p.nPernasMin ?? 2) < 2
    }

    /// Frase de rodapé com a cobertura real, sem enfeite.
    ///
    /// Existe porque a linha sozinha mente por omissão: ela parece uniforme
    /// mesmo quando metade dos pontos veio de um atributo só.
    static func ressalva(_ r: Resposta) -> String? {
        let ralos = r.pontos.filter { ralo($0, de: r.atributosPedidos) }.count
        let umaFonte = r.pontos.filter { ($0.nPernasMin ?? 2) < 2 }.count
        guard ralos > 0 else { return nil }
        if ralos == r.pontos.count {
            return "Every point has partial attribute or source coverage; "
                 + "the line shows the available index, not a directional state."
        }
        var causas = ["\(ralos) of \(r.pontos.count) points have partial coverage"]
        if umaFonte > 0 { causas.append("\(umaFonte) use only one source") }
        return causas.joined(separator: "; ") + ". They are marked on the chart."
    }

    /// Por que o gráfico não aparece, quando não aparece. Sempre uma frase que
    /// diz o que falta — nunca um espaço em branco.
    static func porQueNaoDesenha(_ r: Resposta?) -> String? {
        guard let r else {
            return "The history for these attributes could not be loaded."
        }
        if r.atributosComPeso == 0 {
            return "These attributes do not have panel weights yet, so a combined line cannot be drawn."
        }
        if r.pontos.count < pontosMinimos {
            return "There are \(r.pontos.count) week\(r.pontos.count == 1 ? "" : "s") with readings; "
                 + "at least \(pontosMinimos) are required to draw the chart. History grows with each collection."
        }
        return nil
    }
}
