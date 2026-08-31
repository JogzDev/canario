import SwiftUI

/// Todos os similares mapeados, do que mais casa para o que menos casa.
///
/// **Por que uma tela e não uma folha que sobe.** O conjunto pode ter dezenas
/// de peças, e cada cartão carrega quatro informações que só valem se puderem
/// ser lidas: quanto casou e o que faltou, a grade de tamanhos, a remarcação e
/// o link para a loja. Numa folha, ou o conteúdo fica espremido ou a rolagem
/// dela briga com a rolagem de trás. Numa tela cheia, cada cartão tem a largura
/// inteira e o título diz de qual peça a lista é.
///
/// **A ordem é a do casamento, não a do banco.** A vitrine do painel mostra
/// quatro; aqui a pergunta é outra -- "o que mais se parece com a minha?" --, e
/// a resposta precisa começar pelo topo. Empate desempata pelo preço mais
/// baixo, que é o critério que o comprador usaria de qualquer forma.
struct TodosOsSimilares: View {
    let resumo: Similares.Resumo
    let pecas: [Similares.Peca]
    let atributos: [Termo]
    var precoAlvo: Double?
    let nomeDaPeca: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                // O critério primeiro, como no painel: quantos casaram, com
                // quantos atributos, e o que foi relaxado para chegar neles.
                Cartao {
                    Text("How these were matched")
                        .font(Tokens.Fonte.secao)
                    LinhaInsumo(texto: Similares.criterio(resumo))
                    if let leitura = Similares.leituraDoPreco(resumo, alvo: precoAlvo) {
                        LinhaInsumo(texto: leitura)
                    }
                }

                ForEach(ordenadas) { peca in
                    CartaoDeSimilar(peca: peca, pedidos: atributos)
                }

                if resumo.nSimilares > pecas.count {
                    LinhaInsumo(texto: "Showing \(pecas.count) of \(resumo.nSimilares), "
                              + "including one of the closest matches per brand. "
                              + "Percentages above use all \(resumo.nSimilares) matches.")
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .navigationTitle("Similar to \(nomeDaPeca)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Mais atributos em comum primeiro; empate resolve pelo preço mais baixo,
    /// e a peça sem preço vai para o fim do próprio empate em vez de para o
    /// topo, que é onde um `nil` tratado como zero a colocaria.
    private var ordenadas: [Similares.Peca] {
        pecas.sorted { esquerda, direita in
            if esquerda.emComum != direita.emComum {
                return esquerda.emComum > direita.emComum
            }
            return (esquerda.preco ?? .greatestFiniteMagnitude)
                 < (direita.preco ?? .greatestFiniteMagnitude)
        }
    }
}

/// Um similar na fileira do painel: foto, marca e o quanto casou.
///
/// **A marca sai em texto, não em logo.** O JP pediu logo, e a fileira está
/// desenhada para receber um: caixa de altura fixa, alinhamento e espaço já
/// reservados. O que falta é o arquivo. Logo é ativo de terceiro -- precisa ser
/// embarcado por marca, mantido quando a identidade muda e some quando entra
/// marca nova, e são 15 no painel. Enquanto os arquivos não existem, o nome em
/// versalete espaçado é a versão honesta da mesma ideia: uniforme entre marcas,
/// sempre correto, e trocável por `Image` numa linha quando houver o que trocar.
struct MiniaturaDeSimilar: View {
    let peca: Similares.Peca
    var pedidos: [Termo] = []

    private var destino: URL? {
        guard let u = peca.url else { return nil }
        return URL(string: u)
    }

    var body: some View {
        Group {
            if let destino {
                Link(destination: destino) { conteudo }
            } else {
                conteudo
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rotuloFalado)
        .accessibilityAddTraits(destino == nil ? [] : .isLink)
    }

    private var conteudo: some View {
        VStack(spacing: Tokens.Espaco.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Tokens.Cor.superficie)
                if let imagem = peca.imagem, let url = URL(string: imagem) {
                    AsyncImage(url: url) { fase in
                        switch fase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .failure:
                            // A loja tirou a foto do ar. O bloco de cor do A6
                            // continua existindo e diz o que dá para dizer.
                            MarcaVisual(peca: peca)
                        case .empty:
                            ProgressView().controlSize(.small)
                        @unknown default:
                            MarcaVisual(peca: peca)
                        }
                    }
                } else {
                    MarcaVisual(peca: peca)
                }
            }
            .frame(width: 104, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Caixa de altura fixa: o dia em que entrar `Image(logo)` no lugar
            // do texto, a fileira não muda de altura nem se desalinha.
            Text(peca.marca.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Tokens.Cor.tintaFraca)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 104, height: 14)

            if let casamento = Similares.casamento(peca, pedidos: pedidos) {
                Text(casamento)
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 104)
            }
        }
    }

    private var rotuloFalado: String {
        [peca.marca, peca.titulo ?? "",
         Similares.casamento(peca, pedidos: pedidos) ?? "",
         destino == nil ? "" : "opens the brand's website"]
        .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
