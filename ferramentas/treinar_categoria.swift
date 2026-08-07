#!/usr/bin/env swift
//
//  Treina o classificador de CATEGORIA no Create ML, com as imagens do painel,
//  e mede contra o portão da §28.
//
//  POR QUE ESTE E NÃO O DOS CENTROIDES
//  ===================================
//
//  A primeira tentativa comparou a foto com o CENTROIDE de cada termo — a média
//  dos vetores da Vision. Medido no i7 em 07/08: **49,6% em categoria** (136 de
//  274), contra o piso de 80% da §28. Há sinal (o acaso com 8 categorias daria
//  ~12,5%), e a regra é fraca: centroide assume que cada categoria é uma bolha
//  redonda em torno de um ponto, e roupa fotografada em modelo, manequim e
//  still não é isso.
//
//  A §28 já dizia o que fazer, e eu tinha lido metade do parágrafo: *"dataset a
//  partir das imagens do próprio coletor, rotuladas pelos títulos dos produtos
//  (títulos de e-commerce são etiquetas quase prontas). Treinar classificador
//  multirrótulo no Create ML."* É isso aqui.
//
//  Create ML aprende a FRONTEIRA entre as categorias em vez da média de cada
//  uma, o modelo sai com poucos MB, e é nosso — sem licença de terceiro, que
//  foi o que barrou o MobileCLIP.
//
//  UMA CATEGORIA POR PEÇA
//  ======================
//
//  A taxonomia é multirrótulo (uma peça é vestido E floral E midi), mas
//  CATEGORIA não: a peça é vestido OU calça. Peça que o matcher marcou com duas
//  categorias fica de fora do treino — é ambiguidade do título, não do produto,
//  e ensinar o modelo com ela é ensinar errado.
//
//  Rodar (no i7, nunca na máquina pessoal):
//      SUPABASE_URL=... SUPABASE_SECRET_KEY=... \
//      swift ferramentas/treinar_categoria.swift [--por-termo 400]

import Foundation
#if canImport(CreateML) && canImport(Vision)
import CreateML
import Vision
import CoreGraphics
import ImageIO
#else
#error("Precisa de CreateML: rode no Mac i7, nunca em Linux.")
#endif

let amb = ProcessInfo.processInfo.environment
guard let baseCrua = amb["SUPABASE_URL"], let chave = amb["SUPABASE_SECRET_KEY"] else {
    FileHandle.standardError.write(Data("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.\n".utf8))
    exit(1)
}
let base = baseCrua.hasPrefix("http") ? baseCrua : "https://\(baseCrua)"
let args = CommandLine.arguments
func inteiro(_ b: String, _ p: Int) -> Int {
    guard let i = args.firstIndex(of: b), i + 1 < args.count, let v = Int(args[i + 1])
    else { return p }
    return v
}
let porTermo = inteiro("--por-termo", 2000)

let UA = "CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)"
func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

// MARK: - Rede (regra 7: 1 req/s por domínio)

func pedirJSON(_ caminho: String) -> [[String: Any]] {
    var req = URLRequest(url: URL(string: base + "/rest/v1/" + caminho)!)
    req.setValue(chave, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
    let sem = DispatchSemaphore(value: 0)
    var saida: [[String: Any]] = []
    URLSession.shared.dataTask(with: req) { d, _, _ in
        defer { sem.signal() }
        if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            saida = j
        }
    }.resume()
    sem.wait()
    return saida
}

var ultimo: [String: Date] = [:]
/// Intervalo por dominio. Comeca no 1s da regra 7 e SOBE a cada 429: o
/// servidor pediu para diminuir, entao diminui. Na corrida de 07/08 eu contava
/// o 429 e seguia batendo na mesma cadencia -- 5.411 recusas em 10.702
/// tentativas. Isso nao e ineficiencia, e descumprir a regra 7.
var intervalo: [String: Double] = [:]
let tetoDoIntervalo = 30.0
let trava = NSLock()
var motivos: [String: Int] = [:]
let travaMotivos = NSLock()
func anotar(_ motivo: String) {
    travaMotivos.lock(); motivos[motivo, default: 0] += 1; travaMotivos.unlock()
}

