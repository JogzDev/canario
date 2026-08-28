import SwiftUI
import ImageIO
import UIKit

/// Os cartões de similar da §29 e a representação gerada que a A6 exige.
///
/// **Por que o cartão não tem foto do produto no binário.** A A6 decidiu, quando
/// a publicação na App Store virou requisito, que o binário submetido **não
/// republica foto de produto de terceiro**. A foto que aparece vem por hotlink
/// do CDN da própria loja (A13); quando ela não existe ou cai, o cartão desce
/// para a representação gerada — bloco na família de cor, glifo de silhueta —
/// mais marca em texto, preço, remarcação e estado da grade. O toque abre a
/// página original, que é o que cumpre a rastreabilidade da regra 3.
///
/// A lista vertical que morava aqui saiu em 27/08: o painel passou a mostrar
/// uma fileira compacta no alto e a lista inteira ganhou tela própria, em
/// `TodosOsSimilares`. O que sobrou neste arquivo são as peças que as duas
/// usam.

/// Quanto a peça casa com o que foi marcado, e no que ela difere.
///
/// A §32 proíbe comunicar estado só por cor. Aqui a informação inteira está no
/// texto — "3 of 4 · no stripe" —; ícone e tom são reforço. Quem não distingue
/// cor lê exatamente a mesma coisa.
struct EtiquetaDeCasamento: View {
    let texto: String
    let completo: Bool

    var body: some View {
        HStack(spacing: Tokens.Espaco.xs) {
            Image(systemName: completo
                  ? "checkmark.circle.fill" : "circle.lefthalf.filled")
            Text(texto)
        }
        .font(Tokens.Fonte.miudo.weight(.medium))
        .foregroundStyle(completo ? Tokens.Cor.tinta : Tokens.Cor.tintaFraca)
        .padding(.horizontal, Tokens.Espaco.s)
        .padding(.vertical, Tokens.Espaco.xs)
        .background(Tokens.Cor.superficie, in: Capsule())
    }
}

/// Um similar: foto da loja por hotlink (A13), com o bloco de cor do A6 atrás
/// dela para quando não houver foto.
struct CartaoDeSimilar: View {
    let peca: Similares.Peca
    /// Os atributos que a pessoa marcou. Sem eles o card não tem como dizer no
    /// que a peça difere -- só quantos bateram, que é o que enganava.
    var pedidos: [Termo] = []

    var body: some View {
        Cartao {
            HStack(alignment: .top, spacing: Tokens.Espaco.m) {
                MarcaVisual(peca: peca)
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(peca.marca).font(Tokens.Fonte.apoio.weight(.semibold))
                        Spacer()
                        preco
                    }
                    Text(peca.titulo ?? "—")
                        .font(Tokens.Fonte.corpo)
                        .fixedSize(horizontal: false, vertical: true)
                    if let casamento = Similares.casamento(peca, pedidos: pedidos) {
                        EtiquetaDeCasamento(texto: casamento,
                                            completo: peca.emComum >= pedidos.count)
                    }
                    LinhaInsumo(texto: Similares.desfecho(peca))
                    if let u = peca.url, let link = URL(string: u) {
                        Link("View on the brand's website", destination: link)
                            .font(Tokens.Fonte.miudo)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [peca.marca, peca.titulo ?? "",
             Similares.casamento(peca, pedidos: pedidos) ?? "",
             Similares.desfecho(peca)]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }

    @ViewBuilder
    private var preco: some View {
        if let p = peca.preco {
            VStack(alignment: .trailing, spacing: 0) {
                Text(Formato.dinheiro(p)).font(Tokens.Fonte.numero)
                if let q = peca.quedaPct {
                    Text("−\(Leitura.numero(q, casas: 0))%")
                        .font(Tokens.Fonte.miudo.weight(.semibold))
                        .foregroundStyle(Tokens.Cor.queda)
                }
            }
        }
    }
}

/// A representação gerada da peça (A6).
///
/// Um bloco cuja **altura preenchida** mostra o estado da grade: cheia quando
/// todos os tamanhos estão disponíveis, vazando conforme quebra. É a leitura
/// que o comprador faz de relance, e não depende de cor — a §32 proíbe
/// comunicar estado só por cor, então o número vai ao lado, no texto.
///
/// A foto da peça, carregada do CDN da própria loja (A13).
///
/// **Hotlink, e não cópia.** O aparelho busca a imagem no servidor da marca, na
/// hora de exibir. Nada é copiado para o nosso servidor nem embutido no
/// binário, e o toque no card abre a página original — a atribuição e o
/// caminho até a origem que a regra 3 pede já existiam.
///
/// **O bloco de cor não sai de cena; ele vira o fundo.** Era o desenho do A6
/// (altura = grade disponível) e continua sendo o que aparece enquanto a foto
/// carrega, quando a loja tira a imagem do ar, e quando o produto não tem foto.
/// Card sem foto continua dizendo a mesma coisa que dizia antes.
struct MarcaVisual: View {
    let peca: Similares.Peca

    private var preenchido: Double {
        guard let g = peca.grade, g.degraus > 0 else { return 1 }
        return Double(g.disponiveis) / Double(g.degraus)
    }

    private var endereco: URL? {
        guard let i = peca.imagem, !i.isEmpty else { return nil }
        return URL(string: i)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta)
                    .fill(Tokens.Cor.superficie)
                RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta)
                    .fill(Tokens.Cor.tintaFraca.opacity(0.45))
                    .frame(height: max(2, geo.size.height * preenchido))
                if let endereco {
                    // `AsyncImage` só desenha em `.success`: em carregamento e
                    // em falha o bloco de cor fica visível sozinho, sem ícone
                    // de imagem quebrada e sem a tela pular de tamanho.
                    ImagemRemota(endereco: endereco, modo: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta)
                    .strokeBorder(Tokens.Cor.semDado.opacity(0.35), lineWidth: 1)
            )
        }
        // 34x52 era a medida do BLOCO DE COR, que é abstrato e legível em
        // qualquer tamanho. Foto de produto naquele espaço vira mancha -- o JP
        // rodou o app depois do A13 e não percebeu que havia foto. Agora é
        // 72x96: cabe a silhueta da peça, que é o que faz o card ser útil de
        // relance.
        .frame(width: 72, height: 96)
        .accessibilityHidden(true)   // o texto ao lado já diz a grade
    }
}

