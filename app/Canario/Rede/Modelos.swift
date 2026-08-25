import Foundation

/// O que o app lê do Supabase. Nada aqui é calculado no dispositivo:
/// **servidor calcula, app consulta** (§33).

/// O único recorte servido pela v1. Centralizar evita que uma tela consulte
/// silenciosamente outro segmento quando o banco passar a ter mais de um.
enum Recorte {
    static let segmento = "feminino_casual_br"
}

// MARK: - Taxonomia

/// Um termo aprovado. O app só recebe `status='aprovado'` — a regra inviolável 4
/// é aplicada por política de banco, não por filtro daqui.
struct Termo: Codable, Identifiable, Hashable {
    let id: String
    let rotulo: String
    let dimensao: String
    let exclusiva: Bool
    let sinonimos: String?
    let semPernaBusca: String?
    /// As mesmas listas que o coletor usa para etiquetar produto.
    let palavrasPt: String?
    let palavrasEn: String?

    enum CodingKeys: String, CodingKey {
        case id, rotulo, dimensao, exclusiva, sinonimos
        case semPernaBusca = "sem_perna_busca"
        case palavrasPt = "palavras_pt"
        case palavrasEn = "palavras_en"
    }

    /// Tudo que identifica o termo, para a tradução da busca (§11).
    ///
    /// Inclui `palavras_pt` e `palavras_en` DE PROPÓSITO: sem elas o app teria
    /// um vocabulário mais pobre que o do coletor para a mesma taxonomia. O
    /// teste da entrada por arquivo pegou isso — "Preta" num print não casava
    /// `preto`, porque o rótulo é "Preto" e a flexão só existe em
    /// `palavras_pt` ("preto|preta"). Vocabulário é um só, e é o da taxonomia.
    var termosDeBusca: [String] {
        var lista = [rotulo, id.replacingOccurrences(of: "_", with: " ")]
        for campo in [sinonimos, palavrasPt, palavrasEn] {
            if let c = campo, !c.isEmpty {
                lista.append(contentsOf: c.split(separator: "|").map(String.init))
            }
        }
        return lista
    }
}

// MARK: - Índice

/// O estado semanal de um termo. `estado` é opcional de propósito: quando há
/// menos de duas pernas ativas, a §22 não permite declarar estado, e o app
/// mostra silêncio honesto em vez de inventar "estável" (regra 2 e regra 6).
struct IndiceSemanal: Codable, Identifiable, Hashable {
    let id: Int
    let termoId: String
    let segmento: String
    let semana: String
    let indice: Double?
    let estado: String?
    let pernasAtivas: [String]?
    let nPernas: Int?
    let meta: Meta?
    let computadoEm: String?

    /// O que a §22 registrou junto do número. Existe para a tela poder
    /// **explicar o estado ao usuário**, e não só exibi-lo: "pico" sem motivo é
    /// um rótulo que o comprador não sabe se deve seguir ou ignorar.
    struct Meta: Codable, Hashable {
        let indiceSemanaAnterior: Double?
        let pernasAcimaDe1: Int?
        let pernasAbaixoDe1: Int?

        enum CodingKeys: String, CodingKey {
            case indiceSemanaAnterior = "indice_semana_anterior"
            case pernasAcimaDe1 = "pernas_acima_de_1"
            case pernasAbaixoDe1 = "pernas_abaixo_de_-1"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, segmento, semana, indice, estado, meta
        case termoId = "termo_id"
        case pernasAtivas = "pernas_ativas"
        case nPernas = "n_pernas"
        case computadoEm = "computado_em"
    }
}

/// Escolhe a leitura que a interface deve representar como **estado**.
///
/// O motor continua publicando o índice mais recente mesmo quando apenas uma
/// fonte chegou naquela semana; por isso a linha mais nova pode não ter estado.
/// A interface procura, no máximo nas 12 leituras anteriores, a última semana
/// em que duas fontes realmente sustentaram um estado. A data continua sempre
/// visível. Se não existir, preserva a linha mais nova e o silêncio honesto.
enum SelecaoDeEstado {
    static let janelaMaxima = 13

