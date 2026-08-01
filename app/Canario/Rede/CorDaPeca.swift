import Foundation
import CoreGraphics
import Vision

/// Cor dominante de uma foto de peça, mapeada para a dimensão `cor` da
/// taxonomia.
///
/// **Por que isto existe.** O OCR resolve print de página de produto, onde o
/// título já diz tudo. Não resolve o caso que o JP mandou em 31/07: uma foto de
/// produto da Hering, salva em PDF, **sem uma letra dentro**. Para esse arquivo o
/// app dizia "não encontrei texto" e devolvia o formulário em branco.
///
/// A classificação genérica da Vision não salva: medida na própria foto do JP,
/// ela devolveu `clothing` com 0,53 de confiança e nada mais — sabe que é roupa,
/// não sabe que peça nem de que cor. Nomear a categoria a partir da imagem exige
/// um modelo treinado, e ele está registrado como próximo passo.
///
/// Cor, porém, **é medível direto do pixel**, sem modelo, sem rede e sem custo.
/// É uma dimensão inteira da taxonomia recuperada de uma foto muda.
///
/// **O que foi medido, e em quantas imagens.** Os limiares abaixo foram
/// calibrados em 5 fotos reais (a do JP e quatro do nosso próprio catálogo, com
/// a cor conhecida pelo título) e acertaram as 5. É amostra pequena, e está
/// dito: a calibração definitiva sai do catálogo inteiro, quando o runner
/// residencial puder baixar as imagens — os CDNs devolvem 429 para o datacenter,
/// e a regra 7 proíbe contornar isso.
///
/// Enquanto a amostra for pequena, a cor entra como **sugestão marcada no
/// formulário**, nunca como fato: o usuário confirma ou desmarca com um toque,
/// que é o desenho da §28. Sugestão errada custa um toque; número errado num
/// relatório custa a confiança.
enum CorDaPeca {

    /// O que a leitura devolve, com o quanto ela se sustenta.
    struct Leitura: Equatable {
        let termoId: String
        let rgb: [Double]
        /// Fração de pixels do recorte que sobraram depois de descartar pele.
        /// Abaixo de `coberturaMinima` a leitura não é oferecida.
        let cobertura: Double
    }

    /// Abaixo disto o recorte tinha pele ou vazio demais para afirmar cor.
    static let coberturaMinima = 0.15

    // MARK: Mapeamento puro (é o que os testes cobrem)

    /// RGB em 0…1 para o id do termo da dimensão `cor`.
    ///
    /// Os cortes não são arbitrários; cada um responde a um caso que apareceu:
    ///
    /// * **O eixo neutro é decidido por croma (`máx − mín`), não por saturação.**
    ///   A saturação de HSL tem `2 − máx − mín` no denominador, que vai a zero
    ///   perto do branco: um off white medido em (0,94 0,92 0,90) tem croma de
    ///   0,04 — praticamente cinza — e saturação de 0,25, que o fazia passar por
    ///   colorido e sair como "amarelo e laranja". O teste pegou isso com os
    ///   números reais de duas peças off white do catálogo.
    /// * `luz > 0.82` para branco e cru — o off white do catálogo mediu 0,92 a
    ///   0,94, e o cinza mescla da foto do JP mediu 0,72. O corte fica no meio
    ///   do vão, não na borda de nenhum dos dois.
    /// * amarelo escuro vira `terrosos`, porque caramelo e mostarda dividem a
    ///   mesma faixa de matiz e o que os separa é a luminosidade.
    static func termo(paraRGB c: [Double]) -> String {
        guard c.count == 3 else { return "outras_cores" }
        let r = c[0], g = c[1], b = c[2]
        let mx = max(r, g, b), mn = min(r, g, b)
        let luz = (mx + mn) / 2
        let croma = mx - mn
        let sat = mx == mn ? 0 : croma / (luz > 0.5 ? (2 - mx - mn) : (mx + mn))

        if luz < 0.18 { return "preto" }
        // Neutro por croma absoluto; a segunda cláusula cobre o quase-branco,
        // onde um resto de matiz ainda lê como cru e não como cor.
        if croma < 0.10 || (croma < 0.18 && luz > 0.80) {
            if luz > 0.82 { return "branco_cru" }
            if luz > 0.28 { return "cinza" }
            return "preto"
        }

        var h: Double = 0
        if mx == r { h = (g - b) / (mx - mn) }
        else if mx == g { h = 2 + (b - r) / (mx - mn) }
        else { h = 4 + (r - g) / (mx - mn) }
        h = (h * 60).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }

