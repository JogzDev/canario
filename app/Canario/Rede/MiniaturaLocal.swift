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

    /// Uma escolha visual apresentada antes da leitura da peça. `dados` já é
    /// uma imagem nova, sem EXIF, localização ou nome do arquivo original.
    /// A foto completa sempre fecha a lista como saída segura quando o Vision
    /// separou a pessoa, um acessório ou outra instância que não era a roupa.
    struct OpcaoDeAlvo: Identifiable {
        enum Tipo: Equatable {
            case primeiroPlano
            case fotoCompleta
        }

        let id: Int
        let dados: Data
        let tipo: Tipo

        var rotulo: String {
            switch tipo {
            case .primeiroPlano: return "Isolated item \(id + 1)"
            case .fotoCompleta: return "Full photo"
            }
        }
    }

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

    /// Prepara as alternativas para a confirmação humana, ainda no aparelho.
    /// Não tenta dizer qual instância é uma roupa: ordena as máscaras mais
    /// plausíveis e deixa essa decisão semântica para quem tirou a foto.
    static func opcoesDeAlvo(de imagem: CGImage) async -> [OpcaoDeAlvo] {
        await Task.detached(priority: .userInitiated) {
            var opcoes = recortesDePrimeiroPlano(imagem)
                .prefix(4)
                .enumerated()
                .compactMap { indice, recorte -> OpcaoDeAlvo? in
                    guard let dados = redesenhar(recorte, transparente: true)?.pngData() else {
                        return nil
                    }
                    return OpcaoDeAlvo(id: indice, dados: dados, tipo: .primeiroPlano)
                }

            if let completa = redesenhar(imagem, transparente: false)?
                .jpegData(compressionQuality: 0.82) {
                opcoes.append(OpcaoDeAlvo(id: opcoes.count,
                                          dados: completa,
                                          tipo: .fotoCompleta))
            }
            return opcoes
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
        recortesDePrimeiroPlano(imagem).first
    }

    /// Devolve instâncias úteis em ordem de área/centralidade. O limite de
    /// quatro mantém a decisão rápida e evita expor ruído minúsculo do cenário.
    private static func recortesDePrimeiroPlano(_ imagem: CGImage) -> [CGImage] {
        let pedido = VNGenerateForegroundInstanceMaskRequest()
        let manipulador = VNImageRequestHandler(cgImage: imagem)
        do {
            try manipulador.perform([pedido])
            guard let observacao = pedido.results?.first,
                  !observacao.allInstances.isEmpty else { return [] }
            var candidatas: [(mascara: CVPixelBuffer, medida: MedidaDaMascara)] = []
            for instancia in observacao.allInstances.prefix(16) {
                let mascara = try observacao.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: instancia), from: manipulador)
                guard let medida = medidaUtil(da: mascara) else { continue }
                candidatas.append((mascara, medida))
            }
            let contexto = CIContext(options: [.cacheIntermediates: false])
            let original = CIImage(cgImage: imagem)
            let transparente = CIImage(color: .clear).cropped(to: original.extent)
            return candidatas
                .sorted { $0.medida.pontuacao > $1.medida.pontuacao }
                .compactMap { candidata in
                    let mask = CIImage(cvPixelBuffer: candidata.mascara)
                    let filtro = CIFilter.blendWithMask()
                    filtro.inputImage = original
                    filtro.backgroundImage = transparente
                    filtro.maskImage = mask
                    guard let composta = filtro.outputImage else { return nil }

                    // O pixel buffer tem origem no topo; Core Image, embaixo.
                    let altura = CGFloat(CVPixelBufferGetHeight(candidata.mascara))
                    let limites = candidata.medida.limites
                    var recorte = CGRect(x: limites.minX,
                                         y: altura - limites.maxY,
                                         width: limites.width,
                                         height: limites.height)
                    let margem = max(recorte.width, recorte.height) * 0.05
                    recorte = recorte.insetBy(dx: -margem, dy: -margem)
                        .intersection(original.extent)
                    guard recorte.width > 1, recorte.height > 1 else { return nil }
                    return contexto.createCGImage(composta, from: recorte)
                }
        } catch {
            return []
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
