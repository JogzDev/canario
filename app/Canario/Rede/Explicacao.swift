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

    /// Última barreira de precisão para a vitrine editorial do app.
    ///
    /// A origem já filtra título + resumo. Linhas coletadas antes dessa correção
    /// ainda podem existir no cache/banco por alguns dias; o radar só mostra a
    /// manchete quando o próprio título declara intenção de moda. Isto não
    /// altera série nem estado — apenas impede que "camisa 7" e notícias de
    /// gravidez sejam promovidas como conteúdo de moda na interface.
    static func mancheteDeclaraModa(_ titulo: String) -> Bool {
        let normalizada = titulo.folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let recusadas = [
            #"\bcamisa\s+(?:\d+|do time|da empresa|da campanha)\b"#,
            #"\bvestir?\s+a\s+camisa\s+(?:da|do)\b"#,
        ]
        if recusadas.contains(where: {
            normalizada.range(of: $0, options: .regularExpression) != nil
        }) { return false }
        let marcadores = [
            "moda", "fashion", "look", "looks", "outfit", "style", "styling",
            "trend", "tendencia", "colecao", "collection", "runway", "passarela",
            "streetwear", "street style", "wardrobe", "closet", "fashion week",
            "modelagem", "como usar", "jeitos de usar", "wear", "wearing",
            "chic", "elegant", "silhouette", "alfaiataria", "fw26", "ss27",
        ]
        if marcadores.contains(where: { normalizada.contains($0) }) { return true }
        let pecasInequivocas = [
            "vestido", "vestidos", "dress", "dresses", "gown", "saia",
            "saias", "skirt", "calca", "calcas", "pants", "trousers",
            "short", "shorts", "bermuda", "blusa", "blouse", "camiseta",
            "t-shirt", "camisa", "shirt", "jaqueta", "jacket", "casaco",
            "coat", "blazer", "macacao", "jumpsuit", "denim", "tweed",
        ]
        return pecasInequivocas.contains { peca in
            let padrao = #"\b"# + NSRegularExpression.escapedPattern(for: peca) + #"\b"#
            return normalizada.range(of: padrao, options: .regularExpression) != nil
        }
    }

    // MARK: Unidade

    /// O que a perna conta, em português.
    static func unidade(daFonte fonte: String) -> String {
        switch fonte {
        case "editorial_br", "editorial_intl":
            return frase("published articles that mentioned the term")
        case "busca":
            return frase("Google Trends search-interest index (0 to 100)")
        case "lyst_indice":
            return frase("position in the Lyst Index")
        case "varejo":
            return frase("% of panel items with this attribute")
        case "lyst":
            return frase("position in the Lyst Index")
        default:
            return fonte
        }
    }

    /// A mesma unidade, sem o nome da escala — para a linha que já disse
    /// "x de 100" e só precisa dizer de qual índice.
    ///
    /// Existia como `unidade(daFonte:).replacingOccurrences(of: "search-interest
    /// index ", with: "")`: recortar um pedaço do texto pelo próprio texto. Isso
    /// funciona em exatamente um idioma. Em português a frase não contém aquele
    /// trecho, o `replacingOccurrences` não casa nada e a linha sairia com a
    /// unidade inteira duplicada dentro dela. É o tipo de defeito que só
    /// aparece depois de traduzir, e por isso ele foi arrancado pela raiz em
    /// vez de ganhar um segundo `replacingOccurrences` para o português.
    static func unidadeCurta(daFonte fonte: String) -> String {
        switch fonte {
        case "busca":        return frase("Google Trends index (0 to 100)")
        case "lyst_indice",
             "lyst":         return frase("Lyst Index")
        default:             return unidade(daFonte: fonte)
        }
    }

    /// A unidade do índice em si. É a resposta literal ao "1,15 o quê?".
    static var unidadeDoIndice: String {
        frase("distance from the usual behavior of the previous 12 weeks")
    }

    /// O texto do "?" ao lado do número, para quem quiser saber a escala.
    ///
    /// A pergunta veio assim, em teste de uso: *"Solid cresceu 1,1, o que é
    /// esse número? 110%? 10%?"* — e as duas respostas estavam erradas, o que
    /// mostra que a tela deixava adivinhar. O primeiro trabalho deste texto é
    /// negar a leitura de porcentagem, porque é a que a pessoa tenta sozinha.
    static var tituloDaEscala: String { frase("What this number is") }
    static var textoDaEscala: String {
        frase("It is not a percentage. The number counts standard deviations: how far this week sits from this attribute's own average over the previous 12 weeks. Around 0 is a typical week; around 1 is an unusual one; above 2 is rare.\n\nA percentage would need a baseline that differs for every attribute, so two attributes could not be compared directly. This standardized scale allows attributes to be compared with one another.")
    }

    /// O valor compacto usado em comparação. A unidade/escala vem na linha de
    /// apoio imediatamente abaixo, para não transformar jargão no título.
    static func numeroComUnidade(_ indice: Double?) -> String {
        guard let indice else { return frase("no index") }
        let n = Leitura.numero(indice, casas: 2, sinal: true)
        return "\(n)"
    }

    // MARK: Por que este estado

    /// "1 source", "2 sources" -- nunca "1 sources".
    private static func fontes(_ n: Int) -> String {
        n == 1 ? frase("1 source") : frase("\(String(n)) sources")
    }

    /// A regra que produziu o estado, dita para quem vai decidir compra.
    ///
    /// Espelha `computar_indice()` linha a linha. A ordem importa: o `pico` é
    /// testado antes de "em alta" no Postgres, e aqui também.
    ///
    /// **O QUE SAIU DAQUI EM 28/08, E POR QUÊ**
    ///
    /// Esta frase diz o que foi medido para ESTE termo. A regra geral -- que
    /// confirmar um movimento pede duas semanas seguidas com duas fontes
    /// concordando -- saiu e foi para o Q&A do menu, onde é procurável.
    ///
    /// Ela vinha impressa em todo cartão da lista, sempre com as mesmas
    /// palavras, e o JP mediu o valor dela com precisão: *"é aquele tipo de
    /// coisa que é bom que o user saiba mas não vai ser uma vida se ele não
    /// souber"*. Método repetido em cada linha vira textura e para de ser
    /// lido; explicado uma vez, num lugar fixo, continua sendo método.
    ///
    /// O que fica em cada cartão é o que muda de cartão para cartão: o número
    /// desta semana, a faixa em que ele caiu e quantas fontes concordaram. A
    /// trilha completa continua no "Where this reading comes from".
    static func porQue(estado: String?, indice: IndiceSemanal, series: [PontoSerie]) -> String {
        guard let estado else {
            return frase("Two sources do not yet agree on a direction; this update has \(String(indice.nPernas ?? 0)).")
        }
        let editorial = series.first { $0.fonte.hasPrefix("editorial") && $0.z != nil }
        let acima = indice.meta?.pernasAcimaDe1 ?? 0
        let abaixo = indice.meta?.pernasAbaixoDe1 ?? 0

        switch estado {
        case "pico":
            let intensidade = editorial?.z.map(Leitura.emPalavras)
                ?? frase("far above the usual range")
            let referencia = editorial?.z.map {
                " " + frase("(\(Leitura.numero($0, casas: 1)) on the statistical scale)")
            } ?? ""
            // Esta continua dizendo o que é: pico não é alta, e quem lê o
            // cartão precisa saber disso antes de comprar. Não é regra geral
            // do motor -- é a classificação DESTE termo nesta semana.
            return frase("Press attention was \(intensidade)\(referencia) for one week, and no other source followed — an isolated editorial spike, not a confirmed trend.")
        case "em alta":
            return frase("Two consecutive weeks above the usual range, with \(fontes(acima)) agreeing.")
        case "em queda":
            return frase("Two consecutive weeks below the usual range, with \(fontes(abaixo)) agreeing.")
        case "estavel":
            // AQUI MORAVA UMA CONTRADIÇÃO, e ela aparecia em todo cartão.
            //
            // O selo e esta frase liam campos DIFERENTES: o selo mostra a
            // faixa do z desta semana, e a frase lia `estado`, que é a
            // classificação de movimento CONFIRMADO -- duas semanas seguidas,
            // duas fontes concordando, §22. As duas podem divergir sem que
            // nenhuma esteja errada: um termo pode estar abaixo da faixa nesta
            // semana e ainda não ser uma queda confirmada.
            //
            // Só que o cartão as apresentava como uma afirmação só, e o
            // resultado era "Under the usual range" no selo com "Within this
            // attribute's usual range" logo abaixo. O JP viu de outro ângulo:
            // "não vejo valor em tudo ter o mesmo texto". Não era falta de
            // variedade; era a frase respondendo a uma pergunta que o selo não
            // fez.
            //
            // Agora ela diz as duas coisas na ordem certa: onde o termo está
            // ESTA semana, com o número, e por que isso ainda não é um
            // movimento. É a única leitura do cartão que a pessoa não deduz
            // sozinha, e é diferente para cada termo.
            //
            // ATUALIZAÇÃO DE 28/08: a frase de dentro da faixa abria com
            // "Within this attribute's usual range" a dois dedos de um selo
            // dizendo "Within the usual range". Não era erro -- era a mesma
            // medida dita duas vezes, e o JP marcou de novo: *"não gostei da
            // repetição de within e within"*. A frase é de 14/08 e o selo
            // chegou depois; ninguém escreveu as duas juntas.
            //
            // Agora ela abre pelo que o selo NÃO tem como dizer: o número
            // desta semana e a semana anterior. Mesma forma do caso de fora
            // da faixa, e diferente de termo para termo.
            guard let z = indice.indice, Leitura.faixa(z) != .habitual else {
                guard let z = indice.indice else {
                    return frase("No index for this week. Stable is a measured result, not missing data.")
                }
                // "+0,0" é sinal que o número não sustenta; some abaixo de 0,05.
                let arredondado = (abs(z) * 10).rounded() / 10
                let n = arredondado == 0
                    ? "0.0" : Leitura.numero(z, casas: 1, sinal: true)
                return frase("This week reads \(n) on the statistical scale, and the week before stayed in the same place. Stable is a measured result, not missing data.")
            }
            return frase("This week it reads \(Leitura.numero(z, casas: 1, sinal: true)) on the statistical scale, \(Leitura.emPalavras(z)) — but one week is not a movement.")
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
                    // `String($0)`, e não o `Int` direto: interpolar um número
                    // dentro de `frase(_:)` deixa a chave com `%lld` e faz o
                    // sistema aplicar o separador de milhar do idioma — 7217
                    // viraria "7,217" em inglês e "7.217" em português. Seria
                    // até melhor tipografia, mas mudaria a formatação de um
                    // número que o resto do app imprime cru, e formatação de
                    // número neste projeto tem dono (`Formato`/`Leitura`).
                    // Traduzir não é hora de mexer nisso pelas beiradas.
                    let n = p.nAmostra.map { frase("\(String($0)) panel items") }
                        ?? frase("sample not recorded")
                    linha += frase("\(v)% of the assortment (\(n))")
                case let f where f.hasPrefix("editorial"):
                    // Só a perna editorial trabalha em janela de 4 semanas
                    // (§18). Dizer "em 4 semanas" para a busca era colar a
                    // janela de uma perna no número de outra.
                    let n = p.nAmostra.map(String.init) ?? "—"
                    linha += frase("\(n) \(unidade(daFonte: p.fonte)) over 4 weeks")
                    if let crua = p.meta?.contagemSemanaCrua {
                        linha += frase(", \(String(crua)) this week")
                    }
                default:
                    let v = p.valorBruto.map { Leitura.numero($0, casas: 0) } ?? "—"
                    linha += frase("\(v) out of 100 on the \(unidadeCurta(daFonte: p.fonte))")
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

    /// O banco responde em português e com referência de seção -- "cobertura
    /// insuficiente (§8)". Isso aparecia cru numa interface em inglês, junto
    /// com um "§8" que não significa nada para quem usa o app. A tradução mora
    /// aqui, e o texto desconhecido passa adiante em vez de sumir: é melhor o
    /// usuário ver uma frase estranha do que o app esconder o motivo.
    static func motivoDeExclusao(_ bruto: String?) -> String {
        guard let bruto, !bruto.trimmingCharacters(in: .whitespaces).isEmpty else {
            return frase("no reason recorded")
        }
        let semSecao = bruto.replacingOccurrences(
            of: "\\s*\\(§\\d+[^)]*\\)", with: "",
            options: .regularExpression).trimmingCharacters(in: .whitespaces)
        switch semSecao.lowercased() {
        case "cobertura insuficiente":
            return frase("not enough coverage this week")
        case "sem leitura", "sem leitura na semana":
            return frase("no reading this week")
        case "fonte unica", "fonte única":
            return frase("only one source, so no directional state")
        default:
            return semSecao
        }
    }
}

extension String {
    /// Só a primeira letra, quando a frase vira título de linha.
    /// `capitalized` maiúscularia todas as palavras.
    var capitalizedPrimeira: String {
        isEmpty ? self : prefix(1).uppercased() + dropFirst()
    }
}
