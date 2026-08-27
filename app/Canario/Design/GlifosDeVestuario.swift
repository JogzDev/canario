import SwiftUI

/// Os glifos que o SF Symbols não tem, desenhados no mesmo idioma dele.
///
/// **A regra de desenho, e por que ela importa.** Um símbolo do sistema é um
/// traço de espessura constante, com pontas e junções arredondadas, desenhado
/// numa caixa quadrada com folga nas bordas. Se um glifo nosso ficar mais
/// grosso, mais fino ou mais cheio que os vizinhos, a grade inteira denuncia
/// qual ícone é da Apple e qual é nosso — e é exatamente essa costura que a
/// gente não quer que apareça.
///
/// Por isso tudo aqui é desenhado num quadrado 0…1, contornado com
/// `lineWidth` proporcional ao tamanho e com `lineCap`/`lineJoin` redondos.
/// Nada é preenchido: o SF Symbols do peso `regular` também não é.
struct GlifoDeVestuario: Shape {
    let glifo: IconeDaTaxonomia.Glifo

    /// Proporção do lado que vira espessura do traço. 0,075 é o que faz um
    /// glifo de 24 pt encostar no peso do `tshirt` ao lado dele.
    static let pesoDoTraco: CGFloat = 0.075

    func path(in rect: CGRect) -> Path {
        // Quadrado central: glifo em caixa retangular fica torto ao lado de um
        // símbolo do sistema, que é sempre quadrado.
        let lado = min(rect.width, rect.height)
        let origem = CGPoint(x: rect.midX - lado / 2, y: rect.midY - lado / 2)
        // Folga para o traço não ser cortado pela borda da caixa.
        let folga = lado * Self.pesoDoTraco
        let util = lado - folga * 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origem.x + folga + x * util,
                    y: origem.y + folga + y * util)
        }

        var caminho = Path()

        switch glifo {

        // MARK: - Categoria

        case .camisa:
            // Corpo com ombros caídos, gola em V e carreira de botões. É o
            // `tshirt` do sistema mais as duas coisas que fazem uma camisa ser
            // camisa: colarinho e abotoamento.
            caminho.move(to: p(0.50, 0.20))
            caminho.addLine(to: p(0.30, 0.12))
            caminho.addLine(to: p(0.06, 0.30))
            caminho.addLine(to: p(0.20, 0.44))
            caminho.addLine(to: p(0.26, 0.38))
            caminho.addLine(to: p(0.26, 0.92))
            caminho.addLine(to: p(0.74, 0.92))
            caminho.addLine(to: p(0.74, 0.38))
            caminho.addLine(to: p(0.80, 0.44))
            caminho.addLine(to: p(0.94, 0.30))
            caminho.addLine(to: p(0.70, 0.12))
            caminho.closeSubpath()
            // Colarinho: duas pontas caindo do decote.
            caminho.move(to: p(0.38, 0.15))
            caminho.addLine(to: p(0.50, 0.32))
            caminho.addLine(to: p(0.62, 0.15))
            // Placket.
            caminho.move(to: p(0.50, 0.36))
            caminho.addLine(to: p(0.50, 0.90))

        case .vestido:
            // Corpo justo até a cintura e saia em A. O ponto que define o
            // vestido é a cintura marcada: sem ela, vira túnica.
            caminho.move(to: p(0.50, 0.18))
            caminho.addLine(to: p(0.32, 0.10))
            caminho.addLine(to: p(0.12, 0.26))
            caminho.addLine(to: p(0.24, 0.38))
            caminho.addLine(to: p(0.30, 0.32))
            caminho.addLine(to: p(0.34, 0.50))
            caminho.addLine(to: p(0.14, 0.92))
            caminho.addLine(to: p(0.86, 0.92))
            caminho.addLine(to: p(0.66, 0.50))
            caminho.addLine(to: p(0.70, 0.32))
            caminho.addLine(to: p(0.76, 0.38))
            caminho.addLine(to: p(0.88, 0.26))
            caminho.addLine(to: p(0.68, 0.10))
            caminho.closeSubpath()
            // Cintura.
            caminho.move(to: p(0.34, 0.50))
            caminho.addLine(to: p(0.66, 0.50))

        case .saia:
            // Cós reto e corpo em A. Sem ombro nenhum: é o que separa saia de
            // vestido numa grade pequena.
            caminho.move(to: p(0.28, 0.20))
            caminho.addLine(to: p(0.72, 0.20))
            caminho.addLine(to: p(0.72, 0.32))
            caminho.addLine(to: p(0.90, 0.86))
            caminho.addLine(to: p(0.10, 0.86))
            caminho.addLine(to: p(0.28, 0.32))
            caminho.closeSubpath()
            // Linha do cós.
            caminho.move(to: p(0.28, 0.32))
            caminho.addLine(to: p(0.72, 0.32))

        case .calca:
            caminho.addPath(Self.pernas(p: p, alturaDaBarra: 0.92, abertura: 0.0))

        case .short:
            // Mesma construção da calça com a barra na coxa: a comparação
            // entre as duas fica óbvia porque só o comprimento muda.
            caminho.addPath(Self.pernas(p: p, alturaDaBarra: 0.60, abertura: 0.03))

        case .macacao:
            // Uma peça só: tronco de blusa emendado nas pernas da calça, sem
            // linha de cintura separando — que é literalmente o que define
            // macacão.
            caminho.move(to: p(0.50, 0.16))
            caminho.addLine(to: p(0.32, 0.09))
            caminho.addLine(to: p(0.14, 0.24))
            caminho.addLine(to: p(0.25, 0.35))
            caminho.addLine(to: p(0.30, 0.30))
            caminho.addLine(to: p(0.28, 0.92))
            caminho.addLine(to: p(0.46, 0.92))
            caminho.addLine(to: p(0.50, 0.58))
            caminho.addLine(to: p(0.54, 0.92))
            caminho.addLine(to: p(0.72, 0.92))
            caminho.addLine(to: p(0.70, 0.30))
            caminho.addLine(to: p(0.75, 0.35))
            caminho.addLine(to: p(0.86, 0.24))
            caminho.addLine(to: p(0.68, 0.09))
            caminho.closeSubpath()

        // MARK: - Tecido

        case .jeans:
            // Bolso traseiro com pesponto: é o sinal gráfico do jeans que
            // qualquer pessoa reconhece sem legenda.
            caminho.move(to: p(0.18, 0.22))
            caminho.addLine(to: p(0.82, 0.22))
            caminho.addLine(to: p(0.74, 0.66))
            caminho.addLine(to: p(0.50, 0.84))
            caminho.addLine(to: p(0.26, 0.66))
            caminho.closeSubpath()
            caminho.move(to: p(0.26, 0.36))
            caminho.addLine(to: p(0.74, 0.36))

        case .couro:
            // Silhueta de pele curtida: assimétrica de propósito, porque
            // couro não vem em retângulo.
            caminho.move(to: p(0.22, 0.16))
            caminho.addCurve(to: p(0.80, 0.22),
                             control1: p(0.46, 0.06), control2: p(0.66, 0.10))
            caminho.addCurve(to: p(0.84, 0.72),
                             control1: p(0.94, 0.36), control2: p(0.72, 0.52))
            caminho.addCurve(to: p(0.30, 0.84),
                             control1: p(0.94, 0.90), control2: p(0.50, 0.94))
            caminho.addCurve(to: p(0.22, 0.16),
                             control1: p(0.10, 0.74), control2: p(0.06, 0.34))
            caminho.closeSubpath()

        case .malha:
            // Duas fileiras de ponto tricô. O V repetido é o desenho da malha,
            // e ele lê mesmo em 24 pt.
            for fileira in 0..<2 {
                let topo = 0.28 + CGFloat(fileira) * 0.28
                for coluna in 0..<3 {
                    let x = 0.16 + CGFloat(coluna) * 0.28
                    caminho.move(to: p(x, topo))
                    caminho.addLine(to: p(x + 0.14, topo + 0.20))
                    caminho.addLine(to: p(x + 0.28, topo))
                }
            }

        // MARK: - Comprimento

        case .comprimentoCurto:
            caminho.addPath(Self.silhuetaComBarra(p: p, barra: 0.46))
        case .comprimentoMidi:
            caminho.addPath(Self.silhuetaComBarra(p: p, barra: 0.68))
        case .comprimentoLongo:
            caminho.addPath(Self.silhuetaComBarra(p: p, barra: 0.90))

        // MARK: - Silhueta

        case .silhuetaFlare:
            // Justa no quadril, abrindo na barra.
            caminho.move(to: p(0.32, 0.14))
            caminho.addLine(to: p(0.68, 0.14))
            caminho.addLine(to: p(0.88, 0.90))
            caminho.addLine(to: p(0.56, 0.90))
            caminho.addLine(to: p(0.50, 0.50))
            caminho.addLine(to: p(0.44, 0.90))
            caminho.addLine(to: p(0.12, 0.90))
            caminho.closeSubpath()

        case .silhuetaReta:
            // Mesma largura do cós até a barra.
            caminho.move(to: p(0.26, 0.14))
            caminho.addLine(to: p(0.74, 0.14))
            caminho.addLine(to: p(0.74, 0.90))
            caminho.addLine(to: p(0.54, 0.90))
            caminho.addLine(to: p(0.50, 0.50))
            caminho.addLine(to: p(0.46, 0.90))
            caminho.addLine(to: p(0.26, 0.90))
            caminho.closeSubpath()

        // MARK: - Cintura

        case .cinturaAlta:
            caminho.addPath(Self.calcaComCos(p: p, cos: 0.16))
        case .cinturaMedia:
            caminho.addPath(Self.calcaComCos(p: p, cos: 0.28))
        case .cinturaBaixa:
            caminho.addPath(Self.calcaComCos(p: p, cos: 0.40))

        // MARK: - Motivos de estampa

        case .tomate:
            caminho.addEllipse(in: Self.caixa(p: p, x: 0.16, y: 0.30,
                                              largura: 0.68, altura: 0.60))
            // Sépalas: três pontas saindo do cabinho.
            caminho.move(to: p(0.50, 0.32))
            caminho.addLine(to: p(0.50, 0.12))
            caminho.move(to: p(0.30, 0.24))
            caminho.addLine(to: p(0.50, 0.30))
            caminho.addLine(to: p(0.70, 0.24))

        case .cereja:
            caminho.addEllipse(in: Self.caixa(p: p, x: 0.10, y: 0.56,
                                              largura: 0.34, altura: 0.34))
            caminho.addEllipse(in: Self.caixa(p: p, x: 0.54, y: 0.62,
                                              largura: 0.32, altura: 0.32))
            caminho.move(to: p(0.27, 0.56))
            caminho.addCurve(to: p(0.62, 0.14),
                             control1: p(0.34, 0.34), control2: p(0.48, 0.18))
            caminho.move(to: p(0.70, 0.62))
            caminho.addCurve(to: p(0.62, 0.14),
                             control1: p(0.72, 0.40), control2: p(0.66, 0.24))

        case .morango:
            // Corpo em gota invertida e coroa de folhas.
            caminho.move(to: p(0.16, 0.38))
            caminho.addCurve(to: p(0.50, 0.92),
                             control1: p(0.16, 0.70), control2: p(0.34, 0.92))
            caminho.addCurve(to: p(0.84, 0.38),
                             control1: p(0.66, 0.92), control2: p(0.84, 0.70))
            caminho.closeSubpath()
            caminho.move(to: p(0.24, 0.32))
            caminho.addLine(to: p(0.50, 0.42))
            caminho.addLine(to: p(0.76, 0.32))
            caminho.move(to: p(0.50, 0.42))
            caminho.addLine(to: p(0.50, 0.14))

        case .banana:
            // Duas curvas paralelas com as pontas fechadas.
            caminho.move(to: p(0.16, 0.20))
            caminho.addCurve(to: p(0.84, 0.74),
                             control1: p(0.24, 0.66), control2: p(0.52, 0.86))
            caminho.addLine(to: p(0.86, 0.60))
            caminho.addCurve(to: p(0.28, 0.16),
                             control1: p(0.58, 0.66), control2: p(0.34, 0.48))
            caminho.closeSubpath()

        case .abacaxi:
            caminho.move(to: p(0.30, 0.40))
            caminho.addCurve(to: p(0.50, 0.92),
                             control1: p(0.26, 0.72), control2: p(0.36, 0.92))
            caminho.addCurve(to: p(0.70, 0.40),
                             control1: p(0.64, 0.92), control2: p(0.74, 0.72))
            caminho.closeSubpath()
            // Coroa.
            caminho.move(to: p(0.36, 0.40))
            caminho.addLine(to: p(0.42, 0.12))
            caminho.addLine(to: p(0.50, 0.34))
            caminho.addLine(to: p(0.58, 0.12))
            caminho.addLine(to: p(0.64, 0.40))
            // Uma linha de losango, que é o que faz ler abacaxi e não pera.
            caminho.move(to: p(0.32, 0.58))
            caminho.addLine(to: p(0.68, 0.58))

        case .melancia:
            // Fatia: meia-lua com casca e uma semente.
            caminho.move(to: p(0.10, 0.34))
            caminho.addArc(center: p(0.50, 0.34),
                           radius: 0.40 * min(rect.width, rect.height)
                                   * (1 - Self.pesoDoTraco * 2),
                           startAngle: .degrees(180), endAngle: .degrees(0),
                           clockwise: true)
            caminho.closeSubpath()
            caminho.move(to: p(0.22, 0.34))
            caminho.addLine(to: p(0.78, 0.34))
            caminho.move(to: p(0.50, 0.52))
            caminho.addLine(to: p(0.50, 0.60))
        }

        return caminho
    }

    // MARK: - Peças reaproveitadas

    private static func caixa(p: (CGFloat, CGFloat) -> CGPoint,
                              x: CGFloat, y: CGFloat,
                              largura: CGFloat, altura: CGFloat) -> CGRect {
        let canto = p(x, y)
        let oposto = p(x + largura, y + altura)
        return CGRect(x: canto.x, y: canto.y,
                      width: oposto.x - canto.x, height: oposto.y - canto.y)
    }

    /// Cós, gancho e duas pernas. `alturaDaBarra` é o que separa calça de
    /// short; `abertura` afasta as barras, porque short cai solto e calça não.
    private static func pernas(p: (CGFloat, CGFloat) -> CGPoint,
                               alturaDaBarra: CGFloat,
                               abertura: CGFloat) -> Path {
        var caminho = Path()
        caminho.move(to: p(0.24, 0.12))
        caminho.addLine(to: p(0.76, 0.12))
        caminho.addLine(to: p(0.76 + abertura, alturaDaBarra))
        caminho.addLine(to: p(0.56 + abertura, alturaDaBarra))
        caminho.addLine(to: p(0.50, 0.46))
        caminho.addLine(to: p(0.44 - abertura, alturaDaBarra))
        caminho.addLine(to: p(0.24 - abertura, alturaDaBarra))
        caminho.closeSubpath()
        // Linha do cós, que é o que impede a silhueta de virar um V solto.
        caminho.move(to: p(0.24, 0.24))
        caminho.addLine(to: p(0.76, 0.24))
        return caminho
    }

    /// Silhueta em A com a barra numa altura variável. A peça é sempre a
    /// mesma; o que muda é onde ela termina — que é a pergunta que a dimensão
    /// `comprimento` faz.
    private static func silhuetaComBarra(p: (CGFloat, CGFloat) -> CGPoint,
                                         barra: CGFloat) -> Path {
        var caminho = Path()
        let largura = 0.20 + (barra - 0.46) * 0.55
        caminho.move(to: p(0.34, 0.10))
        caminho.addLine(to: p(0.66, 0.10))
        caminho.addLine(to: p(0.50 + largura, barra))
        caminho.addLine(to: p(0.50 - largura, barra))
        caminho.closeSubpath()
        // Marca da barra, tracejada pelo próprio traço do contorno.
        caminho.move(to: p(0.50 - largura - 0.06, barra))
        caminho.addLine(to: p(0.50 + largura + 0.06, barra))
        return caminho
    }

    /// Calça com o cós numa altura variável — alta, média ou baixa. O corpo é
    /// idêntico nos três; só a faixa sobe ou desce.
    private static func calcaComCos(p: (CGFloat, CGFloat) -> CGPoint,
                                    cos: CGFloat) -> Path {
        var caminho = Path()
        caminho.move(to: p(0.26, cos))
        caminho.addLine(to: p(0.74, cos))
        caminho.addLine(to: p(0.72, 0.90))
        caminho.addLine(to: p(0.56, 0.90))
        caminho.addLine(to: p(0.50, 0.56))
        caminho.addLine(to: p(0.44, 0.90))
        caminho.addLine(to: p(0.28, 0.90))
        caminho.closeSubpath()
        caminho.move(to: p(0.26, cos + 0.10))
        caminho.addLine(to: p(0.74, cos + 0.10))
        return caminho
    }
}