        switch h {
        case 0..<12, 340..<360: return "vermelho_rosa"
        case 12..<45:           return luz < 0.62 ? "terrosos" : "amarelo_laranja"
        case 45..<70:           return sat < 0.35 ? "terrosos" : "amarelo_laranja"
        case 70..<170:          return "verde"
        case 170..<255:         return "azul"
        case 255..<290:         return "lilas_roxo"
        default:                return "vermelho_rosa"
        }
    }

    /// Pele humana em RGB. Descartada porque foto de produto vem em modelo, e
    /// braço e rosto puxariam toda peça clara para "terrosos".
    static func ehPele(_ r: Double, _ g: Double, _ b: Double) -> Bool {
        r > g && g > b && (r - b) > 0.12 && (r - b) < 0.42 && r > 0.38 && b < 0.72
    }

    // MARK: Amostragem da imagem

    /// Lê a cor dominante do torso da peça.
    ///
    /// O recorte é a faixa central da região saliente, pulando o terço
    /// superior: em foto de produto com modelo, ali está o rosto.
    ///
    /// **O fundo claro NÃO é descartado por brilho.** Foi a primeira tentativa
    /// e ela apagava a própria peça quando a peça era off white — a cobertura
    /// de uma regata branca caiu para 6% e a cor lida virou a da sombra. Como
    /// `branco_cru` é um dos termos mais importantes do painel (é o que sobe
    /// todo novembro), o filtro por brilho estava errado pela raiz. Quem separa
    /// peça de fundo aqui é o recorte, não o brilho.
    static func ler(_ img: CGImage) -> Leitura? {
        var caixa = CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5)
        let saliencia = VNGenerateAttentionBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([saliencia])
        if let obs = saliencia.results?.first, let b = obs.salientObjects?.first {
            caixa = b.boundingBox
        }

        let W = CGFloat(img.width), H = CGFloat(img.height)
        let x = caixa.minX * W, w = caixa.width * W
        // Vision tem origem embaixo; CGImage tem em cima.
        let yTopo = (1 - caixa.maxY) * H, h = caixa.height * H
        let recorte = CGRect(x: x + w * 0.25, y: yTopo + h * 0.34,
                             width: w * 0.5, height: h * 0.32)
            .intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard !recorte.isNull, recorte.width >= 8, recorte.height >= 8,
              let corte = img.cropping(to: recorte) else { return nil }

        let n = 64
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &buf, width: n, height: n,
                                  bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(corte, in: CGRect(x: 0, y: 0, width: n, height: n))

        var canais: [[Double]] = [[], [], []]
        for i in stride(from: 0, to: n * n * 4, by: 4) {
            let r = Double(buf[i]) / 255
            let g = Double(buf[i + 1]) / 255
            let b = Double(buf[i + 2]) / 255
            if ehPele(r, g, b) { continue }
            canais[0].append(r); canais[1].append(g); canais[2].append(b)
        }

        let cobertura = Double(canais[0].count) / Double(n * n)
        guard cobertura >= coberturaMinima else { return nil }
        // Mediana, não média: resiste melhor a sombra funda e a costura clara.
        let rgb = canais.map { c -> Double in c.sorted()[c.count / 2] }
        return Leitura(termoId: termo(paraRGB: rgb), rgb: rgb, cobertura: cobertura)
    }
}