func baixar(_ endereco: String) -> Data? {
    guard let url = URL(string: endereco), let host = url.host else {
        anotar("url invalida"); return nil
    }
    trava.lock()
    let meu = intervalo[host] ?? 1.0
    if let a = ultimo[host] {
        let espera = meu - Date().timeIntervalSince(a)
        if espera > 0 { Thread.sleep(forTimeInterval: espera) }
    }
    ultimo[host] = Date()
    trava.unlock()

    var req = URLRequest(url: url, timeoutInterval: 30)
    req.setValue(UA, forHTTPHeaderField: "User-Agent")
    let sem = DispatchSemaphore(value: 0)
    var saida: Data?
    URLSession.shared.dataTask(with: req) { d, r, e in
        defer { sem.signal() }
        if let e { anotar("rede: \(type(of: e))"); return }
        let codigo = (r as? HTTPURLResponse)?.statusCode ?? 0
        guard codigo == 200 else {
            anotar("HTTP \(codigo)")
            if codigo == 429 {
                // Dobra o intervalo deste dominio, ate o teto. Volta a 1s so
                // numa proxima execucao -- dentro da mesma, o servidor ja disse
                // o que achou do nosso ritmo.
                trava.lock()
                intervalo[host] = min(tetoDoIntervalo, (intervalo[host] ?? 1.0) * 2)
                trava.unlock()
            }
            return
        }
        guard let d, CGImageSourceCreateWithData(d as CFData, nil) != nil else {
            anotar("nao decodificou"); return
        }
        saida = d
    }.resume()
    sem.wait()
    return saida
}

// MARK: - Amostragem: uma categoria por peça

log("Lendo categorias...")
let categorias = pedirJSON("termos?status=eq.aprovado&dimensao=eq.categoria&select=id")
    .compactMap { $0["id"] as? String }.sorted()
log("Categorias: \(categorias.joined(separator: ", "))\n")

/// produto_id -> categorias que o título deu. Mais de uma = fora.
var porProduto: [Int: (categorias: Set<String>, imagem: String)] = [:]
for cat in categorias {
    // O PostgREST corta em 1000 linhas POR RESPOSTA e nao avisa. Pedir
    // `limit=2000` devolve 1000 caladamente -- foi assim que o coletor de
    // busca concluiu "36 termos sem serie" quando eram quatro. Pagina.
    var linhas: [[String: Any]] = []
    var deslocamento = 0
    while linhas.count < porTermo {
        let pedaco = min(1000, porTermo - linhas.count)
        let pagina = pedirJSON(
            "produto_termos?termo_id=eq.\(cat)&select=produto_id,produtos(imagem_url)"
            + "&produtos.imagem_url=not.is.null&order=produto_id"
            + "&limit=\(pedaco)&offset=\(deslocamento)")
        if pagina.isEmpty { break }
        linhas += pagina
        deslocamento += pagina.count
        if pagina.count < pedaco { break }
    }
    var n = 0
    for l in linhas {
        guard let pid = l["produto_id"] as? Int,
              let p = l["produtos"] as? [String: Any],
              let img = p["imagem_url"] as? String, !img.isEmpty else { continue }
        if var atual = porProduto[pid] {
            atual.categorias.insert(cat)
            porProduto[pid] = atual
        } else {
            porProduto[pid] = ([cat], img)
        }
        n += 1
    }
    log("  \(cat): \(n)")
}

let limpas = porProduto.filter { $0.value.categorias.count == 1 }
let ambiguas = porProduto.count - limpas.count
log("\nPeças com categoria única: \(limpas.count)  (descartadas por ambiguidade: \(ambiguas))")

// MARK: - Baixar em pastas por categoria

// CACHE QUE SOBREVIVE ENTRE EXECUCOES.
//
// As duas primeiras corridas baixaram ~8.100 imagens e jogaram todas fora: a
// pasta ficava em NSTemporaryDirectory e o runner limpa o workspace. Horas de
// regra 7 no lixo, e a terceira corrida recomecando do zero.
//
// Agora vive em $HOME, fora do workspace. Imagem ja baixada nao e pedida de
// novo -- o que tambem e a coisa educada a fazer com o servidor de quem nos
// deixa entrar.
let raiz = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("canario-imagens-treino")
for cat in categorias {
    try? FileManager.default.createDirectory(
        at: raiz.appendingPathComponent(cat), withIntermediateDirectories: true)
}

func jaTemos(_ cat: String, _ pid: Int) -> Bool {
    FileManager.default.fileExists(
        atPath: raiz.appendingPathComponent(cat)
            .appendingPathComponent("\(pid).jpg").path)
}

// ORCAMENTO DE TEMPO, PORQUE O JOB TEM TETO.
//
// A corrida de 07/08 foi cancelada aos 350 minutos no meio do download, e nao
// produziu numero nenhum -- so gastou o i7. Agora o download para sozinho e o
// treino roda com o que ha, sempre. Execucao seguinte continua de onde parou,
// porque o cache persiste.
// `--minutos-download 0` treina SO com o que ja esta em cache, sem uma
// requisicao sequer. E o experimento barato: responde "mais dado ajuda?" com o
// que ja foi pago, sem gastar o i7 nem incomodar servidor de ninguem.
let minutosDeDownload = Double(inteiro("--minutos-download", 180))
let prazo = Date().addingTimeInterval(minutosDeDownload * 60)

