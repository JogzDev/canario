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
        f.dateFormat = "dd/MM/yyyy 'às' HH:mm"
        return f
    }()

    /// "2026-07-27" → "27/07/2026". Devolve a entrada se não for uma data ISO,
    /// para nunca esconder um dado malformado atrás de um traço.
    static func data(_ texto: String) -> String {
        guard let d = iso.date(from: String(texto.prefix(10))) else { return texto }
        return dia.string(from: d)
    }

    /// Carimbo de coleta com hora, em Brasília (§27 exige a data visível junto
    /// dos números).
    static func dataEHora(_ texto: String) -> String {
        if let d = isoComHora.date(from: texto) { return diaEHora.string(from: d) }
        let semFracao = ISO8601DateFormatter()
        if let d = semFracao.date(from: texto) { return diaEHora.string(from: d) }
        return data(texto)
    }
}
