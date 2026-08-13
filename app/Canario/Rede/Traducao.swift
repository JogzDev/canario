import Foundation

/// Tradução da busca do usuário para termos da taxonomia (§11).
///
/// Está num arquivo próprio, e não dentro da tela, por dois motivos: é a regra
/// mais fácil de violar sem perceber ("a barra de busca do app nunca vira
/// filtro de texto cru") e é a única lógica do app que merece teste — o resto
/// é layout e leitura de rede.
enum Traducao {

    /// Nome que a pessoa usou, quando ele é mais claro que o rótulo interno.
    ///
    /// A taxonomia agrupa poá dentro de `geometrica`, porque o motor precisa de
    /// uma série com volume. Isso não obriga a interface a responder "Geométrica
    /// e étnica" para quem escreveu "vestido de bolinha". O cálculo continua
    /// no id aprovado; só a conversa preserva a palavra de quem pesquisou.
    static func rotuloAmigavel(_ termo: Termo, na consulta: String) -> String {
        let palavras = Set(normalizar(consulta)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
        if termo.id == "geometrica" {
            if !palavras.isDisjoint(with: ["bolinha", "bolinhas"]) { return "Bolinha" }
            if palavras.contains("poa") { return "Poá" }
        }
        return termo.rotulo
    }

    /// Descrição da peça em linguagem de busca, sem expor ids ou agrupamentos
    /// editoriais. O resultado é apenas apresentação; os ids não mudam.
    static func descricaoAmigavel(_ termos: [Termo], consulta: String) -> String {
        termos.map { rotuloAmigavel($0, na: consulta) }.joined(separator: " · ")
    }

    /// Normaliza para comparação: sem acento, minúsculas, sem espaço nas pontas.
    static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Quebra um candidato em partes independentes.
    ///
    /// Metade dos rótulos da taxonomia é ENUMERAÇÃO, não expressão: "Casaco e
    /// jaqueta", "Blusa e top", "Tricô e crochê", "Branco e cru". Exigir todas
    /// as palavras nesses casos faz a busca mais óbvia falhar — quem digita
    /// "casaco" não encontrava "Casaco e jaqueta".
    ///
    /// Já "wide leg" e "manga bufante" são expressões: as palavras andam
    /// juntas e só valem juntas. A diferença é o conectivo.
    private static func partes(_ candidato: String) -> [[String]] {
        let normalizado = normalizar(candidato)
        // Separadores de enumeração; o resto continua sendo frase.
        let pedacos = normalizado
            .replacingOccurrences(of: " e ", with: "|")
            .replacingOccurrences(of: "/", with: "|")
            .split(separator: "|")
        return pedacos.compactMap { pedaco in
            let palavras = pedaco
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            return palavras.isEmpty ? nil : palavras
        }
    }

    /// Casa a string do usuário contra rótulos, ids e sinônimos.
    ///
    /// Casa por PALAVRA INTEIRA, nunca por pedaço de palavra. É a mesma
    /// regressão que o `matcher.py` carrega do lado do coletor: "reta" não pode
    /// casar "preta", senão uma peça preta entra como silhueta reta.
    static func casa(_ consulta: String, _ termo: Termo) -> Bool {
        let alvo = normalizar(consulta)
        guard !alvo.isEmpty else { return false }
        let palavrasDaConsulta = Set(alvo.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
        guard !palavrasDaConsulta.isEmpty else { return false }

        for candidato in termo.termosDeBusca {
            for palavrasDaParte in partes(candidato) {
                // Dentro de uma parte, é expressão: todas as palavras contam.
                if palavrasDaParte.allSatisfy({ palavrasDaConsulta.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    /// Todos os termos que a consulta alcança, na ordem em que vieram.
    static func termos(para consulta: String, em todos: [Termo]) -> [Termo] {
        todos.filter { casa(consulta, $0) }
    }
}
