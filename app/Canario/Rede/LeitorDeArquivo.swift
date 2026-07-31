import Foundation
import PDFKit
import Vision

/// Extrai texto de um print, foto ou PDF, **no dispositivo**.
///
/// Por que este caminho, e não visão computacional:
///
/// A Vision da Apple reconhece TEXTO muito bem e de graça, mas classifica
/// imagem em rótulos genéricos ("roupa", "vestido") — ela não sabe dizer
/// *midi*, *manga bufante* ou *wide leg*. Atributo de moda exigiria um modelo
/// treinado, que é o que a §28 planejava com Create ML e segue revogado.
///
/// O caso real de uso, porém, é print de página de produto — e aí o texto está
/// lá. O título do produto vira atributo pelo mesmo `Traducao` que já converte
/// título de e-commerce, que é o que a §28 chama de "etiqueta quase pronta".
///
/// **Retenção zero** (decisão do JP, 30/07): o arquivo é lido para a memória,
/// o texto é extraído e nada é copiado, salvo ou enviado. Não há cópia em
/// disco, não há upload, não há miniatura.
///
/// **Sem câmera e sem fototeca**: o seletor de documentos do iOS entrega o
/// arquivo já autorizado pelo usuário, então o app não pede permissão nenhuma —
/// e a ficha de privacidade da App Store continua trivial, que era o ganho que
/// motivou o corte da câmera no A7.
enum LeitorDeArquivo {

    enum Falha: LocalizedError {
        case semAcesso
        case formatoNaoSuportado
        case semTexto

        var errorDescription: String? {
            switch self {
            case .semAcesso:
                return "Não consegui abrir o arquivo."
            case .formatoNaoSuportado:
                return "Formato não suportado. Envie um print, uma foto ou um PDF."
            case .semTexto:
                return "Não encontrei texto neste arquivo."
            }
        }
    }

    /// Lê o arquivo e devolve o texto encontrado. Nada persiste.
    static func texto(de url: URL) async throws -> String {
        // Arquivo vindo do seletor chega com escopo de segurança: sem isto a
        // leitura falha silenciosamente.
        let precisaLiberar = url.startAccessingSecurityScopedResource()
        defer { if precisaLiberar { url.stopAccessingSecurityScopedResource() } }

        let dados: Data
        do { dados = try Data(contentsOf: url) } catch { throw Falha.semAcesso }

        if url.pathExtension.lowercased() == "pdf" {
            return try textoDePDF(dados)
        }
        return try await textoDeImagem(dados)
    }

    // MARK: PDF

    /// PDF com texto não precisa de OCR: o texto já está lá, e extraí-lo é mais
    /// exato e mais rápido que reconhecê-lo de novo a partir do desenho.
    private static func textoDePDF(_ dados: Data) throws -> String {
        guard let doc = PDFDocument(data: dados) else { throw Falha.formatoNaoSuportado }
        var partes: [String] = []
        for i in 0..<min(doc.pageCount, 10) {   // 10 páginas basta para uma ficha
            if let p = doc.page(at: i), let t = p.string { partes.append(t) }
        }
        let texto = partes.joined(separator: "\n")
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // PDF de imagem escaneada: sem texto embutido. Poderia cair no OCR,
            // mas dizer o que houve é mais útil que tentar em silêncio.
            throw Falha.semTexto
        }
        return texto
    }

    // MARK: Imagem

    private static func textoDeImagem(_ dados: Data) async throws -> String {
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, nil),
              let imagem = CGImageSourceCreateImageAtIndex(fonte, 0, nil) else {
            throw Falha.formatoNaoSuportado
        }

        return try await withCheckedThrowingContinuation { cont in
            let pedido = VNRecognizeTextRequest { req, erro in
                if let erro { cont.resume(throwing: erro); return }
                let linhas = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                let texto = linhas.joined(separator: "\n")
                if texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cont.resume(throwing: Falha.semTexto)
                } else {
                    cont.resume(returning: texto)
                }
            }
            // Português primeiro: o catálogo é brasileiro. Inglês junto porque
            // muita ficha de produto mistura ("puff sleeve", "wide leg").
            pedido.recognitionLanguages = ["pt-BR", "en-US"]
            pedido.recognitionLevel = .accurate
            pedido.usesLanguageCorrection = true

            do {
                try VNImageRequestHandler(cgImage: imagem, options: [:]).perform([pedido])
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
