import Foundation

/// A curva de tamanhos (§24), do jeito que o comprador precisa ler.
///
/// ## O que este arquivo protege
///
/// A §24 permite **recomendar composição de grade** (redistribuição, soma zero)
/// e proíbe recomendar volume (regra inviolável 1). A fronteira entre as duas
/// coisas é uma frase, e é aqui que ela é escrita — por isso o texto está fora
/// da tela e testado.
///
/// A §24 também exige uma ressalva que não é decorativa: **o público da marca
/// do usuário não é o público médio do painel.** Modelagem e clientela são
/// próprias. Isto é referência de mercado, não prescrição.
///
/// ## O achado, e o que ele não é
///
/// Medido em 01/08/2026, no painel inteiro, escada de letra:
///
///     P  3,57%   (11.135 em risco)
///     M  3,26%
///     G  2,68%
///     PP 2,35%
///     GG 2,16%
///
/// A quebra tem pico em **P**, não em PP. Isso importa: quem lê "os menores
/// quebram mais" e reforça PP estaria agindo sobre uma leitura errada — PP é o
/// segundo que menos quebra. O texto desta tela nomeia o tamanho de pico em vez
/// de falar em "menores" genericamente, justamente para não induzir esse erro.
enum CurvaDeTamanhos {

    /// Uma faixa da grade. Os rótulos vêm de dentro da grade de cada produto,
    /// nunca de uma tabela que equipara tamanho entre marcas.
    struct Faixa: Decodable, Hashable, Identifiable {
        let termoId: String?
        let semana: String
        let sistema: String
        let faixa: String
        let rotulo: String?
        let nGrades: Int
        let nEmRisco: Int
        let nQuebrou: Int
        let taxaQuebra: Double?
        let shareIndisponivel: Double?

        var id: String { "\(termoId ?? "painel")-\(sistema)-\(faixa)-\(rotulo ?? "")" }

        enum CodingKeys: String, CodingKey {
            case semana, sistema, faixa, rotulo
            case termoId = "termo_id"
            case nGrades = "n_grades"
            case nEmRisco = "n_em_risco"
            case nQuebrou = "n_quebrou"
            case taxaQuebra = "taxa_quebra"
            case shareIndisponivel = "share_indisponivel"
        }
    }

    /// §8 aplicado à curva: sem grade suficiente, não há leitura.
    ///
    /// O número é de tamanhos **em risco**, não de peças: uma peça contribui com
    /// vários pares (produto, tamanho), e é o par que sustenta a taxa.
    static let minimoEmRisco = 300

    /// Mínimo por tamanho para ele entrar na curva.
    ///
    /// Existe porque a primeira versão desta tela elegeu como destaque um `M`
    /// com 727 em risco e 4,3%, na frente do `P` com 11.135 e 3,6% — e escolheu
    /// como piso um `P` com **4** em risco e 0,0%, o que zerou a manchete
    /// inteira. Amostra pequena produz taxa extrema, e taxa extrema ganha
    /// qualquer comparação por máximo.
    static let minimoPorTamanho = 500

    // MARK: Consolidação

    /// Junta as linhas do mesmo rótulo numa só.
    ///
    /// O banco guarda a curva por (faixa, rótulo), e o **mesmo rótulo cai em
    /// faixas diferentes conforme o formato da grade**: `M` é meio numa grade de
    /// cinco degraus, é maiores numa de três que vai de PP a M, é menores numa
    /// que vai de M a XGG. Sem consolidar, a tela mostrava `M` três vezes, `P`
    /// duas, e comparava linhas de tamanhos de amostra incomparáveis.
    ///
    /// A taxa consolidada é ponderada pelo risco — soma os quebrados, soma os
    /// em risco e divide. Média das taxas daria peso igual a uma linha de 4 e a
    /// uma de 11 mil.
    static func consolidar(_ linhas: [CurvaDeTamanhos.Faixa]) -> [CurvaDeTamanhos.Faixa] {
        var porRotulo: [String: (risco: Int, quebrou: Int, grades: Int, modelo: Faixa)] = [:]
        for l in linhas {
            guard let r = l.rotulo else { continue }
            let atual = porRotulo[r]
            porRotulo[r] = (
                risco: (atual?.risco ?? 0) + l.nEmRisco,
                quebrou: (atual?.quebrou ?? 0) + l.nQuebrou,
                grades: max(atual?.grades ?? 0, l.nGrades),
                // Guarda a faixa da linha de maior risco: é a posição em que
                // aquele rótulo vive na maioria das grades.
                modelo: (atual.map { $0.risco >= l.nEmRisco ? $0.modelo : l } ?? l))
        }
        return porRotulo
            .filter { $0.value.risco >= minimoPorTamanho }
            .map { rotulo, v in
                Faixa(termoId: v.modelo.termoId, semana: v.modelo.semana,
                      sistema: v.modelo.sistema, faixa: v.modelo.faixa,
                      rotulo: rotulo, nGrades: v.grades,
                      nEmRisco: v.risco, nQuebrou: v.quebrou,
                      taxaQuebra: v.risco > 0 ? 100.0 * Double(v.quebrou) / Double(v.risco) : nil,
                      shareIndisponivel: nil)
            }
    }

