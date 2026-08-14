import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Pré-processador do benchmark Luna. Executa no Mac i7 e replica a mesma API
/// Vision usada no iPhone: escolhe a instância de primeiro plano mais forte,
/// apaga o fundo e grava PNG com transparência. Falha fechada: nenhuma imagem
/// bruta segue para a API quando a máscara não é útil.

struct Medida {
    let limites: CGRect
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

func medir(_ mascara: CVPixelBuffer) -> Medida? {
    CVPixelBufferLockBaseAddress(mascara, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(mascara, .readOnly) }
    guard CVPixelBufferGetPixelFormatType(mascara) == kCVPixelFormatType_OneComponent8,
          let base = CVPixelBufferGetBaseAddress(mascara) else { return nil }
    let largura = CVPixelBufferGetWidth(mascara)
    let altura = CVPixelBufferGetHeight(mascara)
    let passo = CVPixelBufferGetBytesPerRow(mascara)
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var minX = largura, minY = altura, maxX = -1, maxY = -1, ativos = 0
    for y in 0..<altura {
        for x in 0..<largura where bytes[y * passo + x] > 127 {
            ativos += 1
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    let cobertura = Double(ativos) / Double(max(1, largura * altura))
    guard cobertura >= 0.03, cobertura <= 0.95,
          maxX >= minX, maxY >= minY else { return nil }
    let limites = CGRect(x: minX, y: minY,
                         width: maxX - minX + 1, height: maxY - minY + 1)
    let centroX = Double(limites.midX) / Double(max(1, largura))
    let centroY = Double(limites.midY) / Double(max(1, altura))
    let distancia = hypot(centroX - 0.5, centroY - 0.5)
    return Medida(limites: limites,
                  pontuacao: cobertura - 0.04 * distancia)
}

func segmentar(_ imagem: CGImage) throws -> CGImage? {
    let pedido = VNGenerateForegroundInstanceMaskRequest()
    let manipulador = VNImageRequestHandler(cgImage: imagem)
    try manipulador.perform([pedido])
    guard let observacao = pedido.results?.first,
          !observacao.allInstances.isEmpty else { return nil }
    var melhor: (CVPixelBuffer, Medida)?
    for instancia in observacao.allInstances.prefix(16) {
        let mascara = try observacao.generateScaledMaskForImage(
            forInstances: IndexSet(integer: instancia), from: manipulador)
        guard let medida = medir(mascara) else { continue }
        if melhor == nil || medida.pontuacao > melhor!.1.pontuacao {
            melhor = (mascara, medida)
        }
    }
    guard let (mascara, medida) = melhor else { return nil }

    let original = CIImage(cgImage: imagem)
    let transparente = CIImage(color: .clear).cropped(to: original.extent)
    let filtro = CIFilter.blendWithMask()
    filtro.inputImage = original
    filtro.backgroundImage = transparente
    filtro.maskImage = CIImage(cvPixelBuffer: mascara)
    guard let composta = filtro.outputImage else { return nil }

    let alturaMascara = CGFloat(CVPixelBufferGetHeight(mascara))
    var recorte = CGRect(x: medida.limites.minX,
                         y: alturaMascara - medida.limites.maxY,
                         width: medida.limites.width,
                         height: medida.limites.height)
    let margem = max(recorte.width, recorte.height) * 0.05
    recorte = recorte.insetBy(dx: -margem, dy: -margem).intersection(original.extent)
    guard recorte.width > 8, recorte.height > 8 else { return nil }
    return CIContext(options: [.cacheIntermediates: false])
        .createCGImage(composta, from: recorte)
}

func gravarPNG(_ imagem: CGImage, em url: URL) -> Bool {
    guard let destino = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destino, imagem, [
        kCGImageDestinationLossyCompressionQuality: 1.0,
    ] as CFDictionary)
    return CGImageDestinationFinalize(destino)
}

guard CommandLine.arguments.count == 3 else {
    abortar("uso: segmentar_fundo <entrada> <saida.png>")
}
let entrada = URL(fileURLWithPath: CommandLine.arguments[1])
let saida = URL(fileURLWithPath: CommandLine.arguments[2])
guard let imagem = carregar(entrada) else { abortar("imagem_invalida") }
do {
    guard let recortada = try segmentar(imagem) else {
        abortar("primeiro_plano_nao_encontrado")
    }
    guard gravarPNG(recortada, em: saida) else { abortar("falha_ao_gravar_png") }
} catch {
    abortar("vision_falhou")
}
