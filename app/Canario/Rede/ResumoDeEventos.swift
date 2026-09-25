import Foundation

/// A agregação da janela inteira, separada dos exemplos que a ilustram (A58).
///
/// ## O defeito que este arquivo existe para corrigir
///
/// A capa pedia `eventos_recentes(tipo, 120)`, agrupava por marca e escrevia a
/// contagem da **amostra** como se fosse a do mercado. Medido em 17/09/2026
/// sobre o dado que estava no app:
///
/// - reposição de 01/09: 505 eventos reais, 120 entregues. O real dizia Le Lis
///   Blanc 289; a tela dizia C&A 52.
/// - remarcação de 02/09: 917 reais, 120 entregues. O real dizia Maria Filó
///   698; a tela dizia "Maria Filó baixou o preço de 36 peças".
///
/// Pior que o corte era o critério dele: `order by data desc, id desc` premia
/// quem foi **gravado** por último, não quem repôs mais — parte do "peso da
/// C&A" era ordem de inserção.
///
/// ## A separação que este modelo carrega
///
/// `pecas` é a população inteira da janela, em produtos distintos. `exemplos`
/// é uma amostra por marca, para as fotos, e **nunca** alimenta contagem. São
/// dois campos diferentes de propósito: enquanto eram o mesmo array, era
/// inevitável que a tela contasse o que dava para mostrar.
///
/// ## Denominador é opcional, e a taxa se cala sem ele
///
/// `pecas_ofertadas` e `por_mil_ofertadas` chegam nulos quando não existe
/// sortimento observado para aquele dia — fora da retenção de 21 dias, por
/// exemplo. Nesse caso a tela mostra a contagem absoluta e não inventa taxa;
/// dividir pelo sortimento de hoje uma semana de agosto seria pior do que não
/// dividir.
enum ResumoDeEventos {

    struct Resposta: Codable, Hashable {
        let tipo: String
        /// Primeiro e último dia da janela. A janela é COMUM aos três tipos,
        /// ancorada na observação do painel: sem isso, "nenhuma remarcação
        /// nesta semana" recuava até a última remarcação registrada e a
        /// apresentava como atual.
        let de: String?
        let ate: String?
        let dias: Int?
        let diasDesdeOFim: Int?
        let unidade: String?
        /// A data do sortimento que serviu de denominador. Nula quando não há
        /// denominador para aquele dia — e aí as taxas por marca também são.
        let denominadorEm: String?
        let totalPecas: Int
        let totalEventos: Int
        let marcas: [Marca]

        enum CodingKeys: String, CodingKey {
            case tipo, de, ate, dias, unidade, marcas
            case diasDesdeOFim = "dias_desde_o_fim"
            case denominadorEm = "denominador_em"
            case totalPecas = "total_pecas"
            case totalEventos = "total_eventos"
        }
    }

    struct Marca: Codable, Hashable, Identifiable {
        let marca: String
        /// Produtos distintos com evento na janela. É o número da manchete.
        let pecas: Int
        /// Eventos, que podem ser mais que peças: a mesma peça repõe duas
        /// vezes na mesma semana. Os dois existem porque respondem perguntas
        /// diferentes, e porque misturá-los foi o defeito original.
        let eventos: Int
        let pecasRepetidas: Int?
        let maiorQuedaPct: Double?
        let pecasOfertadas: Int?
        let porMilOfertadas: Double?
        /// Produtos distintos observados na mesma janela dos eventos (A69).
        let pecasObservadas: Int?
        let porMilObservadas: Double?
        let tamanhos: [String]?
        let exemplos: [Exemplo]

        var id: String { marca }

        enum CodingKeys: String, CodingKey {
            case marca, pecas, eventos, tamanhos, exemplos
            case pecasRepetidas = "pecas_repetidas"
            case maiorQuedaPct = "maior_queda_pct"
            case pecasOfertadas = "pecas_ofertadas"
            case porMilOfertadas = "por_mil_ofertadas"
            case pecasObservadas = "pecas_observadas"
            case porMilObservadas = "por_mil_observadas"
        }
    }

