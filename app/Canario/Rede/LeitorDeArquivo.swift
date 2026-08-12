import Foundation
import PDFKit
import Vision

/// Extrai o que dá para extrair de um print, foto ou PDF, **no dispositivo**.
///
/// ## O caminho, e por que ele tem três degraus
///
/// 1. **Texto embutido no PDF.** Se existe, é o melhor dado possível: já é
///    exato, não passa por reconhecimento e sai instantâneo.
/// 2. **OCR da imagem.** Print de página de produto tem o título escrito, e o
///    título vira atributo pelo mesmo `Traducao` que converte título de
///    e-commerce. É o que a §28 chama de "etiqueta quase pronta".
/// 3. **Cor medida no pixel.** Quando não há letra nenhuma — foto de produto
///    pura — ainda dá para recuperar uma dimensão inteira da taxonomia, sem
///    modelo treinado e sem rede.
///
/// ## O que quebrou, e virou o degrau 3
///
/// Em 31/07 o JP mandou uma foto de produto da Hering salva em PDF. O arquivo
/// tem `/Image` e `DCTDecode` e **nenhum `/Font`**: é uma foto dentro de um
/// PDF, sem uma letra. A versão anterior chamava `PDFDocument.page.string`,
/// recebia vazio e desistia com "não encontrei texto neste arquivo" — sem nem
/// tentar olhar a imagem que estava ali.
///
/// Eram dois buracos de uma vez: PDF de imagem nunca era rasterizado para OCR,
/// e imagem sem texto não tinha caminho nenhum. Os dois estão fechados aqui.
///
/// ## Retenção zero
///
/// Decisão do JP em 30/07: o arquivo é lido para a memória, o que interessa é
/// extraído e a imagem original não é copiada nem salva por este leitor. A18
/// autoriza, fora daqui e só depois de "Save to Closet", uma miniatura local
/// reamostrada e sem metadados. Câmera e fototeca continuam em memória.
enum LeitorDeArquivo {

    /// Tudo que o arquivo entregou, com a procedência de cada parte.
    struct Leitura {
        var texto: String = ""
        var cor: CorDaPeca.Leitura?
        /// Termos parecidos com peças do painel (§28). Vem vazio enquanto o
        /// portão da §28 não tiver sido medido — ver `SemelhancaVisual`.
        var semelhantes: [SemelhancaVisual.Sugestao] = []
        var origem: Origem = .semNada

        enum Origem: Equatable {
            case textoDoPDF        // texto embutido, sem reconhecimento
            case ocr               // texto reconhecido da imagem
            case somenteCor        // não havia letra; sobrou o pixel
            case semNada
        }

        var vazia: Bool {
            texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && cor == nil && semelhantes.isEmpty
        }
    }

    enum Falha: LocalizedError {
        case semAcesso
        case formatoNaoSuportado
        case nadaReconhecido

        var errorDescription: String? {
            switch self {
            case .semAcesso:
                return "Não consegui abrir o arquivo."
            case .formatoNaoSuportado:
                return "Formato não suportado. Envie um print, uma foto (JPG, PNG, HEIC) ou um PDF."
            case .nadaReconhecido:
                return "Abri o arquivo, mas não reconheci texto nem cor de peça nele."
            }
        }
    }

    /// Lê o arquivo. Nada persiste.
    static func ler(_ url: URL) async throws -> Leitura {
        // Arquivo vindo do seletor chega com escopo de segurança: sem isto a
        // leitura falha silenciosamente.
        let precisaLiberar = url.startAccessingSecurityScopedResource()
        defer { if precisaLiberar { url.stopAccessingSecurityScopedResource() } }

        let dados: Data
        do { dados = try Data(contentsOf: url) } catch { throw Falha.semAcesso }

        let leitura = url.pathExtension.lowercased() == "pdf"
            ? try await dePDF(dados)
            : try await deImagem(dados)

        if leitura.vazia { throw Falha.nadaReconhecido }
        return leitura
    }

