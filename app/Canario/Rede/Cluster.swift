import Foundation

/// Índice do cluster — o número da peça inteira (§22, K5).
///
/// ## O que ele é, e o que ele não pode virar
///
/// É a média dos índices dos atributos **ponderada por raridade**, na mesma
/// unidade do índice de um atributo: desvios contra a própria história (§21).
/// Responde *"quanto este conjunto de atributos se moveu"*.
///
/// Não responde nada sobre volume futuro de vendas. A §5 fecha essa porta com
/// todas as letras, e um número único por peça é exatamente onde essa linha é
/// fácil de cruzar sem perceber. Três coisas seguram isso aqui:
///
/// 1. **A unidade fica visível.** Nunca um 0–100 sem dimensão.
/// 2. **Os pesos são auditáveis.** A tela mostra quanto cada atributo pesou e
///    por quê — regra 3, caminho até a origem.
/// 3. **Ele se cala quando os atributos discordam.** Ver `haDirecao`.
///
/// ## Por que ele pode se calar
///
/// Medido no caso real *vestido + floral + midi*: índice −0,77, mas `vestido`
/// está em −3,10 e `floral` em +0,29. A média existe; a leitura, não. Chamar
/// aquilo de "conjunto em queda" seria repetir a falha da manchete da curva de
/// tamanhos, corrigida em 01/08 — um número que a média produz e a dispersão
/// desmente.
enum Cluster {

    // MARK: O que vem do banco

    struct Resposta: Decodable {
        let indice: Double?
        let dispersao: Double?
        let atributosEfetivos: Double?
        let nAtributos: Int
        let haDirecao: Bool
        let categoriaUsada: String?
        let unidade: String?
        let atributos: [Atributo]

        enum CodingKeys: String, CodingKey {
            case indice, dispersao, unidade, atributos
            case atributosEfetivos = "atributos_efetivos"
            case nAtributos = "n_atributos"
            case haDirecao = "ha_direcao"
            case categoriaUsada = "categoria_usada"
        }
    }

    struct Atributo: Decodable, Identifiable, Hashable {
        let termoId: String
        let rotulo: String
        let dimensao: String
        let papel: String?
        let indice: Double?
        let estado: String?
        let semana: String?
        let pernas: [String]?
        let peso: Double?
        let pesoRelativo: Double?
        let pecasNoPainel: Int?
        let pctNaDimensao: Double?
        let foraPor: String?

        var id: String { termoId }

        enum CodingKeys: String, CodingKey {
            case rotulo, dimensao, papel, indice, estado, semana, pernas, peso
            case termoId = "termo_id"
            case pesoRelativo = "peso_relativo"
            case pecasNoPainel = "pecas_no_painel"
            case pctNaDimensao = "pct_na_dimensao"
            case foraPor = "fora_por"
        }
    }

    // MARK: A manchete

    /// A frase principal. Só afirma direção quando o dado sustenta.
    static func manchete(_ r: Resposta) -> String {
        guard let indice = r.indice, r.nAtributos > 0 else {
            return frase("There is no combined reading for this item yet.")
        }
        if r.nAtributos == 1 {
            return frase("With one attribute, the combined reading is that attribute's own reading: ")
                 + Leitura.emPalavras(indice) + "."
        }
        if !r.haDirecao {
            return frase("This item's attributes do not point in the same direction.")
        }
        return frase("Together, these attributes are \(Leitura.emPalavras(indice)).")
    }

