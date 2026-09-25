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
        /// Quanto o SISTEMA confia na cor desta captura, 0…1.
        ///
        /// Só existe quando a foto veio da rota de cor constante do iOS 18
        /// (ver `CapturaDeCorConstante`), onde o flash de espectro conhecido
        /// permite reconstruir a cor independentemente da lâmpada do ambiente.
        ///
        /// **`nil` não é confiança zero — é confiança não medida.** É o estado
        /// de toda foto de fototeca, de arquivo e da câmera comum, ou seja, da
        /// esmagadora maioria. Confundir os dois transformaria a chegada desta
        /// rota numa regressão silenciosa: o app pararia de sugerir cor para
        /// todo mundo que não tem um iPhone com suporte.
        var confiancaDaCaptura: Double? = nil

        /// A cor pode ser **pré-marcada** no formulário?
        ///
        /// Sim quando não há medida (comportamento de sempre: sugestão que a
        /// pessoa confirma ou desmarca com um toque, §28) e quando há medida
        /// suficiente. Não quando há medida e ela é baixa — aí o app sabe que
        /// a luz enganou a foto, e a regra 2 manda declarar a lacuna em vez de
        /// oferecer um valor plausível.
        var podeSugerirCor: Bool {
            guard let confianca = confiancaDaCaptura else { return true }
            return confianca >= CorDaPeca.confiancaMinimaDaCaptura
        }
    }

    /// Abaixo disto o recorte tinha pele ou vazio demais para afirmar cor.
    static let coberturaMinima = 0.15

    /// Piso de confiança da captura de cor constante.
    ///
    /// **Este número ainda não foi calibrado, e o registro é deliberado.** O
    /// `coberturaMinima` acima saiu de 5 fotos reais e diz isso na cara; este
    /// não saiu de medição nenhuma — é um meio-termo conservador enquanto não
    /// existir um conjunto de peças fotografadas sob luzes conhecidas com a
    /// cor verdadeira anotada. Até lá ele erra para o lado de não sugerir, que
    /// custa um toque, em vez de sugerir errado, que suja o dado no Closet.
    ///
    /// Quando a calibração acontecer, o valor muda AQUI e o teste que o cobre
    /// muda junto; nenhuma tela conhece este limiar.
    static let confiancaMinimaDaCaptura = 0.5

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

    /// Cor representativa de cada termo, para a interface poder MOSTRAR a cor
    /// em vez de escrever o nome dela.
    ///
    /// Os valores não são gosto pessoal: cada um cai no meio da faixa que
    /// `termo(paraRGB:)` usa para classificar aquele termo, e o teste de ida e
    /// volta exige que reclassifiquem em si mesmos. Quer dizer que o quadradinho
    /// na tela é fiel ao que o app entende por aquele termo — e que mudar a
    /// classificação sem mudar a amostra quebra o teste, em vez de deixar os
    /// dois divergirem em silêncio.
    ///
    /// `outras_cores` devolve `nil` de propósito. É a categoria residual, não
    /// uma cor: pintar um quadradinho para ela seria inventar informação, e a
    /// regra 2 proíbe exatamente isso.
    static func rgbRepresentativo(de termoId: String) -> (Double, Double, Double)? {
        switch termoId {
        case "vermelho_rosa":   return (0.85, 0.22, 0.35)
        case "amarelo_laranja": return (0.98, 0.78, 0.30)
        case "terrosos":        return (0.62, 0.44, 0.24)
        case "verde":           return (0.28, 0.60, 0.35)
        case "azul":            return (0.22, 0.42, 0.72)
        case "lilas_roxo":      return (0.55, 0.35, 0.75)
        case "preto":           return (0.10, 0.10, 0.12)
        case "branco_cru":      return (0.96, 0.94, 0.89)
        case "cinza":           return (0.58, 0.58, 0.59)
        default:                return nil
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
    static func ler(_ img: CGImage, confiancaDaCaptura: Double? = nil) -> Leitura? {
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

        guard let amostra = medianaRGBA(buf, numeroDePixels: n * n),
              amostra.cobertura >= coberturaMinima else { return nil }
        let cobertura = amostra.cobertura
        let rgb = amostra.rgb
        return Leitura(termoId: termo(paraRGB: rgb), rgb: rgb, cobertura: cobertura,
                       confiancaDaCaptura: confiancaDaCaptura)
    }

    /// Extrai a mediana dos pixels realmente visíveis de um bitmap RGBA.
    ///
    /// Uma miniatura recortada pelo Vision é PNG transparente. Antes, os pixels
    /// transparentes eram desenhados como preto no `CGContext` e entravam na
    /// mediana: o app media a ausência de fundo como se fosse a cor da roupa.
    /// O alfa agora é um portão explícito, antes inclusive do filtro de pele.
    static func medianaRGBA(_ bytes: [UInt8], numeroDePixels: Int)
        -> (rgb: [Double], cobertura: Double)? {
        guard numeroDePixels > 0, bytes.count >= numeroDePixels * 4 else {
            return nil
        }
        var canais: [[Double]] = [[], [], []]
        for pixel in 0..<numeroDePixels {
            let i = pixel * 4
            let alfa = Double(bytes[i + 3]) / 255
            // Bordas antialiasadas parcialmente transparentes ainda carregam
            // cor misturada com o fundo. Só pixels majoritariamente opacos
            // sustentam a leitura dominante.
            guard alfa >= 0.5 else { continue }
            let r = Double(bytes[i]) / 255
            let g = Double(bytes[i + 1]) / 255
            let b = Double(bytes[i + 2]) / 255
            if ehPele(r, g, b) { continue }
            canais[0].append(r); canais[1].append(g); canais[2].append(b)
        }
        guard !canais[0].isEmpty else { return nil }
        // Mediana, não média: resiste melhor a sombra funda e a costura clara.
        let rgb = canais.map { canal -> Double in
            let ordenado = canal.sorted()
            return ordenado[ordenado.count / 2]
        }
        return (rgb, Double(canais[0].count) / Double(numeroDePixels))
    }
}

/// Reúne as duas entregas que o iOS pode fazer para um único disparo.
///
/// A ordem dos callbacks não faz parte do contrato que interessa ao produto:
/// a foto natural pode chegar antes ou depois da foto de cor constante. Por
/// isso nenhuma delas encerra a captura sozinha. O par só é decidido quando o
/// `AVCapturePhotoCaptureDelegate` declara que o disparo inteiro terminou.
///
/// O tipo é genérico para que a regra seja testada sem câmera e sem UIKit.
struct MontadorDeParDeCaptura<Imagem> {
    struct Par {
        let imagem: Imagem
        let imagemDeMedicao: Imagem?
        let confianca: Double?
    }

    enum Fechamento {
        case captura(Par)
        case tentarNovamente
        case ignorar
    }

    private var natural: Imagem?
    private var constante: Imagem?
    private var confianca: Double?
    private var encerrado = false

    /// Devolve `false` quando a captura já foi encerrada ou cancelada.
    @discardableResult
    mutating func registrarNatural(_ imagem: Imagem) -> Bool {
        guard !encerrado else { return false }
        natural = imagem
        return true
    }

    /// Devolve `false` quando a captura já foi encerrada ou cancelada.
    @discardableResult
    mutating func registrarConstante(_ imagem: Imagem,
                                     confianca: Double?) -> Bool {
        guard !encerrado else { return false }
        constante = imagem
        self.confianca = confianca
        return true
    }

    /// Impede qualquer callback tardio de produzir uma segunda saída.
    @discardableResult
    mutating func cancelar() -> Bool {
        guard !encerrado else { return false }
        encerrado = true
        natural = nil
        constante = nil
        confianca = nil
        return true
    }

    mutating func concluir() -> Fechamento {
        guard !encerrado else { return .ignorar }
        encerrado = true

        if let constante {
            // Sem a natural, a constante ainda é uma foto válida. Ela assume
            // também o papel visual em vez de apagar um disparo bem-sucedido.
            return .captura(.init(imagem: natural ?? constante,
                                  imagemDeMedicao: constante,
                                  confianca: confianca))
        }
        if let natural {
            // A medição constante falhou, mas a reserva preservou a foto.
            return .captura(.init(imagem: natural,
                                  imagemDeMedicao: nil,
                                  confianca: nil))
        }
        return .tentarNovamente
    }
}