var baixadas = 0, falhas = 0, reaproveitadas = 0
var porCategoria: [String: Int] = [:]
var pararam = false
for (i, (pid, v)) in limpas.sorted(by: { $0.key < $1.key }).enumerated() {
    guard let cat = v.categorias.first else { continue }
    if jaTemos(cat, pid) { reaproveitadas += 1; porCategoria[cat, default: 0] += 1; continue }
    if Date() >= prazo {
        pararam = true
        log("\nOrcamento de \(Int(minutosDeDownload))min esgotado em \(i)/\(limpas.count). "
            + "Treinando com o que ha; a proxima execucao continua daqui.")
        break
    }
    if let dados = baixar(v.imagem) {
        try? dados.write(to: raiz.appendingPathComponent(cat)
                            .appendingPathComponent("\(pid).jpg"))
        baixadas += 1
        porCategoria[cat, default: 0] += 1
    } else {
        falhas += 1
    }
    if (i + 1) % 250 == 0 {
        log("  \(i + 1)/\(limpas.count)  novas=\(baixadas) cache=\(reaproveitadas) falhas=\(falhas)")
    }
}
log("\nBaixadas agora: \(baixadas) | reaproveitadas do cache: \(reaproveitadas) | falhas: \(falhas)")
if !motivos.isEmpty {
    log("Motivos das falhas:")
    for (m, n) in motivos.sorted(by: { $0.value > $1.value }) { log("  \(n)x  \(m)") }
}
if pararam { log("(download incompleto: rode de novo para continuar)") }
for cat in categorias { log("  \(cat): \(porCategoria[cat] ?? 0)") }

// Categoria com pouquíssima foto envenena a métrica: o modelo aprende a nunca
// responder aquela classe e a acurácia média sobe. Fica dito, não escondido.
let magras = categorias.filter { (porCategoria[$0] ?? 0) < 50 }
if !magras.isEmpty { log("\nATENCAO: menos de 50 imagens em: \(magras.joined(separator: ", "))") }

// MARK: - Treinar

log("\nTreinando (Create ML separa validação sozinho)...")
let fonte = MLImageClassifier.DataSource.labeledDirectories(at: raiz)
let modelo: MLImageClassifier
do {
    // 12 pontos entre treino (75,9%) e validacao (64,1%) na primeira corrida
    // sao falta de dado, nao teto do metodo. Aumento cobre parte disso sem
    // baixar uma imagem a mais: foto de produto varia em corte, enquadramento
    // e luz, e ensinar essa variacao e de graca.
    //
    // Sem `.flip`: peca de roupa tem lado (abotoamento, fenda, decote
    // assimetrico), e espelhar ensinaria que nao tem.
    var parametros = MLImageClassifier.ModelParameters()
    // Dois, e nao quatro. A corrida de 07/08 foi cancelada no teto do job
    // DURANTE o treino: cada aumento multiplica o conjunto, e um i7 sem GPU
    // decente nao da conta de quatro. `.crop` e `.exposure` sao os que
    // descrevem a variacao real de foto de produto -- enquadramento e luz.
    parametros.augmentationOptions = [.crop, .exposure]
    modelo = try MLImageClassifier(trainingData: fonte, parameters: parametros)
} catch {
    log("ERRO no treino: \(error)")
    exit(1)
}

let acuraciaTreino = 1.0 - modelo.trainingMetrics.classificationError
let acuraciaValidacao = 1.0 - modelo.validationMetrics.classificationError
// A §28 mede contra etiquetagem HUMANA. Aqui a etiqueta veio do título do
// produto, que a própria §28 chama de "etiqueta quase pronta" -- boa, e não
// humana. O portão de verdade continua sendo as 100 peças que o time rotula.
let passou = acuraciaValidacao >= 0.80

log("""

Portão da §28 — categoria
  treino:    \(String(format: "%.1f", acuraciaTreino * 100))%
  validação: \(String(format: "%.1f", acuraciaValidacao * 100))%
  piso:      80,0%
  passou:    \(passou ? "SIM" : "NÃO")

  (centroide da Vision, medido em 07/08, deu 49,6% — é a referência a bater)
""")

// MARK: - Escrever

if passou {
    let destino = URL(fileURLWithPath: "app/Canario/Recursos/CategoriaDaPeca.mlmodel")
    try? FileManager.default.createDirectory(
        at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? modelo.write(to: destino,
                      metadata: MLModelMetadata(
                        author: "Canario",
                        shortDescription: "Categoria da peça (§28). Treinado com imagens do "
                            + "painel rotuladas pelo título do produto.",
                        version: "1"))
    log("Escrito: \(destino.path)")
} else {
    // Modelo que não passou não entra no repositório: ele não seria usado (o
    // portão está no código) e ficaria parecendo pronto.
    log("Abaixo do piso: nada escrito. O app segue sem sugestão de categoria.")
}
