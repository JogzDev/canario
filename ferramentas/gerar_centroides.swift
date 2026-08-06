#!/usr/bin/env swift
//
//  Gera `centroides_do_painel.json` a partir das imagens do painel, e MEDE o
//  portão da §28 antes de dizer que ele está aberto.
//
//  POR QUE ISTO NÃO RODA NO GITHUB ACTIONS
//  =======================================
//
//  Duas razões, e as duas são de fato:
//
//  1. `VNGenerateImageFeaturePrintRequest` só existe em plataforma Apple. O
//     runner do GitHub é Linux.
//  2. Os CDNs de imagem devolvem 429 para faixa de datacenter. A regra 7
//     proíbe contornar isso — o caminho é telefonar de um IP residencial, não
//     fingir ser outro.
//
//  Então roda no Mac i7, que é exatamente o que ele existe para fazer. Nunca
//  na máquina pessoal do JP.
//
//  Rodar:
//      SUPABASE_URL=... SUPABASE_SECRET_KEY=... \
//      swift ferramentas/gerar_centroides.swift [--por-termo 300]
//
//  O QUE ELE FAZ
//  =============
//
//  Amostra N produtos por termo, baixa a imagem no ritmo da regra 7, calcula o
//  vetor da Vision e separa em treino e aferição. Os centroides saem do treino;
//  a concordância sai da aferição, contra a etiqueta que o título do produto já
//  deu (a §28 chama isso de "etiquetas quase prontas", e é o mesmo matcher que
//  o app usa).
//
//  O ARTEFATO NASCE COM O PORTÃO FECHADO
//  =====================================
//
//  `passou` só vira `true` se a concordância medida em categoria E em cor ficar
//  em 0,80 ou acima, com pelo menos 100 peças aferidas — que é o texto da §28,
//  não uma escolha minha. Enquanto for `false`, o app não sugere nada: está
//  testado em `SemelhancaVisualTests`.
//
//  A §28 pede que o conjunto de 100 seja rotulado À MÃO pelo time. A medição
//  automática abaixo NÃO substitui isso: ela roda em milhares de peças e serve
//  para saber se vale a pena gastar o tempo de vocês rotulando. O campo
//  `aferido_por` diz qual das duas produziu o número.

import Foundation
#if canImport(Vision)
import Vision
import CoreGraphics
import ImageIO
#else
#error("Este gerador precisa de Vision: rode em macOS (o Mac i7), nunca em Linux.")
#endif

// MARK: - Configuração

let ambiente = ProcessInfo.processInfo.environment
guard let baseCrua = ambiente["SUPABASE_URL"],
      let chave = ambiente["SUPABASE_SECRET_KEY"] else {
    FileHandle.standardError.write(Data("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.\n".utf8))
    exit(1)
}
let base = baseCrua.hasPrefix("http") ? baseCrua : "https://\(baseCrua)"

let argumentos = CommandLine.arguments
func inteiro(_ bandeira: String, _ padrao: Int) -> Int {
    guard let i = argumentos.firstIndex(of: bandeira), i + 1 < argumentos.count,
          let v = Int(argumentos[i + 1]) else { return padrao }
    return v
}
/// Quantas peças por termo. 300 dá centroide estável sem virar madrugada
/// inteira: 40 termos x 300 = 12 mil imagens.
let porTermo = inteiro("--por-termo", 300)
/// Uma em cada quatro vai para a aferição, e nunca entra no centroide que ela
/// vai julgar.
let fracaoDeAfericao = 4

let UA = "CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)"
/// Regra 7: 1 requisição por segundo POR DOMÍNIO.
let intervaloPorDominio: TimeInterval = 1.0

// MARK: - Rede

