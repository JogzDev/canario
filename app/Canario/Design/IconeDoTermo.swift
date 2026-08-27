import SwiftUI

/// O ícone de um termo, seja ele do SF Symbols, desenhado por nós ou a própria
/// cor. Uma view só, para a grade nunca precisar saber de onde veio o desenho.
struct IconeDoTermo: View {
    let termoId: String
    var lado: CGFloat = 26

    var body: some View {
        switch IconeDaTaxonomia.para(id: termoId) {
        case .sistema(let nome):
            Image(systemName: nome)
                .font(.system(size: lado, weight: .regular))
                .frame(width: lado * 1.15, height: lado * 1.15)

        case .desenhado(let glifo):
            GlifoDeVestuario(glifo: glifo)
                .stroke(style: StrokeStyle(
                    lineWidth: lado * GlifoDeVestuario.pesoDoTraco,
                    lineCap: .round, lineJoin: .round))
                .frame(width: lado * 1.15, height: lado * 1.15)

        case .amostraDeCor:
            AmostraDeCor(termoId: termoId, lado: lado * 1.15)

        case nil:
            // Termo que a taxonomia trouxe e este app ainda não conhece. Some
            // o ícone, fica o rótulo -- e o termo continua selecionável, que é
            // o que importa. Sumir com a opção seria pior que sumir com o
            // desenho dela.
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: lado * 1.15, height: lado * 1.15)
                .opacity(0.35)
        }
    }
}

/// A amostra de uma família de cor.
///
/// `outras_cores` não tem uma cor: ela é o resto. Um círculo cinza mentiria
/// dizendo "cinza", e `cinza` já existe ao lado. Um gradiente diz "várias",
/// que é o que a família significa.
private struct AmostraDeCor: View {
    let termoId: String
    let lado: CGFloat

    var body: some View {
        Group {
            if termoId == "outras_cores" {
                Circle().fill(
                    AngularGradient(colors: [.red, .orange, .yellow, .green,
                                             .blue, .purple, .red],
                                    center: .center))
            } else if let rgb = CorDaPeca.rgbRepresentativo(de: termoId) {
                Circle().fill(Color(red: rgb.0, green: rgb.1, blue: rgb.2))
            } else {
                Circle().fill(Tokens.Cor.superficie)
            }
        }
        // Sem contorno, branco e cru desaparecem no fundo claro -- o mesmo
        // motivo que o chip antigo já tinha para desenhar a borda.
        .overlay(Circle().strokeBorder(Tokens.Cor.borda, lineWidth: 0.5))
        .frame(width: lado, height: lado)
    }
}

/// Um atributo na grade: círculo com o ícone, rótulo embaixo, anel quando
/// escolhido e — só na cor — a posição de prioridade.
struct BotaoDeAtributo: View {
    let termo: Termo
    let ativo: Bool
    /// 1, 2 ou 3 quando este termo ocupa uma posição de prioridade. `nil` em
    /// toda dimensão que não é cor.
    var prioridade: Int?
    let acao: () -> Void

    private var ehCor: Bool { termo.dimensao == "cor" }

    var body: some View {
        Button(action: acao) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(ehCor ? Color.clear : Tokens.Cor.ceu)
                        .frame(width: 60, height: 60)
                    IconeDoTermo(termoId: termo.id, lado: ehCor ? 52 : 26)
                        .foregroundStyle(Tokens.Cor.noite)
                    if ativo {
                        Circle()
                            .strokeBorder(Tokens.Cor.acao, lineWidth: 3)
                            .frame(width: 60, height: 60)
                    }
                    if let prioridade {
                        MarcaDePrioridade(posicao: prioridade)
                    }
                }
                .frame(width: 60, height: 60)

                Text(Traducao.rotuloExibido(termo))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Tokens.Cor.tinta)
                    .lineLimit(2)
                    // Sem isto, "Conversational prints" quebra NO MEIO da
                    // palavra -- "Conversation" / "al prints" -- porque a
                    // primeira palavra sozinha já não cabe em 72 pt. Encolher
                    // um pouco é menos feio que partir palavra.
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
                    .frame(width: 76)
            }
        }
        .buttonStyle(.plain)
        // Alvo mínimo de toque da HIG, mesmo com o círculo desenhado em 60.
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rotuloFalado)
        .accessibilityAddTraits(ativo ? [.isButton, .isSelected] : .isButton)
    }

    /// O VoiceOver precisa dizer a posição, não só que está marcado: "segunda
    /// cor" e "terceira cor" são informações diferentes, e quem não vê o
    /// número dentro do círculo não tem outro jeito de saber.
    private var rotuloFalado: String {
        let nome = Traducao.rotuloExibido(termo)
        guard let prioridade else { return nome }
        let posicao = ["", "primary", "secondary", "third"][min(prioridade, 3)]
        return "\(nome), \(posicao) color"
    }
}

/// O número dentro do círculo da cor escolhida.
///
/// Ele não é contagem, é ordem: 1 é a cor principal da peça, 2 a secundária,
/// 3 a terceira. Fica sobre a amostra porque é dela que ele fala, e ganha
/// contorno claro porque precisa sobreviver tanto sobre preto quanto sobre
/// branco e cru.
private struct MarcaDePrioridade: View {
    let posicao: Int

    var body: some View {
        Text("\(posicao)")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Tokens.Cor.acao)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Tokens.Cor.fundo))
            .overlay(Circle().strokeBorder(Tokens.Cor.acao, lineWidth: 2.5))
    }
}
