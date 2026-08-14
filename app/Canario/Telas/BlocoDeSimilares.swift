import SwiftUI
import ImageIO
import UIKit

/// O bloco de similares da §29, e os cartões que a A6 exige.
///
/// **Por que o cartão não tem foto do produto.** A A6 decidiu, quando a
/// publicação na App Store virou requisito, que o binário submetido **não
/// republica foto de produto de terceiro**. Cada cartão é representação gerada
/// dos atributos — bloco na família de cor, glifo de silhueta — mais marca em
/// texto, preço, remarcação e estado da grade. O toque abre a página original,
/// que é o que cumpre a rastreabilidade da regra 3.
///
/// O desenho definitivo é tarefa da Bianca. O que está aqui usa só os tokens
/// neutros e existe para a função rodar antes do design — trocar depois é mexer
/// em `MarcaVisual`, não na tela.
struct BlocoDeSimilares: View {
    let resumo: Similares.Resumo
    let pecas: [Similares.Peca]
    let atributos: [Termo]
    var precoAlvo: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            Text("Similar pieces in the panel").font(Tokens.Fonte.secao)
            LinhaInsumo(texto: Similares.criterio(resumo))

            if let leitura = Similares.leituraDoPreco(resumo, alvo: precoAlvo) {
                Cartao {
                    Text("Where your price falls").font(Tokens.Fonte.miudo.weight(.semibold))
                    Text(leitura).font(Tokens.Fonte.apoio)
                }
            }

            ForEach(pecas.filter(Similares.podeExibir)) { peca in
                CartaoDeSimilar(peca: peca)
            }

            if resumo.nSimilares > pecas.count {
                LinhaInsumo(texto: "Showing \(pecas.count) of \(resumo.nSimilares), "
                          + "including one of the closest matches per brand. Percentages above use all \(resumo.nSimilares) matches.")
            }
        }
    }
}

/// Um similar: foto da loja por hotlink (A13), com o bloco de cor do A6 atrás
/// dela para quando não houver foto.
struct CartaoDeSimilar: View {
    let peca: Similares.Peca

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
                    LinhaInsumo(texto: Similares.desfecho(peca))
                    if let u = peca.url, let link = URL(string: u) {
                        Link("View on the brand's website", destination: link)
                            .font(Tokens.Fonte.miudo)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(peca.marca), \(peca.titulo ?? ""). \(Similares.desfecho(peca))")
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