func pedirJSON(_ caminho: String) -> [[String: Any]] {
    var componentes = URLComponents(string: base + "/rest/v1/" + caminho)!
    var req = URLRequest(url: componentes.url!)
    req.setValue(chave, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let semaforo = DispatchSemaphore(value: 0)
    var saida: [[String: Any]] = []
    URLSession.shared.dataTask(with: req) { dados, _, _ in
        defer { semaforo.signal() }
        guard let dados,
              let j = try? JSONSerialization.jsonObject(with: dados) as? [[String: Any]]
        else { return }
        saida = j
    }.resume()
    semaforo.wait()
    _ = componentes
    return saida
}

var ultimoAcesso: [String: Date] = [:]
let trava = NSLock()

func respeitarRitmo(_ dominio: String) {
    trava.lock()
    let agora = Date()
    if let anterior = ultimoAcesso[dominio] {
        let espera = intervaloPorDominio - agora.timeIntervalSince(anterior)
        if espera > 0 { Thread.sleep(forTimeInterval: espera) }
    }
    ultimoAcesso[dominio] = Date()
    trava.unlock()
}

func baixarImagem(_ endereco: String) -> CGImage? {
    guard let url = URL(string: endereco), let host = url.host else { return nil }
    respeitarRitmo(host)
    var req = URLRequest(url: url, timeoutInterval: 30)
    req.setValue(UA, forHTTPHeaderField: "User-Agent")
    let semaforo = DispatchSemaphore(value: 0)
    var imagem: CGImage?
    URLSession.shared.dataTask(with: req) { dados, resp, _ in
        defer { semaforo.signal() }
        guard let dados, (resp as? HTTPURLResponse)?.statusCode == 200,
              let fonte = CGImageSourceCreateWithData(dados as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(fonte, 0, nil) else { return }
        imagem = img
    }.resume()
    semaforo.wait()
    return imagem
}

// MARK: - Vision

func vetor(de imagem: CGImage) -> [Double]? {
    let pedido = VNGenerateImageFeaturePrintRequest()
    guard (try? VNImageRequestHandler(cgImage: imagem, options: [:]).perform([pedido])) != nil,
          let obs = pedido.results?.first as? VNFeaturePrintObservation else { return nil }
    let n = obs.elementCount
    var saida = [Double](repeating: 0, count: n)
    obs.data.withUnsafeBytes { bruto in
        let floats = bruto.bindMemory(to: Float.self)
        for i in 0..<min(n, floats.count) { saida[i] = Double(floats[i]) }
    }
    return saida
}

func cosseno(_ a: [Double], _ b: [Double]) -> Double? {
    guard a.count == b.count, !a.isEmpty else { return nil }
    var p = 0.0, na = 0.0, nb = 0.0
    for i in 0..<a.count { p += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    guard na > 0, nb > 0 else { return nil }
    return p / (na.squareRoot() * nb.squareRoot())
}

// MARK: - Amostragem

struct Peca {
    let produtoId: Int
    let imagem: String
    /// Todos os termos que o título deu para esta peça. Multirrótulo: uma peça
    /// é vestido E floral E midi ao mesmo tempo.
    var termos: [String: String] = [:]   // termo_id -> dimensao
}

FileHandle.standardError.write(Data("Lendo taxonomia e ligações...\n".utf8))

var dimensaoDoTermo: [String: String] = [:]
for t in pedirJSON("termos?status=eq.aprovado&select=id,dimensao") {
    if let id = t["id"] as? String, let d = t["dimensao"] as? String {
        dimensaoDoTermo[id] = d
    }
}

// Amostra POR TERMO, e não do catálogo inteiro: sem isso os termos comuns
// (`vestido`, `preto`) dominariam e os raros ficariam sem centroide.
var pecas: [Int: Peca] = [:]
for (termoId, dimensao) in dimensaoDoTermo.sorted(by: { $0.key < $1.key }) {
    let linhas = pedirJSON(
        "produto_termos?termo_id=eq.\(termoId)&select=produto_id,produtos(imagem_url)"
        + "&produtos.imagem_url=not.is.null&limit=\(porTermo)")
    var achados = 0
    for l in linhas {
        guard let pid = l["produto_id"] as? Int,
              let p = l["produtos"] as? [String: Any],
              let img = p["imagem_url"] as? String, !img.isEmpty else { continue }
        pecas[pid, default: Peca(produtoId: pid, imagem: img)].termos[termoId] = dimensao
        achados += 1
    }
    FileHandle.standardError.write(Data("  \(termoId): \(achados)\n".utf8))
}

let todas = pecas.values.sorted { $0.produtoId < $1.produtoId }
FileHandle.standardError.write(Data("Peças únicas a baixar: \(todas.count)\n".utf8))

// MARK: - Baixar e vetorizar

var vetores: [Int: [Double]] = [:]
var falhas = 0
for (i, peca) in todas.enumerated() {
    if let img = baixarImagem(peca.imagem), let v = vetor(de: img) {
        vetores[peca.produtoId] = v
    } else {
        falhas += 1
    }
    if (i + 1) % 200 == 0 {
        FileHandle.standardError.write(
            Data("  \(i + 1)/\(todas.count)  (\(falhas) falhas)\n".utf8))
    }
}
FileHandle.standardError.write(
    Data("Vetorizadas: \(vetores.count), falhas: \(falhas)\n".utf8))

guard let dimensoes = vetores.values.first?.count else {
    FileHandle.standardError.write(Data("ERRO: nenhuma imagem virou vetor.\n".utf8))
    exit(1)
}

// MARK: - Treino e aferição

// A divisão é pelo id, e não aleatória: rodar duas vezes tem que dar a mesma
// divisão, senão a concordância medida não é comparável entre execuções.
let treino = todas.filter { vetores[$0.produtoId] != nil && $0.produtoId % fracaoDeAfericao != 0 }
let afericao = todas.filter { vetores[$0.produtoId] != nil && $0.produtoId % fracaoDeAfericao == 0 }

var soma: [String: [Double]] = [:]
var quantos: [String: Int] = [:]
for peca in treino {
    guard let v = vetores[peca.produtoId] else { continue }
    for termoId in peca.termos.keys {
        if soma[termoId] == nil { soma[termoId] = [Double](repeating: 0, count: dimensoes) }
        for i in 0..<dimensoes { soma[termoId]![i] += v[i] }
        quantos[termoId, default: 0] += 1
    }
}

struct CentroideSaida { let termoId: String; let dimensao: String
                        let nImagens: Int; let vetor: [Double] }
let centroides: [CentroideSaida] = soma.keys.sorted().compactMap { termoId in
    guard let n = quantos[termoId], n > 0, let s = soma[termoId],
          let dim = dimensaoDoTermo[termoId] else { return nil }
    return CentroideSaida(termoId: termoId, dimensao: dim, nImagens: n,
                          vetor: s.map { $0 / Double(n) })
}

// MARK: - Medir o portão da §28

/// Concordância numa dimensão: o termo mais parecido daquela dimensão está
/// entre os que o título deu para a peça?
func concordancia(naDimensao dim: String) -> (acertos: Int, avaliadas: Int) {
    let daDimensao = centroides.filter { $0.dimensao == dim }
    guard !daDimensao.isEmpty else { return (0, 0) }
    var acertos = 0, avaliadas = 0
    for peca in afericao {
        let esperados = Set(peca.termos.filter { $0.value == dim }.keys)
        guard !esperados.isEmpty, let v = vetores[peca.produtoId] else { continue }
        avaliadas += 1
        var melhor: (String, Double)?
        for c in daDimensao {
            if let s = cosseno(v, c.vetor), melhor == nil || s > melhor!.1 {
                melhor = (c.termoId, s)
            }
        }
        if let m = melhor, esperados.contains(m.0) { acertos += 1 }
    }
    return (acertos, avaliadas)
}

let categoria = concordancia(naDimensao: "peca")
let cor = concordancia(naDimensao: "cor")
let taxaCategoria = categoria.avaliadas > 0
    ? Double(categoria.acertos) / Double(categoria.avaliadas) : 0
let taxaCor = cor.avaliadas > 0 ? Double(cor.acertos) / Double(cor.avaliadas) : 0
let avaliadas = min(categoria.avaliadas, cor.avaliadas)

// O texto da §28, e não uma escolha minha: ≥ 80% em categoria E em cor.
let passou = taxaCategoria >= 0.80 && taxaCor >= 0.80 && avaliadas >= 100

FileHandle.standardError.write(Data("""

Portão da §28
  categoria: \(String(format: "%.1f", taxaCategoria * 100))% \
(\(categoria.acertos)/\(categoria.avaliadas))
  cor:       \(String(format: "%.1f", taxaCor * 100))% (\(cor.acertos)/\(cor.avaliadas))
  passou:    \(passou ? "SIM" : "NÃO")

""".utf8))

// MARK: - Escrever

let formatador = DateFormatter()
formatador.dateFormat = "yyyy-MM-dd"

var saida: [String: Any] = [
    "versao": 1,
    "gerado_em": formatador.string(from: Date()),
    "dimensoes": dimensoes,
    "portao_28": [
        "concordancia_categoria": taxaCategoria,
        "concordancia_cor": taxaCor,
        "n_pecas_avaliadas": avaliadas,
        "passou": passou,
        // A §28 pede 100 peças rotuladas À MÃO pelo time. Este número saiu do
        // título do produto, que é etiqueta boa mas não é humana. Fica dito.
        "aferido_por": "titulo_do_produto (automatico); a §28 pede 100 rotuladas a mao pelo time",
    ],
    "centroides": centroides.map {
        ["termo_id": $0.termoId, "dimensao": $0.dimensao,
         "n_imagens": $0.nImagens, "vetor": $0.vetor] as [String: Any]
    },
]

let destino = "app/Canario/Recursos/centroides_do_painel.json"
try? FileManager.default.createDirectory(
    atPath: "app/Canario/Recursos", withIntermediateDirectories: true)
let dados = try JSONSerialization.data(withJSONObject: saida, options: [.sortedKeys])
try dados.write(to: URL(fileURLWithPath: destino))

FileHandle.standardError.write(Data("""
Escrito: \(destino)
  \(centroides.count) centroides, \(dimensoes) dimensões, \
\(ByteCountFormatter.string(fromByteCount: Int64(dados.count), countStyle: .file))

""".utf8))
