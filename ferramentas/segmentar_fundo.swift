import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Pré-processador do benchmark Luna. O i7 possui um SDK anterior ao request de
/// instâncias usado no iPhone, então aqui usamos a máscara de saliência do
/// Vision, disponível desde macOS 10.15. Ela remove o fundo antes da inferência
/// e mantém o mesmo princípio de falha fechada: nenhuma imagem bruta segue para
/// a API quando a máscara não é útil.

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
    let largura = CVPixelBufferGetWidth(mascara)
    let altura = CVPixelBufferGetHeight(mascara)
    let imagemCI = CIImage(cvPixelBuffer: mascara)
    let contextoCI = CIContext(options: [.cacheIntermediates: false])
    guard let imagemCG = contextoCI.createCGImage(imagemCI, from: imagemCI.extent)
    else { return nil }
    var bytes = [UInt8](repeating: 0, count: largura * altura * 4)
    let espaco = CGColorSpaceCreateDeviceRGB()
    guard let contexto = CGContext(
        data: &bytes,
        width: largura,
        height: altura,
        bitsPerComponent: 8,
        bytesPerRow: largura * 4,
        space: espaco,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    contexto.draw(imagemCG, in: CGRect(x: 0, y: 0, width: largura, height: altura))
    var minX = largura, minY = altura, maxX = -1, maxY = -1, ativos = 0
    for y in 0..<altura {
        for x in 0..<largura where bytes[(y * largura + x) * 4] > 32 {
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
    let pedido = VNGenerateAttentionBasedSaliencyImageRequest()
    let manipulador = VNImageRequestHandler(cgImage: imagem)
    try manipulador.perform([pedido])
    guard let observacao = pedido.results?.first else { return nil }
    let mascara = observacao.pixelBuffer
    guard let medida = medir(mascara) else { return nil }

    let original = CIImage(cgImage: imagem)
    let transparente = CIImage(color: .clear).cropped(to: original.extent)
    let mascaraPequena = CIImage(cvPixelBuffer: mascara)
    let escalaX = original.extent.width / mascaraPequena.extent.width
    let escalaY = original.extent.height / mascaraPequena.extent.height
    let mascaraEscalada = mascaraPequena
        .transformed(by: CGAffineTransform(scaleX: escalaX, y: escalaY))
        .applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 3.5,
            kCIInputBrightnessKey: -0.12,
        ])
        .cropped(to: original.extent)
    let filtro = CIFilter.blendWithMask()
    filtro.inputImage = original
    filtro.backgroundImage = transparente
    filtro.maskImage = mascaraEscalada
    guard let composta = filtro.outputImage else { return nil }

    let alturaMascara = CGFloat(CVPixelBufferGetHeight(mascara))
    var recorte = CGRect(
        x: medida.limites.minX * escalaX,
        y: (alturaMascara - medida.limites.maxY) * escalaY,
        width: medida.limites.width * escalaX,
        height: medida.limites.height * escalaY)
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
