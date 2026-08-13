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
struct Termo: Decodable, Identifiable, Hashable {
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
struct IndiceSemanal: Decodable, Identifiable, Hashable {
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
    struct Meta: Decodable, Hashable {
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
        case .emAlta: return "Em alta"
        case .emQueda: return "Em queda"
        case .pico: return "Pico"
        case .estavel: return "Estável"
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
struct PontoSerie: Decodable, Identifiable, Hashable {
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
    struct Meta: Decodable, Hashable {
        let unidade: String?
        let veiculos: [String: Int]?
        let exemplos: [Exemplo]?
        let contagemSemanaCrua: Int?
        let metrica: String?
        let nTotalSortimento: Double?

        struct Exemplo: Decodable, Hashable {
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
        case "busca": return "busca"
        case "editorial_br": return "editorial BR"
        case "editorial_intl": return "editorial internacional"
        case "varejo": return "varejo"
        case "lyst": return "Lyst"
        default: return fonte
        }
    }

    static func frase(_ pernas: [String]?) -> String {
        guard let pernas, !pernas.isEmpty else { return "sem perna ativa" }
        return "baseado em: " + pernas.map(rotulo).joined(separator: " + ")
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
    let suficiente: Bool

    enum CodingKeys: String, CodingKey {
        case segmento, semana, suficiente
        case termoId = "termo_id"
        case pecasNaCelula = "pecas_na_celula"
        case marcasExternas = "marcas_externas"
        case minimoPecas = "minimo_pecas"
        case minimoMarcas = "minimo_marcas"
    }

    /// Frase honesta sobre o que falta, para a tela não dizer só "não dá".
    var oQueFalta: String {
        var partes: [String] = []
        if let p = pecasNaCelula, p < minimoPecas {
            partes.append("\(p) peças no painel nesta semana, mínimo \(minimoPecas)")
        }
        if let m = marcasExternas, m < minimoMarcas {
            partes.append("\(m) marcas externas coletando, mínimo \(minimoMarcas)")
        }
        return partes.isEmpty ? "cobertura abaixo do mínimo" : partes.joined(separator: "; ")
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
        return self.indice(indice, cobertura: cobertura)
            && indice.termoId == varejo.termoId
            && indice.semana == varejo.semana
    }

    /// A aba Comparar precisa de um recorte comum; "o mais recente de cada"
    /// pode juntar semanas diferentes numa frase só.
    static func semanaComum(indices: [IndiceSemanal], varejo: [PontoSerie],
                            coberturas: [Cobertura]) -> String? {
        let semanasI = Set(indices.filter { $0.segmento == Recorte.segmento }.map(\.semana))
        let semanasV = Set(varejo.map(\.semana))
        let semanasC = Set(coberturas.filter { $0.segmento == Recorte.segmento }.map(\.semana))
        return semanasI.intersection(semanasV).intersection(semanasC).max()
    }
}

// MARK: - Eventos

/// Um evento de varejo (§23). Reposição é o sinal mais forte do painel: é a
/// marca decidindo repor com o próprio dinheiro, não uma ruptura que pode ser
/// só estoque acabando.
struct EventoVarejo: Decodable, Identifiable, Hashable {
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

    struct Detalhe: Decodable, Hashable {
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
            return "Tamanho \(t) voltou e permaneceu disponível"
        case "remarcacao":
            if let pct = detalhe?.quedaPct { return String(format: "Preço caiu %.1f%%", pct) }
            return "Preço caiu"
        case "saida_de_linha":
            return "Saiu do catálogo"
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
        let coisa = tipo == "reposicao" ? "reposição" : (tipo == "remarcacao" ? "remarcação" : nil)
        guard let coisa else { return nil }

        if ordinal == 1 {
            return "1ª \(coisa) desde \(Formato.data(inicioDaColeta))"
        }
        var frase = "\(ordinal)ª \(coisa)"
        if tipo == "reposicao", let t = detalhe?.tamanhos, !t.isEmpty {
            frase += " do tamanho \(t.joined(separator: "/"))"
        }
        if let dias = diasDesdeAPrimeira {
            frase += " em \(Formato.periodo(dias: dias))"
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
        case 2.0...:        return "muito acima do normal"
        case 1.0..<2.0:     return "acima do normal"
        case 0.35..<1.0:    return "levemente acima"
        case -0.35..<0.35:  return "no normal"
        case -1.0 ..< -0.35: return "levemente abaixo"
        case -2.0 ..< -1.0: return "abaixo do normal"
        default:            return "muito abaixo do normal"
        }
    }

    /// O que o número é, dito por extenso. Vai na letra miúda, sempre.
    static func explicacao(_ z: Double) -> String {
        let lado = z >= 0 ? "acima" : "abaixo"
        return "\(numero(abs(z), casas: 1)) na escala estatística, \(lado) do comportamento normal das últimas 12 semanas"
    }

    /// Variação percentual entre o valor mais recente e a média da janela.
    /// É a unidade que K6 pede como principal para cada perna.
    static func variacao(recente: Double?, media: Double?) -> String? {
        guard let recente, let media, media > 0 else { return nil }
        let pct = 100.0 * (recente - media) / media
        return "\(numero(pct, casas: 0, sinal: true))% vs. a média da janela"
    }

    /// Número em português: **vírgula decimal**.
    ///
    /// O app já tinha regra de data em dd/mm/aaaa e de horário de Brasília, e
    /// esta é da mesma família — estava faltando. A tela mostrava "-2.18" e
    /// "2.2 desvios", que é notação de código, não de quem lê em português.
    static func numero(_ v: Double, casas: Int, sinal: Bool = false) -> String {
        let formato = sinal ? "%+.\(casas)f" : "%.\(casas)f"
        return String(format: formato, v).replacingOccurrences(of: ".", with: ",")
    }
}
