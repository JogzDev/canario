import Foundation
import CoreGraphics
#if canImport(Vision)
import Vision
#endif

/// Sugere atributos de uma peça comparando a foto com o **painel brasileiro**,
/// e não com um modelo genérico da web.
///
/// ## Por que não MobileCLIP
///
/// A proposta que chegou pelo Gemini era boa e não é executável: a licença do
/// MobileCLIP (`LICENSE_MODELS` do `apple/ml-mobileclip`) libera os pesos
/// **exclusivamente para "Research Purposes"**, e diz com todas as letras que
/// isso *"does not include any commercial exploitation, product development or
/// use in any commercial product or service"*. Publicar o peso dentro de um app
/// na App Store é uso em produto, mesmo grátis, mesmo sendo TCC. Fica fora.
///
/// ## O que entra no lugar, e por que é melhor aqui
///
/// `VNGenerateImageFeaturePrintRequest` já vem no iOS — é a mesma Vision que o
/// `CorDaPeca` e o OCR usam. Ela devolve um vetor semântico da imagem. Não casa
/// imagem com texto, e para este produto isso **não é limitação**: para nomear
/// a peça não é preciso perguntar à web, é preciso perguntar ao painel.
///
/// Em vez de "que peça é essa?", o app pergunta *"com quais peças do painel
/// brasileiro essa se parece?"* — e os atributos saem de lá. Três ganhos que a
/// versão genérica não teria:
///
/// * a sugestão fica ancorada no mercado que o app mede, e não em texto da
///   internet;
/// * a regra 3 é cumprida de graça: dá para mostrar as peças que sustentaram a
///   sugestão, com link;
/// * peso zero no binário e nenhuma permissão nova — o ganho do A7 (ficha de
///   privacidade trivial, nada é enviado) fica de pé.
///
/// ## Por que centroide, e não os 18 mil vetores
///
/// Baixar o painel inteiro para o aparelho seria ~55 MB, e mandar o vetor da
/// foto para o servidor quebraria a promessa de "nada é copiado, salvo ou
/// enviado" do manifesto de privacidade — o vetor é derivado da foto do
/// usuário. Um centroide por termo resolve os dois: ~126 KB embarcados, e a
/// comparação inteira acontece no aparelho.
///
/// ## O portão da §28
///
/// A §28 é explícita: a visão só pode PRÉ-PREENCHER com concordância ≥ 80%
/// contra etiquetagem humana. Enquanto o artefato não declarar que passou,
/// `sugerir` devolve vazio — não é opção de configuração, é o que o arquivo
/// diz de si mesmo. Sugestão errada custa um toque; atributo errado num
/// relatório custa a confiança, que é o produto inteiro.
enum SemelhancaVisual {

    /// Um termo da taxonomia com o vetor médio das peças do painel que o citam.
    struct Centroide: Decodable, Equatable {
        let termoId: String
        let dimensao: String
        /// Quantas imagens entraram na média. Centroide de 3 fotos não é
        /// centroide.
        let nImagens: Int
        let vetor: [Double]

        enum CodingKeys: String, CodingKey {
            case termoId = "termo_id"
            case dimensao
            case nImagens = "n_imagens"
            case vetor
        }
    }

    /// O que a medição do artefato afirma sobre ele mesmo (§28).
    struct Portao: Decodable, Equatable {
        let concordanciaCategoria: Double
        let concordanciaCor: Double
        let nPecasAvaliadas: Int
        let passou: Bool

        enum CodingKeys: String, CodingKey {
            case concordanciaCategoria = "concordancia_categoria"
            case concordanciaCor = "concordancia_cor"
            case nPecasAvaliadas = "n_pecas_avaliadas"
            case passou
        }
    }

    struct Painel: Decodable, Equatable {
        let versao: Int
        let geradoEm: String
        let dimensoes: Int
        let portao: Portao
        let centroides: [Centroide]

        enum CodingKeys: String, CodingKey {
            case versao
            case geradoEm = "gerado_em"
            case dimensoes
            case portao = "portao_28"
            case centroides
        }
    }

    struct Sugestao: Equatable {
        let termoId: String
        let dimensao: String
        /// Cosseno contra o centroide, em [-1, 1].
        let semelhanca: Double
        let nImagensDoCentroide: Int
    }

    /// Centroide com menos imagens que isto não vira sugestão: a média de meia
    /// dúzia de fotos descreve aquelas fotos, não o termo.
    static let imagensMinimasNoCentroide = 30

