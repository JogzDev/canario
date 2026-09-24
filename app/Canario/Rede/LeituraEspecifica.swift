import Foundation

/// A leitura específica de uma peça (2.0), como a Edge Function `ler-peca`
/// devolve.
///
/// O servidor já fez o trabalho que importa: interpretou o pedido, buscou as
/// candidatas no painel publicado, verificou cada uma, calculou os fatos e
/// cortou toda frase com número sem prova. A tela só mostra -- e mostra a
/// prova: cada frase cita fatos, cada fato lista as peças que o sustentam.
struct LeituraEspecifica: Decodable {
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

    struct Frase: Decodable, Hashable {
        let texto: String
        let fatos: [String]
    }

    /// Só o que a tela usa de um fato: quantas peças e quais.
    struct Fato: Decodable {
        let pecas: Int?
        let provas: [Int]?
    }

    struct Peca: Decodable, Identifiable, Hashable {
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

    struct Pergunta: Decodable, Hashable {
        let pergunta: String
        let opcoes: [String]
    }

    struct Busca: Decodable {
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
