import Foundation

/// A leitura específica de uma peça (2.0), como a Edge Function `ler-peca`
/// devolve.
///
/// O servidor já fez o trabalho que importa: interpretou o pedido, buscou as
/// candidatas no painel publicado, verificou cada uma, calculou os fatos e
/// cortou toda frase com número sem prova. A tela só mostra -- e mostra a
/// prova: cada frase cita fatos, cada fato lista as peças que o sustentam.
struct LeituraEspecifica: Codable, Sendable {
    let versao: String?
    let foraDeEscopo: Bool?
    let nome: String?
    let explicacao: String?
    let painelObservadoEm: String?
    let frases: [Frase]
    let fatos: [String: Fato]
    let pecas: [Peca]
    let parecidas: [Peca]
    let perguntas: [Pergunta]
    let busca: Busca?

    struct Frase: Codable, Hashable, Sendable {
        let texto: String
        let fatos: [String]
    }

    /// Só o que a tela usa de um fato: quantas peças e quais.
    struct Fato: Codable, Sendable {
        let pecas: Int?
        let provas: [Int]?
        let marcas: Int?
        let minimo: Double?
        let mediana: Double?
        let maximo: Double?
        let comTamanhoEsgotado: Int?
    }

    struct Peca: Codable, Identifiable, Hashable, Sendable {
        let id: Int
        let titulo: String
        let marca: String
        let preco: Double?
        let precoOriginal: Double?
        let imagemUrl: String?
        let url: String?

        /// Remarcada de verdade: pelo menos 5% abaixo do preço original, a
        /// mesma régua do motor.
        var remarcada: Bool {
            guard let preco, let precoOriginal, precoOriginal > 0 else { return false }
            return preco <= precoOriginal * 0.95
        }
    }

    struct Pergunta: Codable, Hashable, Sendable {
        let pergunta: String
        let opcoes: [String]
    }

    struct Busca: Codable, Sendable {
        let candidatas: Int?
        let confirmadas: Int?
        let parecidas: Int?
    }

    enum CodingKeys: String, CodingKey {
        case versao, foraDeEscopo, nome, explicacao, painelObservadoEm, frases, fatos,
             pecas, parecidas, perguntas, busca
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        versao = try c.decodeIfPresent(String.self, forKey: .versao)
        foraDeEscopo = try c.decodeIfPresent(Bool.self, forKey: .foraDeEscopo)
        nome = try c.decodeIfPresent(String.self, forKey: .nome)
        explicacao = try c.decodeIfPresent(String.self, forKey: .explicacao)
        painelObservadoEm = try c.decodeIfPresent(String.self, forKey: .painelObservadoEm)
        frases = try c.decodeIfPresent([Frase].self, forKey: .frases) ?? []
        fatos = try c.decodeIfPresent([String: Fato].self, forKey: .fatos) ?? [:]
        pecas = try c.decodeIfPresent([Peca].self, forKey: .pecas) ?? []
        parecidas = try c.decodeIfPresent([Peca].self, forKey: .parecidas) ?? []
        perguntas = try c.decodeIfPresent([Pergunta].self, forKey: .perguntas) ?? []
        busca = try c.decodeIfPresent(Busca.self, forKey: .busca)
    }

    static func decodificar(_ dados: Data) throws -> LeituraEspecifica {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(LeituraEspecifica.self, from: dados)
    }

    /// As peças que provam uma frase, na ordem em que os fatos as citam, sem
    /// repetir. Procura nas lidas e nas parecidas: a frase de "nenhuma é a
    /// peça" prova com as parecidas.
    func provas(de frase: Frase) -> [Peca] {
        let todas = Dictionary((pecas + parecidas).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var vistas = Set<Int>()
        var saida: [Peca] = []
        for idDoFato in frase.fatos {
            for id in fatos[idDoFato]?.provas ?? [] where vistas.insert(id).inserted {
                if let peca = todas[id] { saida.append(peca) }
            }
        }
        return saida
    }
}

/// O que se sabe de uma peça da pessoa, no vocabulário da análise de foto.
///
/// A peça do Acervo guarda os termos da taxonomia; a Edge Function entende a
/// análise de foto (`category`, `pattern`, `colors`...). Os ids são os mesmos,
/// então a tradução é só de formato -- e a Leitura da peça salva não precisa
/// de foto nem de nova análise.
struct DescricaoDaPeca: Codable, Sendable, Hashable {
    var categoria: String?
    var estampa: String?
    var comprimento: String?
    var silhueta: String?
    var cores: [String] = []
    var tecidos: [String] = []
    var detalhes: [String] = []

    /// Os ids que a pessoa confirmou substituem qualquer classificação da
    /// foto. Só os detalhes livres, que a taxonomia não guarda, vêm da análise.
    static func daFoto(_ analise: AnaliseVisualRemota, confirmados ids: [String],
                       em termos: [Termo]) -> DescricaoDaPeca {
        var descricao = dosTermos(ids, em: termos)
        descricao.detalhes = limparDetalhes(analise.additionalVisualAttributes)
        return descricao
    }

    static func limparDetalhes(_ valores: [String]) -> [String] {
        var vistos = Set<String>()
        return Array(valores.compactMap { valor -> String? in
            let limpo = valor.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !limpo.isEmpty, limpo.lowercased() != "not_visible" else { return nil }
            let curto = String(limpo.prefix(60))
            guard vistos.insert(curto.lowercased()).inserted else { return nil }
            return curto
        }.prefix(6))
    }

    static func dosTermos(_ ids: [String], em termos: [Termo]) -> DescricaoDaPeca {
        let dimensao = Dictionary(termos.map { ($0.id, $0.dimensao) }, uniquingKeysWith: { a, _ in a })
        var d = DescricaoDaPeca()
        for id in ids {
            switch dimensao[id] {
            case "categoria": d.categoria = d.categoria ?? id
            case "estampa": d.estampa = d.estampa ?? id
            case "comprimento": d.comprimento = d.comprimento ?? id
            case "silhueta": d.silhueta = d.silhueta ?? id
            case "cor": if !d.cores.contains(id) { d.cores.append(id) }
            case "tecido": if !d.tecidos.contains(id) { d.tecidos.append(id) }
            default: continue
            }
        }
        return d
    }

    /// O formato da análise de foto que a `ler-peca` aceita. Só os campos que
    /// ela lê; o que a peça não tem sai como "not_visible" ou lista vazia.
    var comoAnalise: [String: Any] {
        [
            "category": categoria ?? "not_visible",
            "pattern": estampa ?? "not_visible",
            "length": comprimento ?? "not_visible",
            "silhouette": silhueta ?? "not_visible",
            "colors": Array(cores.prefix(3)),
            "fabrics": Array(tecidos.prefix(3)),
            "additional_visual_attributes": Self.limparDetalhes(detalhes),
        ]
    }

    var vazia: Bool {
        categoria == nil && estampa == nil && comprimento == nil && silhueta == nil
            && cores.isEmpty && tecidos.isEmpty && detalhes.isEmpty
    }
}
