import Foundation

/// O que o app lê do Supabase. Nada aqui é calculado no dispositivo:
/// **servidor calcula, app consulta** (§33).

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

    enum CodingKeys: String, CodingKey {
        case id, rotulo, dimensao, exclusiva, sinonimos
        case semPernaBusca = "sem_perna_busca"
    }

    /// Rótulo + sinônimos, para a tradução da busca do usuário (§11).
    var termosDeBusca: [String] {
        var lista = [rotulo, id.replacingOccurrences(of: "_", with: " ")]
        if let s = sinonimos, !s.isEmpty {
            lista.append(contentsOf: s.split(separator: "|").map(String.init))
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

    enum CodingKeys: String, CodingKey {
        case id, segmento, semana, indice, estado
        case termoId = "termo_id"
        case pernasAtivas = "pernas_ativas"
        case nPernas = "n_pernas"
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

    enum CodingKeys: String, CodingKey {
        case id, fonte, semana, z
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
