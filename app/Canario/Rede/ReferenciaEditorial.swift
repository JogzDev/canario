import Foundation

/// A matéria que contém a expressão pesquisada (A58).
///
/// ## O defeito que este arquivo existe para corrigir
///
/// Em 17/09/2026 o JP pesquisou **"Napoleon Jacket"** — a expressão exata de
/// uma manchete que o próprio app exibia na aba de tendências — e recebeu
/// apenas "Casacos e jaquetas". A §11 manda a busca traduzir texto livre para
/// a taxonomia, e foi o que ela fez; o problema é o que acontece com o resto
/// da frase, que desaparece em silêncio. O título estava gravado: 1 entre
/// 172.649 artigos, Refinery29, 31/08/2026.
///
/// Duas coisas diferentes estavam coladas numa só resposta. "Napoleon Jacket"
/// **como atributo** é, de fato, casaco; "Napoleon Jacket" **como expressão**
/// é uma frase que a imprensa escreveu num dia, num veículo, num link. A
/// tradução para a taxonomia continua igual; o que muda é que a expressão
/// literal para de ser jogada fora.
///
/// ## O que este bloco NÃO é
///
/// Não é resumo da matéria, e não pode virar um. O coletor editorial guarda
/// título, veículo, data e URL — **o corpo do texto não está no banco**. Então
/// o app entrega a REFERÊNCIA e manda ler na fonte. Escrever "segundo a
/// Refinery29, a jaqueta Napoleão volta porque…" a partir de um título seria
/// inventar a reportagem, que é o que a §5 proíbe com todas as letras.
///
/// ## Por que o recorte de público vem do banco, e não daqui
///
/// `buscar_referencia_editorial` filtra `publico_editorial <> 'masculino'`,
/// que é o mesmo recorte do painel. Se o filtro morasse no app, uma versão
/// antiga instalada no aparelho de alguém continuaria mostrando matéria fora
/// do recorte — e a correção não alcançaria quem já baixou.
enum ReferenciaEditorial {

    struct Resposta: Decodable {
        let expressao: String
        /// `false` quando a expressão é curta ou longa demais para buscar.
        /// Vem do banco porque o limite é dele: uma busca de duas letras varre
        /// 172 mil títulos para devolver ruído.
        let buscavel: Bool
        /// Quantas matérias casam, e não quantas voltaram. A diferença entre
        /// os dois números é a mesma que derrubou a manchete da capa: amostra
        /// contada como se fosse população.
        let total: Int
        let materias: [Materia]
    }

    struct Materia: Decodable, Identifiable, Hashable {
        let titulo: String
        let veiculo: String?
        let data: String?
        let url: String?

        /// A URL é a chave natural (ela é `unique` na tabela). O título só
        /// entra como reserva para uma matéria sem link, que não deveria
        /// existir e, se existir, não pode derrubar a lista.
        var id: String { url ?? titulo }

        var endereco: URL? { url.flatMap(URL.init(string:)) }

        /// "Refinery29 · 31/08/2026", ou só o que existir.
        var procedencia: String {
            [veiculo, data.map(Formato.data)]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    /// A frase do topo do bloco. `nil` quando não há o que dizer — expressão
    /// curta demais para buscar, ou nenhuma matéria com ela.
    ///
    /// Aspas curvas de propósito: a expressão é do usuário e aparece literal,
    /// então precisa estar visivelmente entre aspas para ninguém confundir o
    /// que ele escreveu com o que o app afirma.
    static func manchete(_ r: Resposta) -> String? {
        guard r.buscavel, r.total > 0 else { return nil }
        return r.total == 1
            ? frase("1 story in the press we track mentions “\(r.expressao)”.")
            : frase("\(Formato.contagem(r.total)) stories in the press we track mention “\(r.expressao)”.")
    }

    /// Quando a lista é amostra, ela diz que é. Sem isto, cinco linhas na tela
    /// afirmam "cinco matérias" quando existem vinte e três.
    static func recorte(_ r: Resposta) -> String? {
        guard r.total > r.materias.count, !r.materias.isEmpty else { return nil }
        return frase("Showing the \(String(r.materias.count)) most recent.")
    }

    /// A ressalva que impede a leitura errada do bloco inteiro.
    static let ondeEstaOTexto = frase("DataDrobe stores the headline, the outlet, the date and the link — not the article. Open the source to read it.")
}
