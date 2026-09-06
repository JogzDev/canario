import Foundation

/// Formatação de data e hora do app.
///
/// Duas regras que valem em toda a interface e em todo o código:
///
/// 1. **Data sempre em dd/MM/aaaa.** O banco guarda ISO (2026-07-27) porque é o
///    formato certo para ordenar e comparar; a tela nunca mostra ISO.
/// 2. **Horário sempre de Brasília.** O servidor grava em UTC — o cron roda em
///    UTC e o Postgres devolve UTC — então converter na exibição é obrigatório,
///    não opcional. Sem isso a "última coleta" apareceria três horas adiantada.
enum Formato {

    /// America/Sao_Paulo, não o fuso do aparelho: um comprador viajando não
    /// deve ver a data da coleta mudar de lugar.
    static let brasilia = TimeZone(identifier: "America/Sao_Paulo") ?? .current

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoComHora: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Formata em UTC de propósito, igual ao parser acima.
    ///
    /// "2026-07-27" vindo de uma coluna `date` do Postgres é uma DATA DE
    /// CALENDÁRIO, não um instante: não tem hora nem fuso. Convertê-la para
    /// Brasília a joga para 21:00 do dia anterior — e a tela mostraria
    /// "04/01/2026" onde o banco diz 05/01. Fuso só se aplica a timestamp, que
    /// é o que `diaEHora` trata.
    private static let dia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    private static let diaEHora: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = brasilia
        f.dateFormat = "dd/MM/yyyy 'at' HH:mm"
        return f
    }()

    /// "2026-07-27" → "27/07/2026". Devolve a entrada se não for uma data ISO,
    /// para nunca esconder um dado malformado atrás de um traço.
    static func data(_ texto: String) -> String {
        guard let d = iso.date(from: String(texto.prefix(10))) else { return texto }
        return dia.string(from: d)
    }

    /// A mesma data ISO como `Date`, para eixos e recortes temporais. O método
    /// é deliberadamente opcional: uma semana malformada não ganha uma posição
    /// inventada no gráfico.
    static func dataISO(_ texto: String) -> Date? {
        iso.date(from: String(texto.prefix(10)))
    }

    /// Carimbo de coleta com hora, em Brasília (§27 exige a data visível junto
    /// dos números).
    static func dataEHora(_ texto: String) -> String {
        if let d = isoComHora.date(from: texto) { return diaEHora.string(from: d) }
        let semFracao = ISO8601DateFormatter()
        if let d = semFracao.date(from: texto) { return diaEHora.string(from: d) }
        return data(texto)
    }

    /// Preço em real, com vírgula decimal e separador de milhar.
    static func dinheiro(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .currency
        f.currencyCode = "BRL"
        // Centavos só abaixo de cem: "R$ 1.199" lê melhor que "R$ 1.199,00" numa
        // lista, e o centavo de uma peça de mil reais não muda decisão nenhuma.
        f.maximumFractionDigits = v >= 100 ? 0 : 2
        let bruto = f.string(from: NSNumber(value: v)) ?? "R$ \(Int(v))"
        // O `NumberFormatter` separa "R$" do número com espaço NÃO-QUEBRÁVEL
        // (U+00A0). Ele imprime igual a um espaço comum, e por isso o teste que
        // procurava "R$ 130" falhava sem que a tela mostrasse nada de errado.
        return bruto.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Contagem com separador de milhar no idioma-fonte da interface.
    ///
    /// Existe porque a tela do cluster mostrava "3542 no painel". Número de
    /// quatro dígitos sem ponto é notação de código, da mesma família do
    /// "-2.18" que virou "-2,18" em 31/07.
    static func contagem(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let bruto = f.string(from: NSNumber(value: n)) ?? "\(n)"
        return bruto.replacingOccurrences(of: "\u{00A0}", with: ",")
    }

    /// Duração em linguagem de quem compra coleção: "menos de 2 meses" diz mais
    /// que "54 dias" quando o assunto é ritmo de reposição.
    static func periodo(dias: Int) -> String {
        switch dias {
        case ..<0:   return "—"
        // Uma chave por forma, em vez de sufixo montado por ternário: em
        // português "1 dia"/"3 dias" mudam só no plural, mas "1 semana"/"3
        // semanas" mudam o gênero do que vem junto, e uma tradução não
        // consegue reordenar isso a partir de um "s" solto dentro da chave.
        case 0...13:
            let d = max(dias, 1)
            return d == 1 ? frase("1 day") : frase("\(String(d)) days")
        case 14...44:
            let semanas = Int((Double(dias) / 7).rounded())
            return semanas == 1 ? frase("1 week") : frase("\(String(semanas)) weeks")
        default:
            // `dias/30 + 1` e não `ceil`: com ceil, 90 dias viraria "menos de 3
            // meses", que é falso — 90 dias são três meses cravados. Somar um ao
            // piso deixa a frase sempre verdadeira, que é o que a regra 2 pede.
            let meses = dias / 30 + 1
            return frase("under \(String(meses)) months")
        }
    }

    /// Hoje em Brasília, no formato ISO do banco. Serve para a tela comparar a
    /// data de um dado com o dia corrente sem depender do fuso do aparelho.
    static func hojeEmBrasilia() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = brasilia
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Idade de uma data de calendário do banco em relação a hoje em Brasília.
    /// Um dado futuro ou malformado não é tratado como velho por conveniência.
    static func diasDesde(_ texto: String, hoje: Date = Date()) -> Int {
        guard let data = iso.date(from: String(texto.prefix(10))) else { return 0 }
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone(identifier: "UTC") ?? .current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = brasilia
        f.dateFormat = "yyyy-MM-dd"
        guard let hojeCalendario = iso.date(from: f.string(from: hoje)) else { return 0 }
        let inicio = calendario.startOfDay(for: data)
        let fim = calendario.startOfDay(for: hojeCalendario)
        return max(0, calendario.dateComponents([.day], from: inicio, to: fim).day ?? 0)
    }

    /// "31/07/2026 às 04:12" → só a hora, para o carimbo de atualização.
    static func hora(_ texto: String) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = brasilia
        f.dateFormat = "HH:mm"
        if let d = isoComHora.date(from: texto) { return f.string(from: d) }
        let semFracao = ISO8601DateFormatter()
        if let d = semFracao.date(from: texto) { return f.string(from: d) }
        return nil
    }
}