/// Carregador explícito das fotos de loja.
///
/// `AsyncImage` escondia completamente a causa da falha e, em alguns CDNs,
/// não voltava a tentar depois de um cancelamento durante a navegação. Este
/// caminho valida HTTP e MIME, usa cache de URL e repete uma vez apenas quando
/// a primeira conexão cai. O fallback visual continua sob ele.
struct ImagemRemota: View {
    let endereco: URL?
    var modo: ContentMode = .fit

    @State private var imagem: UIImage?

    var body: some View {
        Group {
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .aspectRatio(contentMode: modo)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .task(id: endereco) {
            imagem = await CacheDeImagemRemota.shared.imagem(em: endereco)
        }
    }
}

actor CacheDeImagemRemota {
    static let shared = CacheDeImagemRemota()
    private let memoria = NSCache<NSURL, UIImage>()
    private let sessao: URLSession

    init() {
        memoria.countLimit = 120
        memoria.totalCostLimit = 40 << 20
        let configuracao = URLSessionConfiguration.default
        configuracao.urlCache = URLCache(memoryCapacity: 16 << 20,
                                         diskCapacity: 96 << 20)
        configuracao.requestCachePolicy = .returnCacheDataElseLoad
        configuracao.httpMaximumConnectionsPerHost = 4
        configuracao.timeoutIntervalForRequest = 12
        configuracao.waitsForConnectivity = false
        sessao = URLSession(configuration: configuracao)
    }

    func imagem(em endereco: URL?) async -> UIImage? {
        guard let endereco else { return nil }
        if let existente = memoria.object(forKey: endereco as NSURL) { return existente }

        for tentativa in 0...1 {
            do {
                var pedido = URLRequest(url: endereco,
                                        cachePolicy: .returnCacheDataElseLoad,
                                        timeoutInterval: 15)
                pedido.setValue("image/avif,image/webp,image/*,*/*;q=0.8",
                                forHTTPHeaderField: "Accept")
                let (dados, resposta) = try await sessao.data(for: pedido)
                let http = resposta as? HTTPURLResponse
                let codigo = http?.statusCode ?? 0
                if codigo >= 500 && tentativa == 0 {
                    throw URLError(.badServerResponse)
                }
                guard (200..<300).contains(codigo),
                      http?.mimeType?.hasPrefix("image/") == true,
                      let resultado = miniatura(dados) else { return nil }
                let custo = Int(resultado.size.width * resultado.size.height * 4)
                memoria.setObject(resultado, forKey: endereco as NSURL, cost: custo)
                return resultado
            } catch where tentativa == 0 {
                continue
            } catch {
                return nil
            }
        }
        return nil
    }

    /// CDNs entregam fotos de vários megapixels para cards de 38–108 pt.
    /// Decodificar o original fazia o scroll carregar dezenas de bitmaps de
    /// 20–40 MB. O ImageIO cria diretamente uma miniatura de até 384 px.
    private func miniatura(_ dados: Data) -> UIImage? {
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(fonte, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 384,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