    /// Uma peça da vitrine da marca. Amostra, e a tela diz que é.
    struct Exemplo: Codable, Hashable, Identifiable {
        let peca: String?
        let imagem: String?
        let urlDaPeca: String?
        let data: String?
        let repetida: Bool?
        /// O sinal que o JP pediu em 31/07: "3ª reposição dos tamanhos PP/P
        /// em menos de 2 meses". Vem do banco porque contar aqui exigiria a
        /// população inteira no aparelho.
        let ordinal: Int?
        let diasDesdeAPrimeira: Int?
        let detalhe: EventoVarejo.Detalhe?

        var id: String { (urlDaPeca ?? peca ?? "?") + (data ?? "") }

        enum CodingKeys: String, CodingKey {
            case peca, imagem, data, repetida, ordinal, detalhe
            case urlDaPeca = "url_da_peca"
            case diasDesdeAPrimeira = "dias_desde_a_primeira"
        }

        /// As mesmas frases de `eventos_recentes`, escritas uma vez só em
        /// `LeituraDoEvento`. O exemplo não carrega o tipo -- ele é da
        /// resposta inteira --, então ele entra por parâmetro.
        func resumo(tipo: String) -> String {
            LeituraDoEvento.resumo(tipo: tipo, detalhe: detalhe)
        }

        func repeticao(tipo: String, desde inicioDaColeta: String) -> String? {
            LeituraDoEvento.repeticao(tipo: tipo, ordinal: ordinal,
                                      detalhe: detalhe,
                                      diasDesdeAPrimeira: diasDesdeAPrimeira,
                                      desde: inicioDaColeta)
        }
    }

    // MARK: As frases

    /// O carimbo da janela: de quando até quando, e há quanto tempo terminou.
    ///
    /// A idade só aparece quando existe: com a coleta em dia, "esta semana" é
    /// verdade e dizer "0 dias atrás" seria ruído. Com a coleta parada, é a
    /// diferença entre informar e mentir.
    static func janela(_ r: Resposta) -> String? {
        guard let de = r.de, let ate = r.ate else { return nil }
        let periodo = "\(Formato.data(de)) – \(Formato.data(ate))"
        guard let dias = r.diasDesdeOFim, dias >= 2 else { return periodo }
        return frase("\(periodo) · ended \(Formato.periodo(dias: dias)) ago")
    }

    /// Quantas peças a janela inteira tem, e quantos eventos as moveram.
    static func total(_ r: Resposta) -> String {
        let pecas = r.totalPecas == 1
            ? frase("1 item")
            : frase("\(Formato.contagem(r.totalPecas)) items")
        guard r.totalEventos > r.totalPecas else { return pecas }
        return frase("\(pecas) · \(Formato.contagem(r.totalEventos)) events")
    }

    /// A taxa por mil peças observadas na mesma janela, quando disponível.
    ///
    /// É o que separa "quem mexeu mais" de "quem mexeu mais no próprio
    /// catálogo": a C&A lidera contagens absolutas sem necessariamente
    /// liderar a taxa. Sem denominador, a frase não existe.
    static func taxa(_ m: Marca) -> String? {
        guard let porMil = m.porMilObservadas, let observadas = m.pecasObservadas,
              observadas > 0 else { return nil }
        return frase("\(Leitura.numero(porMil, casas: 1)) per 1,000 observed this week")
    }

    /// A linha de apoio de uma marca: repetição e alcance, sem enfeite.
    static func apoio(_ m: Marca) -> String {
        var partes: [String] = []
        if m.eventos > m.pecas {
            partes.append(frase("\(String(m.eventos)) events"))
        }
        if let repetidas = m.pecasRepetidas, repetidas > 0 {
            partes.append(repetidas == 1
                ? frase("1 had happened before")
                : frase("\(String(repetidas)) had happened before"))
        }
        if let taxa = taxa(m) { partes.append(taxa) }
        return partes.joined(separator: " · ")
    }

    /// A lista de uma marca é amostra, e precisa dizer de quantas.
    ///
    /// Sem esta frase, doze cartões afirmam "doze peças" quando a marca tem
    /// seiscentas — exatamente o defeito que a A58 corrigiu no banco, de volta
    /// pela tela.
    static func recorte(_ m: Marca) -> String? {
        guard m.pecas > m.exemplos.count, !m.exemplos.isEmpty else { return nil }
        return frase("Showing \(String(m.exemplos.count)) of \(Formato.contagem(m.pecas)) items, most recent first.")
    }
}