    /// A explicação de baixo da manchete: o número, a unidade e a base.
    ///
    /// K6 pede a unidade sempre visível. Um índice sem unidade é o "Preto subiu
    /// 1,15 — 1,15 o quê?" que o JP apontou em 31/07, agora no lugar mais
    /// perigoso possível, que é o número que resume a peça.
    static func explicacao(_ r: Resposta) -> String? {
        guard let indice = r.indice, r.nAtributos > 0 else { return nil }
        // Sinal só quando ele significa alguma coisa. Um índice que arredonda
        // para zero saía como "-0.00 standard deviations" -- um menos na frente
        // de zero, anunciando uma direção que a própria frase abaixo diz não
        // existir. Zero não tem lado.
        var partes = ["\(Leitura.numero(indice, casas: 2, sinal: abs(indice) >= 0.005)) standard deviations, "
                    + "an average of \(r.nAtributos) attribute\(r.nAtributos == 1 ? "" : "s") "
                    + "weighted by how uncommon each one is in the panel"]
        if !r.haDirecao, let d = r.dispersao {
            partes.append(frase("They spread \(Leitura.numero(d, casas: 2)) deviations around that average — more than the average moves away from zero. That is why no direction is stated"))
        }
        return partes.joined(separator: ". ") + "."
    }

    /// Kish: quantos atributos **realmente** sustentam o número.
    ///
    /// Se um atributo carrega quase todo o peso, o "índice do conjunto" é um
    /// atributo só usando roupa de conjunto, e quem lê merece saber disso.
    /// Só aparece quando há concentração de verdade — abaixo de 70% do total,
    /// dizer isso seria ruído.
    static func concentracao(_ r: Resposta) -> String? {
        guard let efetivos = r.atributosEfetivos, r.nAtributos > 1,
              efetivos < Double(r.nAtributos) * 0.7 else { return nil }
        return frase("In practice, the number rests on \(Leitura.numero(efetivos, casas: 1)) of the \(String(r.nAtributos)) attributes because their weights are uneven.")
    }

    /// Como a raridade foi calculada, em uma frase que o comprador entende.
    static func criterioDaRaridade(_ r: Resposta) -> String {
        let base: String
        if let c = r.categoriaUsada, c != "(todas)" {
            base = frase("among the panel's \(Traducao.rotuloExibido(id: c).lowercased()) items")
        } else {
            base = frase("across the whole panel because no single category was selected")
        }
        return frase("An uncommon attribute weighs more than a common one. Rarity is measured \(base), within its own dimension — midi is compared with other lengths, not with colors.")
    }

    /// A linha de auditoria de um atributo: peso, e de onde o peso saiu.
    static func porQuePesa(_ a: Atributo) -> String? {
        guard let rel = a.pesoRelativo else { return nil }
        // Chamava-se `frase`, e o nome passou a colidir com a função global
        // que resolve texto no idioma escolhido. Aqui o compilador reclamaria;
        // o risco de verdade é o caso em que ele não reclama.
        var linha = frase("\(Leitura.numero(rel * 100, casas: 0))% of the weight")
        if a.papel == "denominador" {
            return linha + " · " + frase("it has no rarity of its own: it is a taxonomy baseline, so it receives the dimension's average weight")
        }
        if let pct = a.pctNaDimensao, let n = a.pecasNoPainel {
            linha += " · " + frase("\(Leitura.numero(pct, casas: 0))% of items with this dimension (\(Formato.contagem(n)) in the panel)")
        }
        return linha
    }

    /// Regra 6: o que ficou de fora aparece, com o motivo, no lugar onde a
    /// pessoa procuraria.
    static func deFora(_ r: Resposta) -> [Atributo] {
        r.atributos.filter { $0.foraPor != nil }
    }

    static func dentro(_ r: Resposta) -> [Atributo] {
        r.atributos.filter { $0.foraPor == nil }
    }

    /// Semanas diferentes entre atributos é fato, não defeito: cada perna tem
    /// sua cadência. Mas misturar sem avisar seria esconder.
    static func ressalvaDeSemana(_ r: Resposta) -> String? {
        let semanas = Set(dentro(r).compactMap(\.semana))
        guard semanas.count > 1 else { return nil }
        let ordenadas = semanas.sorted()
        guard let mais = ordenadas.last, let menos = ordenadas.first else { return nil }
        return frase("The attributes are not all from the same week: they range from \(Formato.data(menos)) to \(Formato.data(mais)). Each source has its own cadence, so the latest reading for each attribute is used.")
    }
}