    // MARK: A leitura

    /// Erro-padrão de uma taxa de quebra, em pontos percentuais.
    static func erroPadrao(_ f: Faixa) -> Double {
        guard let t = f.taxaQuebra, f.nEmRisco > 0 else { return .infinity }
        let p = t / 100
        return 100 * (p * (1 - p) / Double(f.nEmRisco)).squareRoot()
    }

    /// Duas taxas são indistinguíveis quando a diferença cabe em dois
    /// erros-padrão da diferença.
    ///
    /// **Existe porque a tela me pegou.** Depois da limpeza dos atributos, o
    /// painel mostrou M com 5,4% e P com 5,3% — e a manchete declarou o M
    /// campeão. Em onze mil amostras cada, um décimo de ponto é ruído: os dois
    /// erros-padrão somam 0,6 ponto. Eleger vencedor ali é afirmar o que não
    /// foi medido, que é o que a regra 2 proíbe.
    static func empatados(_ a: Faixa, _ b: Faixa) -> Bool {
        guard let ta = a.taxaQuebra, let tb = b.taxaQuebra else { return false }
        let margem = 2 * (erroPadrao(a) * erroPadrao(a) + erroPadrao(b) * erroPadrao(b)).squareRoot()
        return abs(ta - tb) < margem
    }

    /// A frase principal, construída só sobre o que foi medido.
    ///
    /// Nomeia o tamanho em vez de dizer "os menores": no painel, PP é dos que
    /// MENOS saem, e "os menores quebram mais" levaria o comprador a reforçar
    /// justamente a ponta mais lenta da grade.
    static func manchete(porRotulo linhas: [Faixa]) -> String? {
        let ordenado = linhas
            .filter { $0.rotulo != nil && $0.taxaQuebra != nil }
            .sorted { ($0.taxaQuebra ?? 0) > ($1.taxaQuebra ?? 0) }
        guard ordenado.count >= 3, let pico = ordenado.first, let vale = ordenado.last,
              let taxaPico = pico.taxaQuebra, let taxaVale = vale.taxaQuebra,
              taxaVale > 0, let rotuloVale = vale.rotulo
        else { return nil }

        // Quem empata com o primeiro entra na manchete junto.
        let noTopo = ordenado.filter { $0.id == pico.id || empatados(pico, $0) }
        let nomes = noTopo.compactMap(\.rotulo)
        let vezes = Leitura.numero(taxaPico / taxaVale, casas: 1)

        let sujeito: String
        if nomes.count == 1 {
            sujeito = "O tamanho \(nomes[0]) é o que mais sai de linha no painel"
        } else {
            let lista = nomes.dropLast().joined(separator: ", ") + " e " + (nomes.last ?? "")
            sujeito = "Os tamanhos \(lista) saem de linha no mesmo ritmo, e são os mais rápidos do painel"
        }

        return sujeito + ": "
             + "\(Leitura.numero(taxaPico, casas: 1))% dos que estavam disponíveis ficaram "
             + "indisponíveis na janela, contra \(Leitura.numero(taxaVale, casas: 1))% do \(rotuloVale) — "
             + "\(vezes) vez\(vezes == "1,0" ? "" : "es") a taxa dele."
    }