    static func preferida(em leituras: [IndiceSemanal]) -> IndiceSemanal? {
        let ordenadas = leituras.sorted { $0.semana > $1.semana }
        guard let maisNova = ordenadas.first else { return nil }
        return ordenadas.prefix(janelaMaxima).first { $0.estado != nil } ?? maisNova
    }

    static func porTermo(_ leituras: [IndiceSemanal]) -> [String: IndiceSemanal] {
        Dictionary(grouping: leituras, by: \.termoId)
            .compactMapValues { preferida(em: $0) }
    }
}

/// Como o app fala de estado. Os rótulos não carregam duração no título, que é
/// o que a §27 exige — janela de tempo vai para a letra miúda dos insumos.
enum Estado: String {
    case emAlta = "em alta"
    case emQueda = "em queda"
    case pico = "pico"
    case estavel = "estavel"

    var rotulo: String {
        switch self {
        case .emAlta: return "Trending up"
        case .emQueda: return "Trending down"
        case .pico: return "Spike"
        case .estavel: return "Within the usual range"
        }
    }

    /// §32: estado nunca é comunicado só por cor. O ícone vai junto sempre.
    var icone: String {
        switch self {
        case .emAlta: return "arrow.up.right"
        case .emQueda: return "arrow.down.right"
        case .pico: return "bolt.fill"
        case .estavel: return "equal"
        }
    }
}

// MARK: - Série

/// Um ponto de série por fonte. Alimenta o minigráfico do §29.3.
struct PontoSerie: Codable, Identifiable, Hashable {
    let id: Int
    let termoId: String
    let fonte: String
    let semana: String
    let valorBruto: Double?
    let z: Double?
    let nAmostra: Int?
    let meta: Meta?

    /// O que a coleta guardou junto da contagem.
    ///
    /// `veiculos` e `exemplos` foram acrescentados em 31/07 porque a tela dizia
    /// só "baseado em: editorial BR", e o JP apontou o óbvio: isso não nomeia
    /// nada. A regra 3 pede o caminho até a origem, e a origem parava no rótulo
    /// da perna em vez de chegar no site que publicou.
    struct Meta: Codable, Hashable {
        let unidade: String?
        let veiculos: [String: Int]?
        let exemplos: [Exemplo]?
        let contagemSemanaCrua: Int?
        let metrica: String?
        let nTotalSortimento: Double?

        struct Exemplo: Codable, Hashable {
            let veiculo: String
            let titulo: String
            let url: String?
        }

        enum CodingKeys: String, CodingKey {
            case unidade, veiculos, exemplos, metrica
            case contagemSemanaCrua = "contagem_semana_crua"
            case nTotalSortimento = "n_total_sortimento"
        }

        /// "Elle Brasil (4), Vogue Brasil (2)", do maior para o menor.
        var veiculosEmTexto: String? {
            guard let veiculos, !veiculos.isEmpty else { return nil }
            return veiculos.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                .prefix(4)
                .map { "\($0.key) (\($0.value))" }
                .joined(separator: ", ")
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, fonte, semana, z, meta
        case termoId = "termo_id"
        case valorBruto = "valor_bruto"
        case nAmostra = "n_amostra"
    }
}

/// Nome de perna como o usuário lê. §8 exige que a tela declare quais pernas
/// sustentam cada número.
enum Perna {
    static func rotulo(_ fonte: String) -> String {
        switch fonte {
        case "busca": return "search"
        case "editorial_br": return "Brazilian editorial"
        case "editorial_intl": return "international editorial"
        case "varejo": return "retail"
        case "lyst": return "Lyst"
        default: return fonte
        }
    }

