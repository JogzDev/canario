// Benchmark de foto: os modelos da Apple com o MESMO contrato da Luna.
//
// Roda no Mac (macOS 27+), fora do CI: o modelo da Apple vive no aparelho.
//
//   python3 ferramentas/benchmark_foto/luna.py --so-instrucoes /tmp/instrucoes.txt
//   xcrun swiftc -O ferramentas/benchmark_foto/apple.swift -o /tmp/apple
//   /tmp/apple /tmp/instrucoes.txt locais.json aparelho saida.jsonl
//
// `locais.json` e uma lista [{"id": ..., "arquivo": ...}] com as fotos do
// manifesto ja baixadas. Cada linha da saida traz a resposta crua (o mesmo
// JSON que a Luna devolve), o tempo e o erro. As instrucoes e o esquema sao
// os da Edge Function; o esquema abaixo repete as listas do `index.ts`.
//
// A nuvem privada (`nuvem`) responde "disponivel" neste Mac mas recusa a
// chamada (ModelManagerError 1046) num binario sem a permissao que a Apple
// concede na inscricao do app: fica fora ate a inscricao.
import Foundation
import FoundationModels

struct Entrada: Decodable { let id: String; let arquivo: String }
struct Linha: Encodable {
    let id: String
    let modelo: String
    let segundos: Double
    let resposta: String?
    let erro: String?
}

let argumentos = CommandLine.arguments
guard argumentos.count == 5 else {
    FileHandle.standardError.write("uso: apple <instrucoes> <manifesto> <aparelho|nuvem> <saida>\n".data(using: .utf8)!)
    exit(2)
}
let instrucoes = try String(contentsOfFile: argumentos[1], encoding: .utf8)
let entradas = try JSONDecoder().decode([Entrada].self,
                                        from: Data(contentsOf: URL(fileURLWithPath: argumentos[2])))
let qual = argumentos[3]
let saida = URL(fileURLWithPath: argumentos[4])

let estruturas = ["one_piece_no_separate_legs", "one_piece_with_separate_legs",
                  "lower_continuous_panel", "lower_two_legs_short", "lower_two_legs_long",
                  "upper_shirt_construction", "upper_outer_layer", "upper_other",
                  "target_not_determinable"]
let ids: [String: [String]] = [
    "estampa": ["liso", "floral", "listra", "animal_print", "xadrez", "geometrica", "conversacional"],
    "tecido": ["algodao", "linho", "jeans", "couro", "malha", "trico_croche", "viscose_fluido"],
    "comprimento": ["curto", "midi", "longo"],
    "silhueta": ["flare", "reta_wide"],
    "cintura": ["cintura_alta", "cintura_media", "cintura_baixa"],
    "estetica": ["basico", "romantico", "boho_artesanal", "alfaiataria", "festa_brilho"],
    "cor": ["preto", "branco_cru", "cinza", "azul", "verde", "lilas_roxo", "vermelho_rosa",
            "amarelo_laranja", "terrosos", "outras_cores"],
]

func escolha(_ nome: String, _ valores: [String]) -> DynamicGenerationSchema {
    DynamicGenerationSchema(name: nome, anyOf: valores)
}
func lista(_ item: DynamicGenerationSchema, max: Int, min: Int? = nil) -> DynamicGenerationSchema {
    DynamicGenerationSchema(arrayOf: item, minimumElements: min, maximumElements: max)
}
let texto = DynamicGenerationSchema(type: String.self)
let raiz = DynamicGenerationSchema(name: "canario_clothing_analysis", properties: [
    .init(name: "target_clarity", schema: escolha("target_clarity",
          ["clear", "partially_occluded", "multiple_garments_target_clear", "ambiguous_target"])),
    .init(name: "garment_structure", schema: escolha("garment_structure", estruturas)),
    .init(name: "decision_evidence", schema: lista(texto, max: 4, min: 1)),
    .init(name: "pattern", schema: escolha("pattern", ["not_visible"] + ids["estampa"]!)),
    .init(name: "fabrics", schema: lista(escolha("fabric", ids["tecido"]!), max: 3)),
    .init(name: "length", schema: escolha("length", ["not_visible"] + ids["comprimento"]!)),
    .init(name: "silhouette", schema: escolha("silhouette", ["not_visible"] + ids["silhueta"]!)),
    .init(name: "waist", schema: escolha("waist", ["not_visible"] + ids["cintura"]!)),
    .init(name: "aesthetics", schema: lista(escolha("aesthetic", ids["estetica"]!), max: 3)),
    .init(name: "colors", schema: lista(escolha("color", ids["cor"]!), max: 3)),
    .init(name: "additional_visual_attributes", schema: lista(texto, max: 5)),
])
let esquema = try GenerationSchema(root: raiz, dependencies: [])
let pedido = "Determine whether one target garment is visually identifiable, then analyze it under the contract."

func sessao() -> LanguageModelSession {
    if qual == "nuvem" {
        return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instrucoes)
    }
    return LanguageModelSession(model: SystemLanguageModel.default, instructions: instrucoes)
}

if qual == "nuvem" {
    let nuvem = PrivateCloudComputeLanguageModel()
    print("nuvem privada:", nuvem.availability)
    guard nuvem.isAvailable else { exit(3) }
} else {
    print("aparelho:", SystemLanguageModel.default.availability)
}

FileManager.default.createFile(atPath: saida.path, contents: nil)
let escritor = try FileHandle(forWritingTo: saida)
let codificador = JSONEncoder()
for (n, entrada) in entradas.enumerated() {
    let inicio = Date()
    var resposta: String?
    var erro: String?
    do {
        // Uma sessao por foto: nada de uma leitura contaminar a seguinte.
        let r = try await sessao().respond(
            to: Prompt { pedido; Attachment(imageURL: URL(fileURLWithPath: entrada.arquivo)) },
            schema: esquema)
        resposta = r.content.jsonString
    } catch {
        erro = String(describing: error)
    }
    let linha = Linha(id: entrada.id, modelo: qual == "nuvem" ? "apple-pcc" : "apple-aparelho",
                      segundos: Date().timeIntervalSince(inicio), resposta: resposta, erro: erro)
    escritor.write(try codificador.encode(linha))
    escritor.write("\n".data(using: .utf8)!)
    print(n + 1, entrada.id, erro == nil ? "ok" : "erro", String(format: "%.1fs", linha.segundos))
}
try escritor.close()
