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
    /// Célula estreita, para caber cinco por linha.
    ///
    /// Dez cores em quatro colunas dão três fileiras desiguais (4+4+2) e leem
    /// como lista; em cinco dão duas fileiras cheias e leem como **paleta**,
    /// que é o que a pessoa está varrendo. Pedido do Davi, e ele tem razão.
    var compacto = false
    /// 1, 2 ou 3 quando este termo ocupa uma posição de prioridade. `nil` em
    /// toda dimensão que não é cor.
    var prioridade: Int?
    let acao: () -> Void
    @ScaledMetric(relativeTo: .caption) private var escala: CGFloat = 1

    private var ehCor: Bool { termo.dimensao == "cor" }
    private var lado: CGFloat { (compacto ? 52 : 60) * escala }
    private var larguraDoRotulo: CGFloat { (compacto ? 62 : 76) * escala }

    var body: some View {
        Button(action: acao) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(ehCor ? Color.clear : Edicao.papel)
                        .frame(width: lado, height: lado)
                    IconeDoTermo(termoId: termo.id,
                                 lado: ehCor ? lado * 0.87 : lado * 0.43)
                        .foregroundStyle(.primary)
                    if ativo {
                        Circle()
                            .strokeBorder(Edicao.bordo, lineWidth: 3)
                            .frame(width: lado, height: lado)
                    }
                    if let prioridade {
                        MarcaDePrioridade(posicao: prioridade)
                    }
                }
                .frame(width: lado, height: lado)

                Text(Traducao.rotuloExibido(termo))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    // Sem isto, "Conversational prints" quebra NO MEIO da
                    // palavra -- "Conversation" / "al prints" -- porque a
                    // primeira palavra sozinha já não cabe em 72 pt. Encolher
                    // um pouco é menos feio que partir palavra.
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
                    .frame(width: larguraDoRotulo)

                // "Romantic" pede gosto; "ruffle · lace · puff sleeve" pede
                // olhar. A legenda veio dos chips antigos e não podia sumir na
                // troca para grade: ela é o que permite responder a dimensão
                // mais subjetiva da tela sem conhecer a taxonomia.
                if let pista = Traducao.pistaDoTermo(termo) {
                    Text(pista)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .frame(width: larguraDoRotulo)
                }
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
        var partes = [Traducao.rotuloExibido(termo)]
        if let prioridade {
            partes.append(["", "primary", "secondary", "third"][min(prioridade, 3)]
                          + " color")
        }
        // A legenda entra na fala pelo mesmo motivo que entra na tela: quem
        // não conhece a taxonomia precisa dela para responder, e quem usa
        // VoiceOver precisa mais, não menos.
        if let pista = Traducao.pistaDoTermo(termo) {
            partes.append(pista.replacingOccurrences(of: " · ", with: ", "))
        }
        return partes.joined(separator: ", ")
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
        // Disco cheio, sem contorno próprio. A versão anterior tinha anel, e
        // com o anel azul da seleção em volta o conjunto virava um alvo de
        // tiro -- dois círculos concêntricos azuis sobre a cor. Azul sólido
        // com número branco resolve os dois problemas de uma vez: some o anel
        // repetido e o contraste passa a funcionar sobre qualquer amostra,
        // inclusive preto e branco e cru, que eram os dois casos difíceis.
        Text("\(posicao)")
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Edicao.bordoCheio))
    }
}
