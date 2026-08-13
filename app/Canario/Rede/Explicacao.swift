import Foundation

/// Traduz o índice e o estado para o que o usuário precisa saber antes de
/// decidir se acredita neles.
///
/// **Por que existe.** Em 31/07 o JP olhou o cartão "Preto +1,15 · Pico" e
/// perguntou: "1,15 o quê? Paçoquitas?" — e, logo depois, "por que isso é
/// considerado pico? Não é pra mim que você tem que explicar, é pro usuário".
///
/// As duas perguntas apontam o mesmo defeito. A tela mostrava um número sem
/// unidade e um rótulo sem regra, e as duas coisas quebram a regra 3 (todo
/// número carrega o caminho até a origem) e a regra 6 (dizer o que não se sabe).
/// Um comprador que não sabe o que é "pico" não sabe se compra ou se espera.
///
/// Está fora da tela porque é texto com decisão dentro, e por isso é testado:
/// a explicação precisa continuar batendo com a regra que o Postgres aplica
/// em `computar_indice()`. Se um dos dois mudar sem o outro, o teste quebra.
enum Explicacao {

    // MARK: Unidade

    /// O que a perna conta, em português.
    static func unidade(daFonte fonte: String) -> String {
        switch fonte {
        case "editorial_br", "editorial_intl":
            return "matérias publicadas que citaram o termo"
        case "busca":
            return "índice de interesse do Google Trends (0 a 100)"
        case "lyst_indice":
            return "posição no índice da Lyst"
        case "varejo":
            return "% das peças do painel que têm este atributo"
        case "lyst":
            return "posição no índice da Lyst"
        default:
            return fonte
        }
    }

    /// A unidade do índice em si. É a resposta literal ao "1,15 o quê?".
    static let unidadeDoIndice =
        "distância em relação ao comportamento normal das 12 semanas anteriores"

    /// O valor compacto usado em comparação. A unidade/escala vem na linha de
    /// apoio imediatamente abaixo, para não transformar jargão no título.
    static func numeroComUnidade(_ indice: Double?) -> String {
        guard let indice else { return "sem índice" }
        let n = Leitura.numero(indice, casas: 2, sinal: true)
        return "\(n)"
    }

    // MARK: Por que este estado

    /// A regra que produziu o estado, dita para quem vai decidir compra.
    ///
    /// Espelha `computar_indice()` linha a linha. A ordem importa: o `pico` é
    /// testado antes de "em alta" no Postgres, e aqui também.
    static func porQue(estado: String?, indice: IndiceSemanal, series: [PontoSerie]) -> String {
        guard let estado else {
            return "Ainda não há duas fontes concordando para afirmar uma direção: esta atualização tem \(indice.nPernas ?? 0)."
        }
        let editorial = series.first { $0.fonte.hasPrefix("editorial") && $0.z != nil }
        let acima = indice.meta?.pernasAcimaDe1 ?? 0
        let abaixo = indice.meta?.pernasAbaixoDe1 ?? 0

        switch estado {
        case "pico":
            let intensidade = editorial?.z.map(Leitura.emPalavras) ?? "muito acima do normal"
            let referencia = editorial?.z.map {
                " (\(Leitura.numero($0, casas: 1)) na escala estatística)"
            } ?? ""
            return "A atenção da imprensa ficou \(intensidade)\(referencia) numa semana, mas nenhuma outra fonte acompanhou. "
                 + "Por enquanto é um destaque editorial isolado, não uma tendência confirmada."
        case "em alta":
            return "Duas semanas seguidas acima do normal, com \(acima) fontes concordando. "
                 + "Uma semana isolada não conta: o limiar existe para ruído de uma semana não virar notícia."
        case "em queda":
            return "Duas semanas seguidas abaixo do normal, com \(abaixo) fontes concordando. "
                 + "Vale a mesma trava da alta: uma semana fraca sozinha não vira queda."
        case "estavel":
            return "Dentro da faixa normal deste atributo nas duas últimas semanas. Estável é resultado medido, não falta de dado."
        default:
            return estado
        }
    }

    // MARK: De onde veio

    /// Uma linha por perna, com o que ela contou e quem publicou.
    ///
    /// É o que faltava para a tela parar de repetir "baseado em: editorial BR +
    /// editorial internacional" em todo cartão.
    static func origens(_ series: [PontoSerie]) -> [String] {
        series
            .filter { $0.z != nil || $0.fonte == "varejo" }
            .sorted { $0.fonte < $1.fonte }
            .map { p in
                var linha = "\(Perna.rotulo(p.fonte)): "
                switch p.fonte {
                case "varejo":
                    let v = p.valorBruto.map { Leitura.numero($0, casas: 1) } ?? "—"
                    let n = p.nAmostra.map { "\($0) peças do painel" } ?? "amostra não registrada"
                    linha += "\(v)% do sortimento (\(n))"
                case let f where f.hasPrefix("editorial"):
                    // Só a perna editorial trabalha em janela de 4 semanas
                    // (§18). Dizer "em 4 semanas" para a busca era colar a
                    // janela de uma perna no número de outra.
                    let n = p.nAmostra.map(String.init) ?? "—"
                    linha += "\(n) \(unidade(daFonte: p.fonte)) em 4 semanas"
                    if let crua = p.meta?.contagemSemanaCrua {
                        linha += ", \(crua) nesta semana"
                    }
                default:
                    let v = p.valorBruto.map { Leitura.numero($0, casas: 0) } ?? "—"
                    linha += "\(v) de 100 no \(unidade(daFonte: p.fonte).replacingOccurrences(of: "índice de interesse do ", with: ""))"
                }
                if let quem = p.meta?.veiculosEmTexto {
                    linha += " — \(quem)"
                }
                return linha
            }
    }

    /// As manchetes que o robô leu. Nada de resumo nem de citação longa: só
    /// título e veículo, que é o que a §18 permite guardar.
    static func manchetes(_ series: [PontoSerie], limite: Int = 3) -> [PontoSerie.Meta.Exemplo] {
        var vistos = Set<String>()
        return series
            .flatMap { $0.meta?.exemplos ?? [] }
            .filter { vistos.insert($0.titulo).inserted }
            .prefix(limite)
            .map { $0 }
    }
}
