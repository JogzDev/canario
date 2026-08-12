import Foundation
import ImageIO
import PDFKit
import UIKit

/// Cria a única cópia visual persistente autorizada pela A18.
///
/// A imagem é redesenhada num bitmap novo, limitada a 720 px e recodificada em
/// JPEG. Isso descarta EXIF, localização, nome original e demais metadados. O
/// resultado só é salvo quando o usuário confirma "Save to Closet".
enum MiniaturaLocal {
    static let ladoMaximo: CGFloat = 720

    /// Decodifica a orientação EXIF antes da análise. `CGImage` puro não aplica
    /// essa transformação e faria fotos verticais chegarem deitadas ao leitor.
    static func imagem(de dados: Data, ladoMaximo: Int = 2_400) -> CGImage? {
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, nil) else {
            return nil
        }
        let opcoes: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: ladoMaximo,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary)
    }

    static func jpeg(de imagem: CGImage) -> Data? {
        let largura = CGFloat(imagem.width)
        let altura = CGFloat(imagem.height)
        guard largura > 0, altura > 0 else { return nil }
        let escala = min(1, ladoMaximo / max(largura, altura))
        let tamanho = CGSize(width: max(1, (largura * escala).rounded()),
                             height: max(1, (altura * escala).rounded()))
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        let limpa = UIGraphicsImageRenderer(size: tamanho, format: formato).image { contexto in
            UIColor.white.setFill()
            contexto.fill(CGRect(origin: .zero, size: tamanho))
            UIImage(cgImage: imagem).draw(in: CGRect(origin: .zero, size: tamanho))
        }
        return limpa.jpegData(compressionQuality: 0.82)
    }

    static func jpeg(doArquivo url: URL) -> Data? {
        let precisaLiberar = url.startAccessingSecurityScopedResource()
        defer { if precisaLiberar { url.stopAccessingSecurityScopedResource() } }
        guard let dados = try? Data(contentsOf: url) else { return nil }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pagina = PDFDocument(data: dados)?.page(at: 0) else { return nil }
            let caixa = pagina.bounds(for: .mediaBox)
            guard caixa.width > 0, caixa.height > 0 else { return nil }
            let escala = ladoMaximo / max(caixa.width, caixa.height)
            let imagem = pagina.thumbnail(
                of: CGSize(width: caixa.width * escala, height: caixa.height * escala),
                for: .mediaBox)
            guard let cgImage = imagem.cgImage else { return nil }
            return jpeg(de: cgImage)
        }
        guard let imagem = imagem(de: dados) else { return nil }
        return jpeg(de: imagem)
    }
}