    /// O formato da quebra, que é o que a §24 chama de "à esquerda" ou "à direita".
    static func formato(menores: Faixa?, maiores: Faixa?) -> String? {
        guard let m = menores?.taxaQuebra, let g = maiores?.taxaQuebra, g > 0 else { return nil }
        let razao = m / g
        let vezes = Leitura.numero(razao, casas: 2)
        if razao >= 1.15 {
            return "A quebra pende para os tamanhos menores da grade: eles saem \(vezes) vezes mais que os maiores."
        }
        if razao <= 0.87 {
            let inverso = Leitura.numero(1 / razao, casas: 2)
            return "A quebra pende para os tamanhos maiores da grade: eles saem \(inverso) vezes mais que os menores."
        }
        return "As duas pontas da grade saem em ritmo parecido nesta janela. Sem formato declarado."
    }

    /// **Composição de grade, soma zero.** É o único tipo de recomendação que a
    /// §24 autoriza, e a soma zero é o que a mantém do lado permitido: fala de
    /// proporção entre tamanhos, nunca de quantas peças comprar.
    ///
    /// A frase é condicional de propósito. O painel não conhece a modelagem nem
    /// a clientela de quem lê.
    static func composicao(porRotulo linhas: [Faixa]) -> String? {
        let ordenado = linhas
            .filter { $0.rotulo != nil && $0.taxaQuebra != nil }
            .sorted { ($0.taxaQuebra ?? 0) > ($1.taxaQuebra ?? 0) }
        guard ordenado.count >= 3, let pico = ordenado.first, let vale = ordenado.last,
              let rVale = vale.rotulo
        else { return nil }
        // Sem diferença que se sustente, não há composição a sugerir. Mandar
        // deslocar grade sobre ruído seria pior que não dizer nada.
        guard !empatados(pico, vale) else {
            return "Nesta seleção os tamanhos saem em ritmo parecido, dentro da margem de erro. "
                 + "Não há deslocamento de grade que este dado sustente."
        }
        let noTopo = ordenado.filter { $0.id == pico.id || empatados(pico, $0) }
            .compactMap(\.rotulo)
        let destino = noTopo.count == 1 ? noTopo[0] : noTopo.joined(separator: " e ")
        return "Se a sua grade hoje for uniforme e o seu público se parecer com o do painel, "
             + "o que este dado sugere é deslocar participação de \(rVale) para \(destino) — "
             + "trocando proporção entre tamanhos, sem mexer no total de peças. "
             + "Quantas peças comprar depende do seu custo, do seu prazo e do seu histórico, que não estão aqui."
    }

    /// §24, ressalva obrigatória. Não é rodapé: é a condição de uso do número.
    static let ressalvas = [
        "O público da sua marca não é o público médio do painel: modelagem e clientela são suas. Isto é referência de mercado, não prescrição.",
        "Não vemos quantidade em estoque. Marca costuma comprar menos nas pontas da grade, e isso sozinho já acelera a saída de PP e GG.",
        "A taxa conta tamanhos que estavam disponíveis e deixaram de estar. Não é venda: é saída do ar, que pode ser venda, remanejamento ou fim de linha.",
    ]

    /// O que sustenta o número, em uma linha (regra 3).
    static func insumo(_ linhas: [Faixa], janelaDias: Int = 14) -> String {
        let risco = linhas.reduce(0) { $0 + $1.nEmRisco }
        let grades = linhas.map(\.nGrades).max() ?? 0
        let semana = linhas.first?.semana ?? ""
        return "\(risco) tamanhos em risco em \(grades) grades do painel, janela de \(janelaDias) dias, semana de \(Formato.data(semana))."
    }

    /// Ordena os rótulos do menor para o maior, para a tela desenhar a curva na
    /// ordem em que a grade existe.
    static func emOrdem(_ linhas: [Faixa]) -> [Faixa] {
        let ordem = ["PP": 1, "P": 2, "M": 3, "G": 4, "GG": 5]
        return linhas
            .filter { $0.rotulo != nil }
            .sorted { a, b in
                let x = ordem[a.rotulo ?? ""] ?? Int(a.rotulo ?? "") ?? 99
                let y = ordem[b.rotulo ?? ""] ?? Int(b.rotulo ?? "") ?? 99
                return x < y
            }
    }
}
