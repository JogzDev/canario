import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Pré-processador do benchmark Luna: isola a peça e descarta o fundo antes da
/// inferência.
///
/// Usa `VNGenerateForegroundInstanceMaskRequest`, o mesmo pedido do app, para
/// que o benchmark meça a imagem que o iPhone realmente enviaria. A versão
/// anterior usava a saliência de atenção, que é um mapa de 68x68 treinado para
/// achar *onde o olho pousa* — numa foto de moda isso é o rosto, não a roupa.
///
/// Três garantias explícitas:
/// 1. A saída é opaca sobre branco. Transparência vira preto em API de visão, e
///    foi assim que o benchmark de 300 mediu retângulos pretos.
/// 2. A saída é conferida antes de gravar: máscara vazia, quase total ou recorte
///    minúsculo abortam. Nenhuma imagem crua sai daqui disfarçada de recorte.
/// 3. Sem SDK com máscara de instância o programa aborta; não cai em saliência.

let coberturaMinima = 0.06
let coberturaMaxima = 0.98
let ladoMinimo = 64
let margemDoRecorte = 0.05
let limiarDaMascara: Float = 0.5

struct Mascara {
    let valores: [Float]
    let largura: Int
    let altura: Int
}

struct Medida {
    let minX: Int, minY: Int, maxX: Int, maxY: Int
    let cobertura: Double
    let pontuacao: Double
}

func abortar(_ mensagem: String) -> Never {
    FileHandle.standardError.write(Data((mensagem + "\n").utf8))
    exit(1)
}

func carregar(_ url: URL) -> CGImage? {
    guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opcoes: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 2_400,
        kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary)
}

/// Lê o buffer da máscara em `[0,1]`, aceitando os dois formatos que o Vision
/// devolve conforme a versão do sistema. Formato desconhecido não é tratado
/// como máscara vazia: é erro, para não virar um falso "sem primeiro plano".
func lerMascara(_ buffer: CVPixelBuffer) -> Mascara? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let largura = CVPixelBufferGetWidth(buffer)
    let altura = CVPixelBufferGetHeight(buffer)
    let passo = CVPixelBufferGetBytesPerRow(buffer)
    let formato = CVPixelBufferGetPixelFormatType(buffer)
    var valores = [Float](repeating: 0, count: largura * altura)

    switch formato {
    case kCVPixelFormatType_OneComponent8:
        for y in 0..<altura {
            let linha = base.advanced(by: y * passo).assumingMemoryBound(to: UInt8.self)
            for x in 0..<largura {
                valores[y * largura + x] = Float(linha[x]) / 255
            }
        }
    case kCVPixelFormatType_OneComponent32Float:
        for y in 0..<altura {
            let linha = base.advanced(by: y * passo).assumingMemoryBound(to: Float.self)
            for x in 0..<largura {
                valores[y * largura + x] = linha[x]
            }
        }
    default:
        return nil
    }
    return Mascara(valores: valores, largura: largura, altura: altura)
}

