import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import PDFKit
import UIKit
import Vision

/// Cria a única cópia visual persistente autorizada pela A18.
///
/// A imagem é redesenhada num bitmap novo, limitada a 720 px e recodificada.
/// Quando o Vision encontra um primeiro plano confiável, ele vira PNG com
/// transparência; caso contrário, cai no JPEG seguro já existente. Nos dois
/// casos são descartados EXIF, localização, nome original e demais metadados.
/// O resultado só é salvo quando o usuário confirma "Save to Closet".
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

    /// Gera a prévia persistível. O recorte é deliberadamente conservador:
    /// máscara quase vazia ou que cobre praticamente a foto inteira não é
    /// aceita, porque apagar uma parte da roupa é pior que manter o fundo.
    static func dados(de imagem: CGImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            if let recortada = recortarPrimeiroPlano(imagem) {
                return redesenhar(recortada, transparente: true)?.pngData()
            }
            return redesenhar(imagem, transparente: false)?
                .jpegData(compressionQuality: 0.82)
        }.value
    }

    private static func redesenhar(_ imagem: CGImage,
                                   transparente: Bool) -> UIImage? {
        let largura = CGFloat(imagem.width)
        let altura = CGFloat(imagem.height)
        guard largura > 0, altura > 0 else { return nil }
        let escala = min(1, ladoMaximo / max(largura, altura))
        let tamanho = CGSize(width: max(1, (largura * escala).rounded()),
                             height: max(1, (altura * escala).rounded()))
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = !transparente
        let limpa = UIGraphicsImageRenderer(size: tamanho, format: formato).image { contexto in
            if transparente {
                contexto.cgContext.clear(CGRect(origin: .zero, size: tamanho))
            } else {
                UIColor.white.setFill()
                contexto.fill(CGRect(origin: .zero, size: tamanho))
            }
            UIImage(cgImage: imagem).draw(in: CGRect(origin: .zero, size: tamanho))
        }
        return limpa
    }

    static func dados(doArquivo url: URL) async -> Data? {
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
            return await self.dados(de: cgImage)
        }
        guard let imagem = imagem(de: dados) else { return nil }
        return await self.dados(de: imagem)
    }

    /// `VNGenerateForegroundInstanceMaskRequest` é local e está disponível no
    /// iOS 17. Ele separa sujeito e fundo; não tenta adivinhar o SKU numa foto
    /// com várias roupas. Essa decisão semântica continua pertencendo à etapa
    /// de visão e ao usuário.
    private static func recortarPrimeiroPlano(_ imagem: CGImage) -> CGImage? {
        let pedido = VNGenerateForegroundInstanceMaskRequest()
        let manipulador = VNImageRequestHandler(cgImage: imagem)
        do {
            try manipulador.perform([pedido])
            guard let observacao = pedido.results?.first,
                  !observacao.allInstances.isEmpty else { return nil }
            // Peça sobre mesa/cabide costuma ser uma instância própria. Usar
            // todas preservaria também mão, prop e objeto de cenário. A maior
            // instância plausível vira o alvo; em foto vestida o Vision pode
            // considerar a pessoa inteira uma instância, limite que a tela de
            // captura precisa declarar em vez de fingir uma segmentação de SKU.
            var escolhida: (mascara: CVPixelBuffer, medida: MedidaDaMascara)?
            for instancia in observacao.allInstances.prefix(16) {
                let mascara = try observacao.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: instancia), from: manipulador)
                guard let medida = medidaUtil(da: mascara) else { continue }
                if escolhida == nil || medida.pontuacao > escolhida!.medida.pontuacao {
                    escolhida = (mascara, medida)
                }
            }
            guard let (mascara, medida) = escolhida else { return nil }
            let limites = medida.limites

            let original = CIImage(cgImage: imagem)
            let mask = CIImage(cvPixelBuffer: mascara)
            let transparente = CIImage(color: .clear).cropped(to: original.extent)
            let filtro = CIFilter.blendWithMask()
            filtro.inputImage = original
            filtro.backgroundImage = transparente
            filtro.maskImage = mask
            guard let composta = filtro.outputImage else { return nil }

            // O pixel buffer tem origem no topo; Core Image, embaixo.
            let altura = CGFloat(CVPixelBufferGetHeight(mascara))
            var recorte = CGRect(x: limites.minX,
                                 y: altura - limites.maxY,
                                 width: limites.width,
                                 height: limites.height)
            let margem = max(recorte.width, recorte.height) * 0.05
            recorte = recorte.insetBy(dx: -margem, dy: -margem)
                .intersection(original.extent)
            guard recorte.width > 1, recorte.height > 1 else { return nil }
            return CIContext(options: [.cacheIntermediates: false])
                .createCGImage(composta, from: recorte)
        } catch {
            return nil
        }
    }

    /// Bounding box e cobertura da máscara. Entre 3% e 95%: abaixo disso a
    /// detecção é ruído; acima disso ela não removeu fundo de forma útil.
    private struct MedidaDaMascara {
        let limites: CGRect
        let pontuacao: Double
    }

    private static func medidaUtil(da mascara: CVPixelBuffer) -> MedidaDaMascara? {
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
        guard cobertura >= 0.03, cobertura <= 0.95, maxX >= minX, maxY >= minY else {
            return nil
        }
        let limites = CGRect(x: minX, y: minY,
                             width: maxX - minX + 1, height: maxY - minY + 1)
        // Área ativa domina; uma pequena preferência pelo centro desempata
        // prop grande na borda sem derrubar roupa propositalmente assimétrica.
        let centroX = Double(limites.midX) / Double(max(1, largura))
        let centroY = Double(limites.midY) / Double(max(1, altura))
        let distancia = hypot(centroX - 0.5, centroY - 0.5)
        return MedidaDaMascara(limites: limites,
                               pontuacao: cobertura - 0.04 * distancia)
    }
}
