import CoreGraphics
import CoreVideo
import Foundation

/// Leitura e medição da máscara devolvida pelo Vision.
///
/// Vive fora de `MiniaturaLocal` por um motivo prático: aqui não há UIKit nem
/// Vision, então este arquivo entra no pacote `CanarioLogica` e é testado a
/// cada commit, sem simulador.
///
/// O formato do buffer não é estável entre versões do sistema. Em 14/08/2026,
/// `generateScaledMaskForImage` devolve `OneComponent32Float`; havia código que
/// exigia `OneComponent8` e, por isso, descartava **toda** máscara em silêncio —
/// o app achava que não existia primeiro plano e mandava a foto crua, com fundo,
/// para a análise. Tratar formato desconhecido como "sem peça" é o erro caro:
/// aqui ele é distinguível de máscara realmente vazia.
enum MascaraDeInstancia {
    /// Limiar de pertencimento à peça. Igual ao do segmentador do benchmark.
    static let limiar: Float = 0.5
    /// Abaixo disso a detecção é ruído; acima, ela não removeu fundo algum.
    static let coberturaMinima = 0.06
    static let coberturaMaxima = 0.98

    struct Leitura {
        let valores: [Float]
        let largura: Int
        let altura: Int
    }

    enum Falha: Error, Equatable {
        case bufferIlegivel
        case formatoDesconhecido(OSType)
    }

    struct Medida: Equatable {
        let limites: CGRect
        let cobertura: Double
        let pontuacao: Double
    }

    /// Normaliza o buffer para `[0,1]`. Usado pelos testes, que constroem
    /// máscara sintética; o caminho do app não passa por aqui, porque
    /// materializar a máscara inteira custa caro num aparelho.
    static func ler(_ buffer: CVPixelBuffer) throws -> Leitura {
        var valores = [Float]()
        var largura = 0
        var altura = 0
        try percorrer(buffer) { l, a, x, y, v in
            if valores.isEmpty {
                largura = l; altura = a
                valores = [Float](repeating: 0, count: l * a)
            }
            valores[y * l + x] = v
        }
        return Leitura(valores: valores, largura: largura, altura: altura)
    }

    /// Lê o buffer pixel a pixel sem alocar cópia. Aceita os dois formatos que
    /// o Vision publica; formato desconhecido é erro, não máscara vazia.
    private static func percorrer(
        _ buffer: CVPixelBuffer,
        _ visitar: (Int, Int, Int, Int, Float) -> Void) throws {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw Falha.bufferIlegivel
        }
        let largura = CVPixelBufferGetWidth(buffer)
        let altura = CVPixelBufferGetHeight(buffer)
        let passo = CVPixelBufferGetBytesPerRow(buffer)
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<altura {
                let linha = base.advanced(by: y * passo)
                    .assumingMemoryBound(to: UInt8.self)
                for x in 0..<largura {
                    visitar(largura, altura, x, y, Float(linha[x]) / 255)
                }
            }
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<altura {
                let linha = base.advanced(by: y * passo)
                    .assumingMemoryBound(to: Float.self)
                for x in 0..<largura {
                    visitar(largura, altura, x, y, linha[x])
                }
            }
        case let formato:
            throw Falha.formatoDesconhecido(formato)
        }
    }

    /// Mede direto do buffer, numa passada e sem alocar. É este o caminho do
    /// app: a versão anterior materializava um `[Float]` de largura x altura --
    /// cerca de 15 MB por instância, para até 16 instâncias -- e a tela de
    /// escolha do alvo demorava dezenas de segundos num iPhone.
    static func medir(_ buffer: CVPixelBuffer) throws -> Medida? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        var ativos = 0, largura = 0, altura = 0
        try percorrer(buffer) { l, a, x, y, v in
            largura = l; altura = a
            guard v >= limiar else { return }
            ativos += 1
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        return consolidar(minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                          ativos: ativos, largura: largura, altura: altura)
    }

    /// Caixa, cobertura e pontuação, a partir da leitura materializada. Existe
    /// para os testes; o app usa a versão que lê o buffer direto. As duas
    /// terminam em `consolidar`, então não podem divergir de critério.
    static func medir(_ leitura: Leitura) -> Medida? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, ativos = 0
        for y in 0..<leitura.altura {
            for x in 0..<leitura.largura
            where leitura.valores[y * leitura.largura + x] >= limiar {
                ativos += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        return consolidar(minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                          ativos: ativos, largura: leitura.largura, altura: leitura.altura)
    }

    /// Área manda; a centralidade só desempata instância grande na borda contra
    /// peça deliberadamente assimétrica. Devolve `nil` quando a máscara é
    /// inútil — ruído ou cobrindo a foto toda —, nunca quando é ilegível: esse
    /// caso é erro e sobe como `Falha`.
    private static func consolidar(minX: Int, minY: Int, maxX: Int, maxY: Int,
                                   ativos: Int, largura: Int, altura: Int) -> Medida? {
        let cobertura = Double(ativos) / Double(max(1, largura * altura))
        guard maxX >= minX, maxY >= minY,
              cobertura >= coberturaMinima, cobertura <= coberturaMaxima else {
            return nil
        }
        let limites = CGRect(x: minX, y: minY,
                             width: maxX - minX + 1, height: maxY - minY + 1)
        let centroX = Double(limites.midX) / Double(max(1, largura))
        let centroY = Double(limites.midY) / Double(max(1, altura))
        let distancia = hypot(centroX - 0.5, centroY - 0.5)
        return Medida(limites: limites, cobertura: cobertura,
                      pontuacao: cobertura - 0.04 * distancia)
    }
}

/// Calcula o bitmap de trabalho sem ampliar a origem e sem depender da escala
/// de tela do aparelho. Uma foto 4032×3024 não pode virar 12096×9072 só porque
/// o iPhone usa `@3x`: isso ultrapassaria 400 MB antes mesmo do Vision começar.
enum DimensaoDaImagem {
    struct Pixels: Equatable {
        let largura: Int
        let altura: Int

        var bytesRGBA: Int { largura * altura * 4 }
    }

    static func limitada(largura: Int, altura: Int,
                         ladoMaximo: Int) -> Pixels? {
        guard largura > 0, altura > 0, ladoMaximo > 0 else { return nil }
        let maior = max(largura, altura)
        guard maior > ladoMaximo else {
            return Pixels(largura: largura, altura: altura)
        }
        let escala = Double(ladoMaximo) / Double(maior)
        return Pixels(
            largura: max(1, Int((Double(largura) * escala).rounded())),
            altura: max(1, Int((Double(altura) * escala).rounded())))
    }
}