    static func frase(_ pernas: [String]?) -> String {
        guard let pernas, !pernas.isEmpty else { return "no active source" }
        return "based on: " + pernas.map(rotulo).joined(separator: " + ")
    }
}

// MARK: - Cobertura

/// O portão da §8: abaixo dos mínimos, a interface exibe "cobertura
/// insuficiente" e **não mostra índice nem estado**.
///
/// Existe porque o app não checava nada disso e exibia número sempre. Com o
/// dado de 30/07, seis células estavam abaixo do mínimo de 30 peças — a menor
/// com 4 — e o app mostrava índice em todas.
struct Cobertura: Decodable, Hashable {
    let termoId: String
    let segmento: String
    let semana: String
    let pecasNaCelula: Int?
    let marcasExternas: Int?
    let minimoPecas: Int
    let minimoMarcas: Int
    let pecasNaDimensao: Int?
    let coberturaDimensaoPct: Double?
    let minimoCoberturaDimensaoPct: Double?
    let suficiente: Bool

    enum CodingKeys: String, CodingKey {
        case segmento, semana, suficiente
        case termoId = "termo_id"
        case pecasNaCelula = "pecas_na_celula"
        case marcasExternas = "marcas_externas"
        case minimoPecas = "minimo_pecas"
        case minimoMarcas = "minimo_marcas"
        case pecasNaDimensao = "pecas_na_dimensao"
        case coberturaDimensaoPct = "cobertura_dimensao_pct"
        case minimoCoberturaDimensaoPct = "minimo_cobertura_dimensao_pct"
    }

    /// Frase honesta sobre o que falta, para a tela não dizer só "não dá".
    var oQueFalta: String {
        var partes: [String] = []
        if let p = pecasNaCelula, p < minimoPecas {
            partes.append("\(p) panel items this week, minimum \(minimoPecas)")
        }
        if let m = marcasExternas, m < minimoMarcas {
            partes.append("\(m) external brands reporting, minimum \(minimoMarcas)")
        }
        if let pct = coberturaDimensaoPct,
           let minimo = minimoCoberturaDimensaoPct,
           pct < minimo {
            partes.append(
                String(format: "this dimension labels %.1f%% of current offers, minimum %.0f%%",
                       pct, minimo))
        } else if coberturaDimensaoPct == nil {
            partes.append("dimension-level coverage has not been measured")
        }
        return partes.isEmpty ? "coverage below the minimum" : partes.joined(separator: "; ")
    }
}

/// Aplica a §8 em um único lugar. A ausência de cobertura reprova a leitura:
/// `nil` quer dizer "não foi medido", nunca "pode mostrar".
enum Elegibilidade {
    static func indice(_ indice: IndiceSemanal?, cobertura: Cobertura?) -> Bool {
        guard let indice, let cobertura else { return false }
        return cobertura.suficiente
            && cobertura.termoId == indice.termoId
            && cobertura.segmento == indice.segmento
            && cobertura.semana == indice.semana
    }

    static func comparacao(indice: IndiceSemanal?, varejo: PontoSerie?,
                           cobertura: Cobertura?) -> Bool {
        guard let indice, let varejo, let cobertura else { return false }
        return indice.indice != nil
            && varejo.valorBruto != nil
            && self.indice(indice, cobertura: cobertura)
            && indice.termoId == varejo.termoId
            && indice.semana == varejo.semana
    }

    /// A lista do Compare não pode desaparecer só porque o índice composto
    /// reprovou um portão. Presença no varejo continua sendo uma medição real
    /// e comparável; o segundo eixo fica explicitamente indisponível na linha.
    static func varejoComparavel(_ varejo: PontoSerie?) -> Bool {
        varejo?.fonte == "varejo" && varejo?.valorBruto != nil
    }