    // MARK: PDF

    private static func dePDF(_ dados: Data) async throws -> Leitura {
        guard let doc = PDFDocument(data: dados) else { throw Falha.formatoNaoSuportado }

        // 1) Texto embutido. Quando existe, é exato e acaba aqui.
        var partes: [String] = []
        for i in 0..<min(doc.pageCount, 10) {   // 10 páginas basta para uma ficha
            if let p = doc.page(at: i), let t = p.string { partes.append(t) }
        }
        let texto = partes.joined(separator: "\n")
        if !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Leitura(texto: texto, cor: nil, origem: .textoDoPDF)
        }

        // 2) PDF sem fonte é foto dentro de um envelope. Rasteriza e trata como
        //    imagem — que é exatamente o arquivo que o JP mandou.
        guard let pagina = doc.page(at: 0), let img = rasterizar(pagina) else {
            throw Falha.formatoNaoSuportado
        }
        return await deCGImage(img)
    }

    /// Desenha a página num bitmap. 2x do tamanho natural: abaixo disso o OCR
    /// perde legenda pequena, que é justamente onde mora o nome do produto.
    private static func rasterizar(_ pagina: PDFPage) -> CGImage? {
        let caixa = pagina.bounds(for: .mediaBox)
        let escala: CGFloat = 2
        let w = Int(caixa.width * escala), h = Int(caixa.height * escala)
        guard w > 0, h > 0, w * h < 40_000_000,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Fundo branco: PDF sem fundo desenharia sobre preto e inverteria a cor
        // lida — e a cor é metade do que esta função existe para recuperar.
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: escala, y: escala)
        ctx.translateBy(x: -caixa.minX, y: -caixa.minY)
        pagina.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    // MARK: Imagem

    private static func deImagem(_ dados: Data) async throws -> Leitura {
        // Aceita tudo que o ImageIO decodifica: JPG, PNG, HEIC, TIFF.
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, nil),
              let imagem = CGImageSourceCreateImageAtIndex(fonte, 0, nil) else {
            throw Falha.formatoNaoSuportado
        }
        return await deCGImage(imagem)
    }

    /// Mesma leitura, a partir de uma imagem já em memória.
    ///
    /// Existe para a câmera e a fototeca (A12): as duas entregam a imagem
    /// direto, sem passar por arquivo em disco. Isso é o que mantém a retenção
    /// zero da §28 — não há caminho de arquivo para gravar, e não existe cópia
    /// intermediária a esquecer.
    static func ler(_ imagem: CGImage) async -> Leitura {
        await deCGImage(imagem)
    }

    private static func deCGImage(_ img: CGImage) async -> Leitura {
        let texto = (try? await ocr(img)) ?? ""
        let temTexto = !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A cor é lida sempre, inclusive quando há texto: o título costuma
        // trazer a cor comercial ("areia", "off white"), mas nem todo título
        // traz, e medir custa milissegundos.
        let cor = CorDaPeca.ler(img)
        // Terceira leitura da mesma imagem: com que peças do painel esta se
        // parece (§28). Sai vazia enquanto o portão da §28 estiver fechado,
        // então adicioná-la aqui não muda nada até alguém medir.
        #if canImport(Vision)
        let semelhantes = SemelhancaVisual.sugerir(img)
        #else
        let semelhantes: [SemelhancaVisual.Sugestao] = []
        #endif
        let temSinal = temTexto || cor != nil || !semelhantes.isEmpty
        let origem: Leitura.Origem = temTexto ? .ocr : (temSinal ? .somenteCor : .semNada)
        return Leitura(texto: texto, cor: cor, semelhantes: semelhantes, origem: origem)
    }

    private static func ocr(_ imagem: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let pedido = VNRecognizeTextRequest { req, erro in
                if let erro { cont.resume(throwing: erro); return }
                let linhas = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: linhas.joined(separator: "\n"))
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