    /// Abaixo disto a semelhança não separa nada. Valor provisório: o
    /// definitivo sai da mesma medição que preenche o `portao_28`, e enquanto
    /// o portão estiver fechado ele não chega a ser usado.
    static let semelhancaMinima = 0.55

    /// Quantas sugestões por dimensão. Mais que isso não é sugestão, é lista.
    static let porDimensao = 2

    // MARK: - Matemática, testável sem Vision e sem imagem

    /// Cosseno entre dois vetores. Devolve `nil` se as formas não batem ou se
    /// algum deles é nulo -- caso em que "semelhança" não quer dizer nada.
    static func cosseno(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var produto = 0.0, normaA = 0.0, normaB = 0.0
        for i in 0..<a.count {
            produto += a[i] * b[i]
            normaA += a[i] * a[i]
            normaB += b[i] * b[i]
        }
        guard normaA > 0, normaB > 0 else { return nil }
        return produto / (normaA.squareRoot() * normaB.squareRoot())
    }

    /// Ordena os centroides por semelhança e aplica os cortes.
    ///
    /// Separado da Vision de propósito: é aqui que mora a decisão do que vira
    /// sugestão, e decisão precisa de teste. O que a Vision faz é produzir o
    /// vetor.
    static func ranquear(vetorDaFoto vetor: [Double], painel: Painel) -> [Sugestao] {
        // O portão da §28 vem primeiro. Enquanto o artefato não declarar que
        // passou, não há sugestão nenhuma -- nem fraca, nem "só de dica".
        guard painel.portao.passou else { return [] }

        var porDimensaoAchados: [String: [Sugestao]] = [:]
        for c in painel.centroides {
            guard c.nImagens >= imagensMinimasNoCentroide,
                  let s = cosseno(vetor, c.vetor),
                  s >= semelhancaMinima else { continue }
            porDimensaoAchados[c.dimensao, default: []].append(
                Sugestao(termoId: c.termoId, dimensao: c.dimensao,
                         semelhanca: s, nImagensDoCentroide: c.nImagens))
        }

        return porDimensaoAchados.values
            .flatMap { achados -> [Sugestao] in
                achados.sorted {
                    // Empate de cosseno resolve pelo id, para o resultado ser
                    // determinístico -- tela que troca de ordem a cada leitura
                    // parece quebrada.
                    ($0.semelhanca, $1.termoId) > ($1.semelhanca, $0.termoId)
                }
                .prefix(porDimensao)
                .map { $0 }
            }
            .sorted { ($0.semelhanca, $1.termoId) > ($1.semelhanca, $0.termoId) }
    }

    // MARK: - Carga do artefato

    /// Lê o painel embarcado. `nil` quando não há artefato -- que é o estado
    /// até a primeira geração no runner residencial.
    static func painelEmbarcado(_ bundle: Bundle = .main) -> Painel? {
        guard let url = bundle.url(forResource: "centroides_do_painel",
                                   withExtension: "json"),
              let dados = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Painel.self, from: dados)
    }

    // MARK: - Vision

    #if canImport(Vision)
    /// Vetor semântico da imagem, pela Vision do próprio sistema.
    static func vetor(de imagem: CGImage) -> [Double]? {
        let pedido = VNGenerateImageFeaturePrintRequest()
        do {
            try VNImageRequestHandler(cgImage: imagem, options: [:]).perform([pedido])
        } catch {
            return nil
        }
        guard let obs = pedido.results?.first as? VNFeaturePrintObservation else {
            return nil
        }
        // O buffer vem como `Float`; a conta toda roda em `Double` para o
        // cosseno não perder dígito em vetor de 768 dimensões.
        let n = obs.elementCount
        var saida = [Double](repeating: 0, count: n)
        obs.data.withUnsafeBytes { bruto in
            let floats = bruto.bindMemory(to: Float.self)
            for i in 0..<min(n, floats.count) { saida[i] = Double(floats[i]) }
        }
        return saida
    }

    /// Sugestões para uma imagem, ou vazio quando não há artefato, quando o
    /// portão da §28 está fechado, ou quando nada passou do corte.
    static func sugerir(_ imagem: CGImage, painel: Painel? = nil) -> [Sugestao] {
        guard let painel = painel ?? painelEmbarcado(),
              let v = vetor(de: imagem),
              v.count == painel.dimensoes else { return [] }
        return ranquear(vetorDaFoto: v, painel: painel)
    }
    #endif
}