func medir(_ mascara: Mascara) -> Medida? {
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    var ativos = 0
    for y in 0..<mascara.altura {
        for x in 0..<mascara.largura
        where mascara.valores[y * mascara.largura + x] >= limiarDaMascara {
            ativos += 1
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    let cobertura = Double(ativos) / Double(max(1, mascara.largura * mascara.altura))
    // Área manda; a centralidade só desempata instância grande encostada na
    // borda contra peça deliberadamente assimétrica.
    let centroX = Double(minX + maxX) / 2 / Double(max(1, mascara.largura))
    let centroY = Double(minY + maxY) / 2 / Double(max(1, mascara.altura))
    let distancia = hypot(centroX - 0.5, centroY - 0.5)
    return Medida(minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                  cobertura: cobertura, pontuacao: cobertura - 0.04 * distancia)
}

/// Desenha num RGBA8 conhecido em vez de confiar no espaço de cor que o
/// Core Image escolheria; o índice do pixel passa a bater com o da máscara.
func pixels(de imagem: CGImage) -> [UInt8]? {
    let largura = imagem.width, altura = imagem.height
    var bytes = [UInt8](repeating: 0, count: largura * altura * 4)
    guard let contexto = CGContext(
        data: &bytes, width: largura, height: altura,
        bitsPerComponent: 8, bytesPerRow: largura * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    contexto.draw(imagem, in: CGRect(x: 0, y: 0, width: largura, height: altura))
    return bytes
}

/// Compõe a peça sobre branco e recorta. Branco opaco em vez de alfa: o destino
/// é uma API de visão, e PNG transparente chega lá achatado sobre preto.
func compor(_ imagem: CGImage, _ mascara: Mascara, _ medida: Medida)
    -> (imagem: CGImage, cobertura: Double, luz: Double)? {
    guard let origem = pixels(de: imagem) else { return nil }
    let largura = imagem.width, altura = imagem.height
    guard mascara.largura == largura, mascara.altura == altura else { return nil }

    let margem = Int((Double(max(medida.maxX - medida.minX, medida.maxY - medida.minY))
        * margemDoRecorte).rounded())
    let x0 = max(0, medida.minX - margem), x1 = min(largura - 1, medida.maxX + margem)
    let y0 = max(0, medida.minY - margem), y1 = min(altura - 1, medida.maxY + margem)
    let larguraSaida = x1 - x0 + 1, alturaSaida = y1 - y0 + 1
    guard larguraSaida >= ladoMinimo, alturaSaida >= ladoMinimo else { return nil }

    var saida = [UInt8](repeating: 255, count: larguraSaida * alturaSaida * 4)
    var somaLuz = 0.0
    var opacos = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let alfa = Double(min(1, max(0, mascara.valores[y * largura + x])))
            let entrada = (y * largura + x) * 4
            let destino = ((y - y0) * larguraSaida + (x - x0)) * 4
            var canais = [Double](repeating: 0, count: 3)
            for c in 0..<3 {
                let peca = Double(origem[entrada + c])
                canais[c] = peca * alfa + 255 * (1 - alfa)
                saida[destino + c] = UInt8(min(255, max(0, canais[c].rounded())))
            }
            saida[destino + 3] = 255
            if alfa >= Double(limiarDaMascara) {
                opacos += 1
                somaLuz += 0.299 * Double(origem[entrada])
                    + 0.587 * Double(origem[entrada + 1])
                    + 0.114 * Double(origem[entrada + 2])
            }
        }
    }
    let cobertura = Double(opacos) / Double(larguraSaida * alturaSaida)
    let luz = opacos > 0 ? somaLuz / Double(opacos) : 0

    let dados = CFDataCreate(nil, saida, saida.count)!
    guard let provedor = CGDataProvider(data: dados),
          let composta = CGImage(
            width: larguraSaida, height: alturaSaida,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: larguraSaida * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provedor, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent) else { return nil }
    return (composta, cobertura, luz)
}

func segmentar(_ imagem: CGImage) throws -> (CGImage, String)? {
    guard #available(macOS 14.0, *) else {
        abortar("sdk_sem_mascara_de_instancia")
    }
    let pedido = VNGenerateForegroundInstanceMaskRequest()
    let manipulador = VNImageRequestHandler(cgImage: imagem)
    try manipulador.perform([pedido])
    guard let observacao = pedido.results?.first,
          !observacao.allInstances.isEmpty else { return nil }

    var candidatas: [(Mascara, Medida)] = []
    for instancia in observacao.allInstances.prefix(16) {
        let buffer = try observacao.generateScaledMaskForImage(
            forInstances: IndexSet(integer: instancia), from: manipulador)
        guard let mascara = lerMascara(buffer) else {
            abortar("formato_de_mascara_desconhecido")
        }
        guard let medida = medir(mascara),
              medida.cobertura >= coberturaMinima,
              medida.cobertura <= coberturaMaxima else { continue }
        candidatas.append((mascara, medida))
    }
    guard let melhor = candidatas.max(by: { $0.1.pontuacao < $1.1.pontuacao }) else {
        return nil
    }
    guard let composta = compor(imagem, melhor.0, melhor.1) else { return nil }

    // Confere a saída, não a máscara: é a imagem gravada que segue para a API.
    guard composta.cobertura >= coberturaMinima, composta.cobertura <= coberturaMaxima
    else { return nil }
    let diagnostico = String(
        format: "{\"instancias\":%d,\"cobertura\":%.4f,\"luz\":%.1f,\"dims\":\"%dx%d\"}",
        observacao.allInstances.count, composta.cobertura, composta.luz,
        composta.imagem.width, composta.imagem.height)
    return (composta.imagem, diagnostico)
}

func gravarPNG(_ imagem: CGImage, em url: URL) -> Bool {
    guard let destino = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destino, imagem, nil)
    return CGImageDestinationFinalize(destino)
}

guard CommandLine.arguments.count == 3 else {
    abortar("uso: segmentar_fundo <entrada> <saida.png>")
}
let entrada = URL(fileURLWithPath: CommandLine.arguments[1])
let saida = URL(fileURLWithPath: CommandLine.arguments[2])
guard let imagem = carregar(entrada) else { abortar("imagem_invalida") }
do {
    guard let (recortada, diagnostico) = try segmentar(imagem) else {
        abortar("primeiro_plano_nao_encontrado")
    }
    guard gravarPNG(recortada, em: saida) else { abortar("falha_ao_gravar_png") }
    FileHandle.standardOutput.write(Data((diagnostico + "\n").utf8))
} catch {
    abortar("vision_falhou")
}