    /// Semana mais recente que contém pelo menos duas medições de varejo.
    /// Índice e cobertura enriquecem a comparação, mas não são pré-requisitos
    /// para a pessoa conseguir escolher entre os atributos observados.
    static func semanaComVarejo(_ varejo: [PontoSerie]) -> String? {
        let porSemana = Dictionary(grouping: varejo.filter(varejoComparavel), by: \.semana)
        return porSemana.keys.sorted(by: >).first {
            Set(porSemana[$0, default: []].map(\.termoId)).count >= 2
        }
    }

    /// Recorte do Compare: prefere a semana mais recente com uma base externa
    /// material, sem apagar os demais termos que têm presença no painel. Uma
    /// atualização parcial de dois índices não deve rebaixar a ferramenta
    /// inteira a duas escolhas.
    static func semanaDeComparacao(indices: [IndiceSemanal], varejo: [PontoSerie],
                                   coberturas: [Cobertura], minimoRico: Int = 8) -> String? {
        let semanas = Dictionary(grouping: varejo.filter(varejoComparavel), by: \.semana)
            .keys.sorted(by: >)
        var primeiraComVarejo: String?
        for semana in semanas {
            let mapaI = Dictionary(uniqueKeysWithValues: indices
                .filter { $0.segmento == Recorte.segmento && $0.semana == semana }
                .map { ($0.termoId, $0) })
            let mapaV = Dictionary(uniqueKeysWithValues: varejo
                .filter { $0.semana == semana }.map { ($0.termoId, $0) })
            let mapaC = Dictionary(uniqueKeysWithValues: coberturas
                .filter { $0.segmento == Recorte.segmento && $0.semana == semana }
                .map { ($0.termoId, $0) })
            let medidos = Set(mapaV.compactMap { varejoComparavel($0.value) ? $0.key : nil })
            if medidos.count >= 2, primeiraComVarejo == nil { primeiraComVarejo = semana }
            let completos = medidos.filter {
                comparacao(indice: mapaI[$0], varejo: mapaV[$0], cobertura: mapaC[$0])
            }
            if completos.count >= minimoRico { return semana }
        }
        return primeiraComVarejo
    }

    /// A aba Comparar precisa de um recorte comum; "o mais recente de cada"
    /// pode juntar semanas diferentes numa frase só. A semana também precisa
    /// sustentar uma comparação de verdade: uma atualização parcial com um
    /// único termo não pode esvaziar a tela inteira.
    static func semanaComum(indices: [IndiceSemanal], varejo: [PontoSerie],
                            coberturas: [Cobertura]) -> String? {
        let semanasI = Set(indices.filter { $0.segmento == Recorte.segmento }.map(\.semana))
        let semanasV = Set(varejo.map(\.semana))
        let semanasC = Set(coberturas.filter { $0.segmento == Recorte.segmento }.map(\.semana))
        let candidatas = semanasI.intersection(semanasV).intersection(semanasC).sorted(by: >)

        for semana in candidatas {
            let mapaI = Dictionary(uniqueKeysWithValues: indices
                .filter { $0.segmento == Recorte.segmento && $0.semana == semana }
                .map { ($0.termoId, $0) })
            let mapaV = Dictionary(uniqueKeysWithValues: varejo
                .filter { $0.semana == semana }
                .map { ($0.termoId, $0) })
            let mapaC = Dictionary(uniqueKeysWithValues: coberturas
                .filter { $0.segmento == Recorte.segmento && $0.semana == semana }
                .map { ($0.termoId, $0) })
            let comparaveis = Set(mapaI.keys).intersection(mapaV.keys).intersection(mapaC.keys)
                .filter { comparacao(indice: mapaI[$0], varejo: mapaV[$0], cobertura: mapaC[$0]) }
            if comparaveis.count >= 2 { return semana }
        }
        return nil
    }
}

// MARK: - Eventos

/// Um evento de varejo (§23). Reposição é o sinal mais forte do painel: é a
/// marca decidindo repor com o próprio dinheiro, não uma ruptura que pode ser
/// só estoque acabando.
struct EventoVarejo: Codable, Identifiable, Hashable {
    let id: Int
    let tipo: String
    let data: String
    let semana: String
    let marca: String
    let peca: String?
    let urlDaPeca: String?
    /// Hotlink para o CDN da própria loja, sob a mesma decisão A13 usada nos
    /// similares. O app não copia a imagem para o servidor nem para o binário.
    let imagem: String?
    let detalhe: Detalhe?
    /// Quantas vezes isto já aconteceu com esta peça, contando esta.
    let ordinal: Int?
    /// Dias entre a primeira ocorrência e esta. Nulo quando é a primeira.
    let diasDesdeAPrimeira: Int?

