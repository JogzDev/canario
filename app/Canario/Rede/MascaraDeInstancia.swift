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

    /// Normaliza o buffer para `[0,1]`, aceitando os dois formatos publicados.
    static func ler(_ buffer: CVPixelBuffer) throws -> Leitura {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw Falha.bufferIlegivel
        }
        let largura = CVPixelBufferGetWidth(buffer)
        let altura = CVPixelBufferGetHeight(buffer)
        let passo = CVPixelBufferGetBytesPerRow(buffer)
        let formato = CVPixelBufferGetPixelFormatType(buffer)
        var valores = [Float](repeating: 0, count: largura * altura)

        switch formato {
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<altura {
                let linha = base.advanced(by: y * passo)
                    .assumingMemoryBound(to: UInt8.self)
                for x in 0..<largura {
                    valores[y * largura + x] = Float(linha[x]) / 255
                }
            }
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<altura {
                let linha = base.advanced(by: y * passo)
                    .assumingMemoryBound(to: Float.self)
                for x in 0..<largura {
                    valores[y * largura + x] = linha[x]
                }
            }
        default:
            throw Falha.formatoDesconhecido(formato)
        }
        return Leitura(valores: valores, largura: largura, altura: altura)
    }

    /// Caixa, cobertura e pontuação da máscara. Área manda; a centralidade só
    /// desempata instância grande na borda contra peça deliberadamente
    /// assimétrica. Devolve `nil` quando a máscara é inútil, não quando é
    /// ilegível: esse caso é erro e sobe como `Falha`.
    static func medir(_ leitura: Leitura) -> Medida? {
        var minX = leitura.largura, minY = leitura.altura
        var maxX = -1, maxY = -1, ativos = 0
        for y in 0..<leitura.altura {
            for x in 0..<leitura.largura
            where leitura.valores[y * leitura.largura + x] >= limiar {
                ativos += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let cobertura = Double(ativos) / Double(max(1, leitura.largura * leitura.altura))
        guard maxX >= minX, maxY >= minY,
              cobertura >= coberturaMinima, cobertura <= coberturaMaxima else {
            return nil
        }
        let limites = CGRect(x: minX, y: minY,
                             width: maxX - minX + 1, height: maxY - minY + 1)
        let centroX = Double(limites.midX) / Double(max(1, leitura.largura))
        let centroY = Double(limites.midY) / Double(max(1, leitura.altura))
        let distancia = hypot(centroX - 0.5, centroY - 0.5)
        return Medida(limites: limites, cobertura: cobertura,
                      pontuacao: cobertura - 0.04 * distancia)
    }
}
