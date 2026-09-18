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
        /// A28: termos da mesma dimensão são alternativas (por exemplo,
        /// branco OU verde), sem contar duas vezes o mesmo tipo de evidência.
        let dimensoesPedidas: Int?
        let minimoEmComum: Int
        let minimoDimensoes: Int?
        let dimensaoRelaxada: String?
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

        /// A57: quando o painel que sustenta estas peças foi visto.
        ///
        /// A correção que fez a busca parar de confundir pausa de coleta com
        /// ausência de mercado tem duas metades. A primeira é do banco: a
        /// janela de frescor passou a ser ancorada no último dia observado de
        /// cada segmento, então uma coleta parada devolve o painel em vez de
        /// devolver vazio. A segunda é desta tela: sem a data, a correção
        /// apenas trocaria uma frase falsa ("não existe") por outra ("isto é
        /// de hoje").
        ///
        /// `var` com valor padrão, e não `let`, porque um app novo pode falar
        /// com um banco anterior à A57. Nesse caso as três chegam nulas e a
        /// tela volta a escrever a frase antiga, sem data -- que é o
        /// comportamento correto para um dado que ninguém mediu.
        var observadoEm: String? = nil
        var observadoMaisAntigoEm: String? = nil
        var diasDesdeAObservacao: Int? = nil

        enum CodingKeys: String, CodingKey {
            case nSimilares = "n_similares"
            case nMarcas = "n_marcas"
            case atributosPedidos = "atributos_pedidos"
            case dimensoesPedidas = "dimensoes_pedidas"
            case minimoEmComum = "minimo_em_comum"
            case minimoDimensoes = "minimo_dimensoes"
            case dimensaoRelaxada = "dimensao_relaxada"
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
            case observadoEm = "observado_em"
            case observadoMaisAntigoEm = "observado_mais_antigo_em"
            case diasDesdeAObservacao = "dias_desde_a_observacao"
        }
    }

    struct Peca: Decodable, Identifiable, Hashable {
        let id: Int
        let marca: String
        let papelDaMarca: String?
        let titulo: String?
        let url: String?
        /// URL no CDN da PRÓPRIA loja (A13). O card carrega direto de lá, por
        /// hotlink: a imagem nunca é copiada para o nosso servidor nem para o
        /// binário. Se a loja tirar do ar, o card cai no bloco de cor, que é o
        /// desenho do A6 e continua existindo.
        let imagem: String?
        let preco: Double?
        let precoDe: Double?
        let quedaPct: Double?
        let emComum: Int
        /// Quais atributos pedidos esta peça tem. Contagem responde "quanto";
        /// esta lista responde "o quê" — e é o quê que a pessoa enxerga na foto.
        /// Opcional porque uma versão do app pode falar com um banco anterior
        /// ao P14; nesse caso a diferença simplesmente não é mostrada.
        let termosEmComum: [String]?
        let grade: Grade?
        /// A57: o dia em que ESTA peça foi vista pela última vez.
        ///
        /// Não é desenhada no cartão de propósito -- data por peça, em oito
        /// cartões, é ruído que a revisão de UX já pediu para tirar. Ela é o
        /// caminho até a origem da frase do resumo (regra 3): o intervalo que
        /// a tela declara sai de `observado_mais_antigo_em` e `observado_em`,
        /// que são o mínimo e o máximo destas datas.
        var vistoEm: String? = nil

        enum CodingKeys: String, CodingKey {
            case id, marca, titulo, url, imagem, preco, grade
            case vistoEm = "visto_em"
            case papelDaMarca = "papel_da_marca"
            case precoDe = "preco_de"
            case quedaPct = "queda_pct"
            case emComum = "em_comum"
            case termosEmComum = "termos_em_comum"
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

    // MARK: A idade do que a resposta mostra (A57)

    /// Abaixo disto a resposta é do presente e dizer a data seria ruído.
    ///
    /// Um dia de folga porque a coleta roda de madrugada: às 9h da manhã o
    /// painel mais novo que existe é o de ontem, e chamar isso de "ontem"
    /// assusta sem motivo.
    static let diasParaSerAgora = 1

    /// A resposta descreve o mercado de agora, ou o de uma observação antiga?
    ///
    /// Sem `dias_desde_a_observacao` -- banco anterior à A57 --, responde que
    /// sim: é o comportamento que o app já tinha, e inventar uma ressalva
    /// sobre um dado que ninguém mediu seria pior do que não ter a ressalva.
    static func ehDeAgora(_ r: Resumo) -> Bool {
        guard let dias = r.diasDesdeAObservacao else { return true }
        return dias <= diasParaSerAgora
    }

    /// Quando o painel foi visto, para entrar DENTRO da frase do resultado.
    ///
    /// Não é uma frase separada de propósito. A ressalva em linha própria é
    /// fácil de pular, e a que a pessoa precisa ler é justamente esta -- com a
    /// coleta parada em 02/09, "encontrei 20 peças" e "havia 20 peças quinze
    /// dias atrás" são afirmações diferentes sobre o mesmo número.
    static func quandoFoiVisto(_ r: Resumo) -> String? {
        guard !ehDeAgora(r), let dias = r.diasDesdeAObservacao,
              let observado = r.observadoEm else { return nil }
        let intervalo: String
        if let maisAntigo = r.observadoMaisAntigoEm, maisAntigo != observado {
            intervalo = "between \(Formato.data(maisAntigo)) and \(Formato.data(observado))"
        } else {
            intervalo = "on \(Formato.data(observado))"
        }
        return "when the panel was last seen, \(intervalo) — "
             + "\(Formato.periodo(dias: dias)) ago"
    }

    // MARK: O parágrafo (§29.1)

    /// O template determinístico da §29, montado só com o que existe.
    ///
    /// A §29 dá o exemplo: *"No painel de {n_marcas} marcas, encontrei
    /// {n_similares} similares: {pct_preco_cheio}% a preço cheio e
    /// {pct_grade_quebrada}% com grade quebrando {formato}."*
    /// As mesmas frases da §29, mas em lista.
    ///
    /// A revisão de UX da 1.0 pediu menos texto corrido e mais bullet points, e
    /// aqui isso sai de graça: o parágrafo SEMPRE foi um array de frases
    /// pré-escritas -- é o que a §29 exige -- e só era juntado com espaço no
    /// último passo. Expor o array deixa a tela escolher entre parágrafo e lista
    /// **sem trocar uma palavra**, então a regra de "frases pré-escritas com
    /// slots preenchidos pelo motor" continua intacta.
    static func frasesDoResumo(_ r: Resumo, atributos: [Termo],
                               descricao: String? = nil) -> [String] {
        var frases: [String] = []

        let nomes = descricao
            ?? atributos.map(Traducao.rotuloExibido).joined(separator: " + ")
        if r.nSimilares == 0 {
            // A tela chama `similares_da_peca_amplo`, que SEMPRE tenta o
            // conjunto estrito e depois tenta de novo largando a dimensão
            // menos distintiva. Quando volta zero, as duas tentativas
            // falharam -- e não dizer isso deixa a pessoa achando que basta
            // desmarcar um atributo à mão para o painel responder.
            let tentouMais = (r.dimensoesPedidas ?? 0) > 1
                ? " I also tried a wider match, dropping the least distinctive dimension, and that found nothing either."
                : ""
            return ["I found no panel item with \(nomes).\(tentouMais) "
                  + "It may be an uncommon combination, "
                  + "or the panel may not cover it yet; the data cannot distinguish those cases."]
        }

        // Quando o motor afrouxou, as peças encontradas **não têm** todos os
        // atributos pedidos -- e esta frase as anunciava com a lista inteira,
        // afirmando o contrário do que os próprios cartões dizem logo abaixo
        // ("3 of 5 · no gray or solid"). Duas partes da mesma tela discordando
        // é a forma mais cara de mentir: a pessoa acredita na primeira.
        let marcas = "\(r.nMarcas) brand\(r.nMarcas == 1 ? "" : "s")"
        let pecas = "\(r.nSimilares) panel item\(r.nSimilares == 1 ? "" : "s")"
        // O tempo do verbo é o dado. "I found" é presente e vale quando a
        // coleta é de agora; com o painel parado há duas semanas, o que existe
        // é o passado -- "had", com a data junto.
        if let quando = quandoFoiVisto(r) {
            frases.append(afrouxou(r)
                ? "Across \(marcas), \(pecas) were close to \(nomes) \(quando); "
                + "none matched all of them."
                : "Across \(marcas), \(pecas) had \(nomes) \(quando).")
        } else if afrouxou(r) {
            frases.append("Across \(marcas), I found \(pecas) "
                        + "close to \(nomes) — none matches all of them.")
        } else {
            frases.append("Across \(marcas), I found \(pecas) with \(nomes).")
        }

        // A porcentagem só entra quando o conjunto a sustenta.
        if r.nSimilares >= minimoParaPorcentagem {
            if let cheio = r.pctPrecoCheio {
                frases.append("\(Leitura.numero(cheio, casas: 0))% remain at full price.")
            }
            if let quebrada = r.pctGradeQuebrada {
                var f = "\(Leitura.numero(quebrada, casas: 0))% have missing sizes"
                if let esgotada = r.pctEsgotada, esgotada >= 5 {
                    f += ", and \(Leitura.numero(esgotada, casas: 0))% have no size left"
                }
                frases.append(f + ".")
            }
        } else {
            frases.append("There are too few for percentages to be meaningful. Below \(minimoParaPorcentagem) matches, the items are shown without a summary statistic.")
        }

        if let mediana = r.precoMediana {
            frases.append("The median price is \(Formato.dinheiro(mediana)).")
        }
        return frases
    }

    /// A versão corrida das mesmas frases. Continua existindo para quem precisa
    /// de uma string só -- rótulo de acessibilidade, por exemplo, onde uma lista
    /// viraria pausas estranhas no VoiceOver.
    static func paragrafo(_ r: Resumo, atributos: [Termo],
                          descricao: String? = nil) -> String {
        frasesDoResumo(r, atributos: atributos, descricao: descricao)
            .joined(separator: " ")
    }

    /// §5 autoriza percentil de preço como substituto da previsão proibida:
    /// *"seu preço-alvo está no percentil 78 dos similares"*.
    static func leituraDoPreco(_ r: Resumo, alvo: Double?) -> String? {
        guard let alvo, let p = r.percentilDoAlvo, r.comPreco >= minimoParaPorcentagem
        else { return nil }
        let pct = Int(p.rounded())
        let posicao: String
        switch pct {
        case ..<25:  posicao = "below most of them"
        case 25..<45: posicao = "in the lower half"
        case 45..<55: posicao = "near the middle"
        case 55..<75: posicao = "in the upper half"
        default:      posicao = "above most of them"
        }
        return "\(Formato.dinheiro(alvo)) is at the \(pct)th percentile among priced matches — \(posicao). "
             + "This is a panel price position, not a judgment of your price; your costs and margin are not included."
    }

    /// Como o limiar de semelhança foi aplicado. Regra 3: o usuário precisa
    /// poder auditar o que "parecida" significou nesta tela.
    /// O motor precisou largar uma dimensão para achar alguma coisa.
    ///
    /// É a mesma conta que `criterio` faz para escolher a frase dele; ela vive
    /// aqui para as duas partes da tela nunca discordarem sobre se houve
    /// afrouxamento — que foi exatamente o que aconteceu até 27/08, com o
    /// critério dizendo "3 of 5" e o resultado dizendo "com todos os 7".
    static func afrouxou(_ r: Resumo) -> Bool {
        guard let dimensoes = r.dimensoesPedidas,
              let minimoDimensoes = r.minimoDimensoes else { return false }
        return minimoDimensoes < max(1, Int(ceil(0.7 * Double(dimensoes))))
    }

    static func criterio(_ r: Resumo) -> String {
        if let dimensoes = r.dimensoesPedidas,
           let minimoDimensoes = r.minimoDimensoes {
            let base = max(1, Int(ceil(0.7 * Double(dimensoes))))
            let alternativas = r.atributosPedidos > dimensoes
                ? " Selections within the same dimension are alternatives."
                : ""
            // Mesma conta de `afrouxou`, e é de propósito que ela apareça uma
            // vez só: as duas frases da tela têm de concordar sempre.
            if afrouxou(r) {
                let omitida = r.dimensaoRelaxada.map {
                    " The expanded set does not require \(Traducao.rotuloDaDimensao($0).lowercased())."
                } ?? ""
                let ancora = r.dimensaoRelaxada == "categoria"
                    ? "The recognizable print motif still matches; clothing category may differ."
                    : "Category still matches."
                return "No useful set reached the usual \(base)-of-\(dimensoes)-dimension match. "
                     + "Showing the closest available matches at \(minimoDimensoes) of \(dimensoes). \(ancora)"
                     + omitida
                     + alternativas
            }
            return "Matches cover at least \(minimoDimensoes) of \(dimensoes) selected dimensions; category always matches."
                 + alternativas
        }
        if r.minimoEmComum == r.atributosPedidos {
            return "All \(r.atributosPedidos) attributes matched."
        }
        if r.nComTodos > 0 {
            let n = r.nComTodos
            return "\(n) piece\(n == 1 ? "" : "s") match\(n == 1 ? "es" : "") "
                 + "all \(r.atributosPedidos) attributes; the rest, at least "
                 + "\(r.minimoEmComum)."
        }
        // Quando nada bate em tudo, a frase antiga imprimia literalmente
        // "0 match all of them" -- anunciar a ausencia, que e a forma mais
        // desanimadora de dizer a mesma coisa. Aqui ela diz o melhor que existe
        // e aponta para onde a diferenca esta explicada, peca a peca.
        return "Closest available: \(r.minimoEmComum) of your "
             + "\(r.atributosPedidos) attributes. Each card shows what differs."
    }

    /// Uma linha de desfecho por peça — o "e o desfecho delas" da §5.
    static func desfecho(_ p: Peca) -> String {
        var partes: [String] = []
        if let g = p.grade, g.degraus > 0 {
            if g.esgotada {
                partes.append("no size available")
            } else if g.quebrada {
                let faltam = g.faltando.prefix(3).joined(separator: ", ")
                partes.append("\(g.disponiveis) of \(g.degraus) sizes, missing \(faltam)")
            } else {
                partes.append("full size range, \(g.degraus) sizes")
            }
        }
        if let q = p.quedaPct {
            partes.append("marked down \(Leitura.numero(q, casas: 0))%")
        } else if p.preco != nil {
            partes.append("at full price")
        }
        return partes.isEmpty ? "no price or size data" : partes.joined(separator: " · ")
    }

    /// Produto explicitamente esgotado não é alternativa útil. Falta de grade
    /// continua visível, pois nil significa “não medido”, não “esgotado”.
    static func podeExibir(_ p: Peca) -> Bool {
        p.grade?.esgotada != true
    }

    /// Diz, por peça, o quanto ela casa **e no quê difere**.
    ///
    /// O bloco aceita casamento parcial: com quatro atributos marcados, três
    /// bastam. Isso é deliberado — exigir todos deixaria a lista quase vazia —
    /// mas até 19/08/2026 o app não dizia qual atributo tinha ficado de fora.
    /// Quem mandou uma camiseta listrada e viu uma peça lisa na lista concluiu,
    /// com razão, que o app tinha errado.
    ///
    /// Ele não errou: mostrou a terceira peça mais parecida que existe no
    /// painel. O defeito era não dizer em que ela difere, e isso é a regra 2
    /// aplicada aqui — não afirmar mais do que o dado sustenta.
    ///
    /// A contagem sozinha não resolve: "3 de 4" não conta se o que faltou foi a
    /// estampa ou o tecido, e é a estampa que a pessoa enxerga na foto.
    static func casamento(_ p: Peca, pedidos: [Termo]) -> String? {
        guard !pedidos.isEmpty else { return nil }
        let total = pedidos.count
        // Banco anterior ao P14 devolve a contagem sem a lista. Vale mostrar o
        // número: é menos do que o ideal, e ainda assim mais honesto que nada.
        guard let tem = p.termosEmComum else {
            return p.emComum >= total
                ? "All \(total) attributes"
                : "\(p.emComum) of \(total) attributes"
        }
        let conjunto = Set(tem)
        let faltam = pedidos.filter { !conjunto.contains($0.id) }
        guard !faltam.isEmpty else { return "All \(total) attributes" }
        let nomes = faltam.map { Traducao.rotuloExibido($0).lowercased() }
        return "\(total - faltam.count) of \(total) · no \(listar(nomes))"
    }

    /// "a", "a or b", "a, b or c" — o "or" importa: são atributos que a peça
    /// NÃO tem, e "and" leria como se ela tivesse os dois.
    private static func listar(_ itens: [String]) -> String {
        guard let ultimo = itens.last else { return "" }
        guard itens.count > 1 else { return ultimo }
        return itens.dropLast().joined(separator: ", ") + " or " + ultimo
    }
}
