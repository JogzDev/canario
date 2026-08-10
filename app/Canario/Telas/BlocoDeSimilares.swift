import SwiftUI

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
            Text("Peças parecidas no painel").font(Tokens.Fonte.secao)
            LinhaInsumo(texto: Similares.criterio(resumo))

            if let leitura = Similares.leituraDoPreco(resumo, alvo: precoAlvo) {
                Cartao {
                    Text("Onde o seu preço cai").font(Tokens.Fonte.miudo.weight(.semibold))
                    Text(leitura).font(Tokens.Fonte.apoio)
                }
            }

            ForEach(pecas) { peca in
                CartaoDeSimilar(peca: peca)
            }

            if resumo.nSimilares > pecas.count {
                LinhaInsumo(texto: "Mostrando \(pecas.count) de \(resumo.nSimilares), "
                          + "uma das mais parecidas por marca. As porcentagens acima são sobre as \(resumo.nSimilares).")
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
                        Link("ver no site da marca", destination: link)
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
                    AsyncImage(url: endereco) { fase in
                        if case .success(let img) = fase {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .transition(.opacity)
                        }
                    }
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
