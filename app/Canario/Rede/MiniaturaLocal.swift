import Foundation
import OSLog
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
        /// PNG com transparência: serve para exibir e guardar no closet.
        let dados: Data
        let tipo: Tipo

        var rotulo: String {
            switch tipo {
            case .primeiroPlano: return frase("Isolated item \(String(id + 1))")
            case .fotoCompleta: return frase("Full photo")
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
                opcoes.append(OpcaoDeAlvo(id: opcoes.count, dados: completa,
                                          tipo: .fotoCompleta))
            }
            return opcoes
        }.value
    }

    /// Achata a peça escolhida sobre branco, opaca. PNG transparente chega
    /// achatado sobre **preto** numa API de visão -- foi assim que o benchmark
    /// de 300 mediu retângulos pretos. Só a opção confirmada passa por aqui:
    /// gerar isto para as quatro opções custava quatro codificações JPEG antes
    /// de a tela de escolha sequer aparecer.
    static func opacaParaAnalise(de dados: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let imagem = imagem(de: dados, ladoMaximo: Int(ladoMaximo)) else {
                return nil
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
        guard let imagem = imagem(doArquivo: url) else { return nil }
        return await self.dados(de: imagem)
    }

    /// Abre também PDF como imagem para que Arquivos, Fotos e Câmera entrem no
    /// mesmo portão de confirmação e, com consentimento, na mesma Luna. Antes o
    /// PDF era desviado direto ao OCR/cor local e nunca chegava à análise visual.
    static func imagem(doArquivo url: URL) -> CGImage? {
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
            return imagem.cgImage
        }
        return imagem(de: dados)
    }

    /// Recorte manual em coordenadas normalizadas (origem no canto superior
    /// esquerdo), usado antes de gerar novamente as máscaras de primeiro plano.
    /// A imagem original continua somente em memória.
    static func recortar(_ imagem: CGImage,
                         retanguloNormalizado: CGRect) -> CGImage? {
        let unidade = CGRect(x: 0, y: 0, width: 1, height: 1)
        let normalizado = retanguloNormalizado.standardized.intersection(unidade)
        guard !normalizado.isNull, normalizado.width > 0.01,
              normalizado.height > 0.01 else { return nil }
        let largura = CGFloat(imagem.width)
        let altura = CGFloat(imagem.height)
        let pixels = CGRect(
            x: normalizado.minX * largura,
            y: normalizado.minY * altura,
            width: normalizado.width * largura,
            height: normalizado.height * altura)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: largura, height: altura))
        guard pixels.width >= 8, pixels.height >= 8 else { return nil }
        return imagem.cropping(to: pixels)
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
            var candidatas: [(mascara: CVPixelBuffer,
                              medida: MascaraDeInstancia.Medida)] = []
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
            // NÃO É A MESMA COISA QUE "não achei peça", e o código tratava como
            // se fosse.
            //
            // `VNGenerateForegroundInstanceMaskRequest` precisa do Neural
            // Engine. No simulador ele falha sempre, com
            // `Error code: 9; Could not create inference context` -- medido em
            // 05/09, e foi o que fez a tela de confirmação aparecer só com
            // "Foto inteira" numa captura que parecia mostrar a função sumida.
            // Num aparelho a mesma exceção significaria outra coisa: memória,
            // imagem corrompida, modelo indisponível.
            //
            // O retorno continua `[]`, porque a tela deve mesmo cair na foto
            // inteira nos dois casos -- o que muda é que a falha para de ser
            // indistinguível do silêncio legítimo. É a regra do §16 da
            // blueprint aplicada ao app: não esconder falha como execução de
            // sucesso vazia.
            registrarFalhaDeSegmentacao(error)
            return []
        }
    }

    /// Onde a falha do segmentador fica visível para quem for investigar.
    ///
    /// `os_log` e não `print`: sai no Console.app de um aparelho físico, que é
    /// o único lugar onde esta função roda de verdade.
    private static func registrarFalhaDeSegmentacao(_ erro: Error) {
        Logger(subsystem: "br.com.canario.ch3.app", category: "segmentacao")
            .error("primeiro plano indisponível: \(erro.localizedDescription, privacy: .public)")
    }

    /// A medição vive em `MascaraDeInstancia`, que é testada sem simulador.
    private static func medidaUtil(da mascara: CVPixelBuffer)
        -> MascaraDeInstancia.Medida? {
        (try? MascaraDeInstancia.medir(mascara)) ?? nil
    }
}