    struct Detalhe: Codable, Hashable {
        let tamanhos: [String]?
        // Vem como NUMERO no jsonb; declarar String derrubava a decodificacao
        // e a tela mostrava "nao consegui consultar" como se fosse rede.
        let quedaPct: Double?
        let precoDe: Double?
        let precoPara: Double?

        enum CodingKeys: String, CodingKey {
            case tamanhos
            case quedaPct = "queda_pct"
            case precoDe = "preco_de"
            case precoPara = "preco_para"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, tipo, data, semana, marca, peca, imagem, detalhe, ordinal
        case urlDaPeca = "url_da_peca"
        case diasDesdeAPrimeira = "dias_desde_a_primeira"
    }

    /// Uma linha de leitura humana. Fato observado, nunca projeção.
    var resumo: String {
        switch tipo {
        case "reposicao":
            let t = detalhe?.tamanhos?.joined(separator: ", ") ?? "—"
            return "Size \(t) returned and remained available"
        case "remarcacao":
            // "Price dropped 50%" media uma coisa e era lida como outra.
            //
            // `computar_eventos` (regra K4) compara o preço de hoje com o
            // ANTERIOR OBSERVADO: o tamanho do corte que a marca deu nesta
            // semana. O selo do site desconta do preço de TABELA. Os dois são
            // certos e quase nunca batem — a peça 5572 da PatBo caiu de
            // R$ 799 para R$ 400 (50% de corte) sobre uma tabela de R$ 1.998
            // (80% no site). Só coincidem quando a peça nunca tinha sido
            // remarcada antes, que é por que "alguns estavam corretos".
            //
            // Mostrar os dois preços faz a frase se explicar sozinha: quem
            // duvidar confere a conta na própria linha.
            if let pct = detalhe?.quedaPct,
               let de = detalhe?.precoDe, let para = detalhe?.precoPara {
                return String(format: "%.0f%% below its previous price: %@ → %@",
                              pct, Formato.dinheiro(de), Formato.dinheiro(para))
            }
            if let pct = detalhe?.quedaPct {
                return String(format: "%.1f%% below its previous price", pct)
            }
            return "Price cut since the last reading"
        case "saida_de_linha":
            return "Removed from the catalog"
        default:
            return tipo
        }
    }

    /// A repetição, que é onde mora o sinal.
    ///
    /// O JP pediu "*1ª reposição" e "*3ª reposição dos tamanhos PP/P em menos
    /// de 2 meses", e a segunda frase é muito mais forte: repor três vezes o
    /// mesmo tamanho em dois meses é a marca dizendo que aquele tamanho vende.
    ///
    /// A **1ª vem ancorada na data em que passamos a olhar**, e não solta. Dizer
    /// "1ª reposição" com oito dias de coleta afirmaria que nunca houve outra
    /// antes, que é coisa que não medimos — e a regra 2 proíbe afirmar o que não
    /// foi medido.
    func repeticao(desde inicioDaColeta: String) -> String? {
        guard let ordinal else { return nil }
        let coisa = tipo == "reposicao" ? "restock" : (tipo == "remarcacao" ? "markdown" : nil)
        guard let coisa else { return nil }

        if ordinal == 1 {
            return "First \(coisa) since \(Formato.data(inicioDaColeta))"
        }
        let mod100 = ordinal % 100
        let suffix: String
        if 11...13 ~= mod100 {
            suffix = "th"
        } else {
            switch ordinal % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        var frase = "\(ordinal)\(suffix) \(coisa)"
        if tipo == "reposicao", let t = detalhe?.tamanhos, !t.isEmpty {
            frase += " for size \(t.joined(separator: "/"))"
        }
        if let dias = diasDesdeAPrimeira {
            frase += " in \(Formato.periodo(dias: dias))"
        }
        return frase
    }

    var icone: String {
        switch tipo {
        case "reposicao": return "arrow.clockwise"
        case "remarcacao": return "tag"
        case "saida_de_linha": return "xmark.circle"
        default: return "circle"
        }
    }
}

// MARK: - Leitura humana do índice

/// Traduz o z-score para linguagem de quem compra coleção.
///
/// O número cru é desvio-padrão contra a própria história do termo (§21). Isso
/// é preciso e ilegível: "−1,29" não diz nada para quem decide coleção.
///
/// A constante K6 da auditoria já mandava fazer assim — "variação percentual do
/// valor bruto na janela, com o z entre parênteses; nunca apresentar z como se
/// fosse porcentagem" — e não tinha sido implementada.
enum Leitura {

    /// Frase curta para o número principal.
    static func emPalavras(_ z: Double) -> String {
        switch z {
        case 2.0...:        return "far above the usual range"
        case 1.0..<2.0:     return "above the usual range"
        case 0.35..<1.0:    return "slightly above the usual range"
        case -0.35..<0.35:  return "within the usual range"
        case -1.0 ..< -0.35: return "slightly below the usual range"
        case -2.0 ..< -1.0: return "below the usual range"
        default:            return "far below the usual range"
        }
    }

    /// A mesma leitura quando ela ocupa o lugar de título ou selo. Capitaliza
    /// somente a primeira letra; `capitalized` alteraria todas as palavras.
    static func comoTitulo(_ z: Double) -> String {
        let frase = emPalavras(z)
        return frase.prefix(1).uppercased() + frase.dropFirst()
    }

    /// O que o número é, dito por extenso. Vai na letra miúda, sempre.
    ///
    /// A direção sai do valor EXIBIDO, não do bruto. Com `z >= 0 ? above :
    /// below` sobre o valor bruto, um z de 0,04 imprimia "0,0 on the
    /// statistical scale, **above** this attribute's usual behavior" logo
    /// abaixo de um selo dizendo "within the usual range" -- visto em aparelho
    /// em 19/08/2026. Duas frases sobre o mesmo número, uma contradizendo a
    /// outra, e a errada era a que afirmava direção que o número não sustenta.
    static func explicacao(_ z: Double) -> String {
        let exibido = (abs(z) * 10).rounded() / 10
        let lado = exibido == 0
            ? "level with"
            : (z > 0 ? "above" : "below")
        return "\(numero(exibido, casas: 1)) on the statistical scale, \(lado) this attribute's usual behavior over the previous 12 weeks"
    }

    /// Variação percentual entre o valor mais recente e a média da janela.
    /// É a unidade que K6 pede como principal para cada perna.
    static func variacao(recente: Double?, media: Double?) -> String? {
        guard let recente, let media, media > 0 else { return nil }
        let pct = 100.0 * (recente - media) / media
        return "\(numero(pct, casas: 0, sinal: true))% vs. the window average"
    }

    /// Número no idioma-fonte da interface (inglês), com ponto decimal.
    static func numero(_ v: Double, casas: Int, sinal: Bool = false) -> String {
        let formato = sinal ? "%+.\(casas)f" : "%.\(casas)f"
        return String(format: formato,
                      locale: Locale(identifier: "en_US_POSIX"),
                      arguments: [v])
    }
}
