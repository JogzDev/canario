import SwiftUI
import AppKit
import CoreText

// MARK: - Tokens da v4 (Edicao.swift), claro e escuro

extension Color {
    init(_ hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: a)
    }
}

struct Tema {
    let papel, cartao, tinta, bordo, caneta, marcaTexto, peca, grafite: Color
    /// No ícone escuro o bordô precisa acender sem virar rosa.
    var bordoDoIcone: Color { self.papel == Color(0x1A1917) ? Color(0xC8374F) : bordo }
    static let claro = Tema(papel: Color(0xF7F5EF), cartao: Color(0xFFFFFF), tinta: Color(0x1C1B19),
                            bordo: Color(0x8A1C2E), caneta: Color(0x2743D6), marcaTexto: Color(0xF7E27A),
                            peca: Color(0xCBCBCB), grafite: Color(0x6A6760))
    static let escuro = Tema(papel: Color(0x1A1917), cartao: Color(0x262523), tinta: Color(0xF2EFE8),
                             bordo: Color(0xF0899A), caneta: Color(0x8FA2FF), marcaTexto: Color(0x5E5421),
                             peca: Color(0x3A3936), grafite: Color(0xB9B5AC))
}

// MARK: - Geometria

/// Contorno real de um glifo da New York, centrado no quadro pedido.
struct Glifo: Shape {
    let caractere: String
    let peso: NSFont.Weight
    let altura: CGFloat   // fração da altura do quadro ocupada pelo glifo

    func path(in rect: CGRect) -> Path {
        let base = NSFont.systemFont(ofSize: 1000, weight: peso).fontDescriptor.withDesign(.serif)!
        let fonte = NSFont(descriptor: base, size: 1000)! as CTFont
        var unichars = Array(caractere.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
        CTFontGetGlyphsForCharacters(fonte, &unichars, &glyphs, unichars.count)
        guard let cg = CTFontCreatePathForGlyph(fonte, glyphs[0], nil) else { return Path() }
        var p = Path(cg)
        let b = p.boundingRect
        let escala = rect.height * altura / b.height
        p = p.applying(CGAffineTransform(scaleX: escala, y: -escala))
        let nb = p.boundingRect
        return p.offsetBy(dx: rect.midX - nb.midX, dy: rect.midY - nb.midY)
    }
}

/// Um S feito de dois arcos, amostrado em pontos: serve de fita e de linha.
struct CurvaS {
    let pontos: [CGPoint]
    init(em r: CGRect, raio: CGFloat, amostras: Int = 400) {
        let c = CGPoint(x: r.midX, y: r.midY)
        let cima = CGPoint(x: c.x, y: c.y - raio), baixo = CGPoint(x: c.x, y: c.y + raio)
        var pts: [CGPoint] = []
        let a0 = -25.0, a1 = -270.0
        for i in 0...amostras {
            let a = (a0 + (a1 - a0) * Double(i) / Double(amostras)) * .pi / 180
            pts.append(CGPoint(x: cima.x + raio * cos(a), y: cima.y + raio * sin(a)))
        }
        let b0 = -90.0, b1 = 155.0
        for i in 1...amostras {
            let a = (b0 + (b1 - b0) * Double(i) / Double(amostras)) * .pi / 180
            pts.append(CGPoint(x: baixo.x + raio * cos(a), y: baixo.y + raio * sin(a)))
        }
        pontos = pts
    }
    var caminho: Path { Path { p in p.addLines(pontos) } }
}

struct Tracado: Shape {
    let fazer: @Sendable (CGRect) -> Path
    func path(in rect: CGRect) -> Path { fazer(rect) }
}

// MARK: - Fundo de papel pontilhado

struct PapelPontilhado: View {
    let tema: Tema
    var passo: CGFloat = 22
    var tinta: Double = 0.11
    var body: some View {
        Canvas { ctx, size in
            var y = passo / 2
            while y < size.height {
                var x = passo / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6)),
                             with: .color(tema.tinta.opacity(tinta)))
                    x += passo
                }
                y += passo
            }
        }
        .background(tema.papel)
    }
}

// MARK: - Três direções de ícone (quadro 1024, a máscara do iOS vem depois)

/// Remendo: o S da New York costurado como um patch de ateliê.
struct IconeRemendo: View {
    let tema: Tema
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            let glifo = Glifo(caractere: "S", peso: .heavy, altura: 0.60)
            ZStack {
                PapelPontilhado(tema: tema, passo: s * 0.055, tinta: 0.10)
                glifo.fill(tema.bordoDoIcone)
                // costura: pontos retos por dentro da borda, como num patch
                glifo.stroke(tema.papel.opacity(0.95),
                             style: StrokeStyle(lineWidth: s * 0.062, lineCap: .butt,
                                                dash: [s * 0.030, s * 0.022]))
                    .clipShape(glifo)
                glifo.stroke(tema.bordoDoIcone, lineWidth: s * 0.036).clipShape(glifo)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Fita métrica: "Fashion, measured" dito sem palavra nenhuma.
struct IconeFita: View {
    let tema: Tema
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            let quadro = CGRect(x: 0, y: 0, width: s, height: s)
            let curva = CurvaS(em: quadro, raio: s * 0.165)
            let largura = s * 0.118
            ZStack {
                (tema.papel == Color(0x1A1917) ? Color(0x4A0F1A) : tema.bordo)
                curva.caminho.stroke(Color(0xF7E27A), style: StrokeStyle(lineWidth: largura, lineCap: .butt))
                Tracado { _ in marcas(curva, largura: largura, s: s) }
                    .stroke(Color(0x1C1B19).opacity(0.80), style: StrokeStyle(lineWidth: s * 0.009, lineCap: .butt))
                // ponteira de metal no começo da fita
                Tracado { _ in ponteira(curva, largura: largura, s: s) }
                    .fill(Color(0xD9D6CF))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    func marcas(_ c: CurvaS, largura: CGFloat, s: CGFloat) -> Path {
        var p = Path()
        let passo = s * 0.034
        var acumulado: CGFloat = 0, proxima: CGFloat = passo * 2, n = 0
        for i in 1..<(c.pontos.count - 1) {
            let a = c.pontos[i - 1], b = c.pontos[i + 1]
            acumulado += hypot(c.pontos[i].x - a.x, c.pontos[i].y - a.y)
            guard acumulado >= proxima else { continue }
            proxima += passo; n += 1
            let t = CGVector(dx: b.x - a.x, dy: b.y - a.y)
            let len = hypot(t.dx, t.dy)
            let nx = -t.dy / len, ny = t.dx / len
            let borda = CGPoint(x: c.pontos[i].x + nx * largura / 2, y: c.pontos[i].y + ny * largura / 2)
            let comp = largura * (n % 4 == 0 ? 0.50 : 0.24)
            p.move(to: borda)
            p.addLine(to: CGPoint(x: borda.x - nx * comp, y: borda.y - ny * comp))
        }
        return p
    }

    func ponteira(_ c: CurvaS, largura: CGFloat, s: CGFloat) -> Path {
        let a = c.pontos[0], b = c.pontos[4]
        let t = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let len = hypot(t.dx, t.dy); let ux = t.dx / len, uy = t.dy / len
        let nx = -uy, ny = ux
        let h = largura / 2 + s * 0.012, e = s * 0.030
        var p = Path()
        p.move(to: CGPoint(x: a.x + nx * h, y: a.y + ny * h))
        p.addLine(to: CGPoint(x: a.x - nx * h, y: a.y - ny * h))
        p.addLine(to: CGPoint(x: a.x - nx * h + ux * e, y: a.y - ny * h + uy * e))
        p.addLine(to: CGPoint(x: a.x + nx * h + ux * e, y: a.y + ny * h + uy * e))
        p.closeSubpath()
        return p
    }
}

/// Costura: um pesponto em S sobre o papel, pontos alongados como linha de verdade.
struct IconeCostura: View {
    let tema: Tema
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            let quadro = CGRect(x: 0, y: 0, width: s, height: s)
            let curva = CurvaS(em: quadro, raio: s * 0.165)
            let w = s * 0.046
            ZStack {
                PapelPontilhado(tema: tema, passo: s * 0.055, tinta: 0.10)
                // marca de giz da modelista: a linha que a costura segue
                curva.caminho.stroke(tema.caneta.opacity(0.30), style: StrokeStyle(lineWidth: s * 0.008))
                    .offset(x: s * 0.018, y: s * 0.012)
                curva.caminho.stroke(tema.bordoDoIcone, style: StrokeStyle(lineWidth: w, lineCap: .round,
                                                                   dash: [s * 0.040, s * 0.040 + w]))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Molduras de apresentação

struct NaMascara<C: View>: View {
    let lado: CGFloat
    @ViewBuilder let conteudo: C
    var body: some View {
        conteudo.frame(width: lado, height: lado)
            .clipShape(RoundedRectangle(cornerRadius: lado * 0.2237, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: lado * 0.2237, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: lado * 0.03, y: lado * 0.015)
    }
}

struct Direcao: View {
    let nome: String
    let ideia: String
    let claro: AnyView
    let escuro: AnyView
    let pequenos: [AnyView]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(nome).font(.system(size: 44, weight: .bold, design: .serif))
            Text(ideia).font(.system(size: 22)).foregroundStyle(Tema.claro.grafite)
                .frame(width: 700, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 28) {
                NaMascara(lado: 330) { claro }
                NaMascara(lado: 330) { escuro }
            }
            HStack(alignment: .bottom, spacing: 26) {
                ForEach(0..<pequenos.count, id: \.self) { i in pequenos[i] }
                Text("tamanhos reais da tela inicial: 60, 40 e 29 pt")
                    .font(.system(size: 17)).foregroundStyle(Tema.claro.grafite)
            }
        }
        .frame(width: 720, alignment: .leading)
    }
}

// MARK: - Prancha

struct Prancha: View {
    let t = Tema.claro
    var body: some View {
        VStack(alignment: .leading, spacing: 56) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Seam").font(.system(size: 120, weight: .bold, design: .serif))
                Text("Três direções de ícone, uma marca só. Cada uma nasce de um sentido do nome: a letra costurada, a medida, a própria costura. Cores e tipos são os da v4, sem nada novo.")
                    .font(.system(size: 26)).foregroundStyle(t.grafite)
                    .frame(width: 1500, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 60) {
                Direcao(nome: "Remendo",
                        ideia: "O S da New York vira um patch costurado à mão. É o jeito mais grife das três: lê como etiqueta de ateliê, e em tamanho pequeno sobra só o S bordô.",
                        claro: AnyView(IconeRemendo(tema: .claro)), escuro: AnyView(IconeRemendo(tema: .escuro)),
                        pequenos: [60, 40, 29].map { l in AnyView(NaMascara(lado: CGFloat(l) * 2) { IconeRemendo(tema: .claro) }) })
                Direcao(nome: "Fita métrica",
                        ideia: "A fita de costureira desenhando o S. É o \"measured\" do subtítulo sem precisar de palavra, e é o ícone mais reconhecível de longe.",
                        claro: AnyView(IconeFita(tema: .claro)), escuro: AnyView(IconeFita(tema: .escuro)),
                        pequenos: [60, 40, 29].map { l in AnyView(NaMascara(lado: CGFloat(l) * 2) { IconeFita(tema: .claro) }) })
                Direcao(nome: "Costura",
                        ideia: "Um pesponto em S seguindo a marca de giz da modelista. É o mais abstrato e o mais parecido com a interface, que já usa costura nas folhas; é também o que menos se sustenta pequeno.",
                        claro: AnyView(IconeCostura(tema: .claro)), escuro: AnyView(IconeCostura(tema: .escuro)),
                        pequenos: [60, 40, 29].map { l in AnyView(NaMascara(lado: CGFloat(l) * 2) { IconeCostura(tema: .claro) }) })
            }
        }
        .padding(80)
        .frame(width: 2400, alignment: .leading)
        .background(PapelPontilhado(tema: t))
        .foregroundStyle(t.tinta)
    }
}

// MARK: - Prancha 2: marca, cor e tipo

struct Assinatura: View {
    let tema: Tema
    var tamanho: CGFloat = 150
    var body: some View {
        VStack(alignment: .leading, spacing: tamanho * 0.10) {
            Text("Seam").font(.system(size: tamanho, weight: .bold, design: .serif))
                .foregroundStyle(tema.tinta)
                .overlay(alignment: .bottomLeading) {
                    // a costura por baixo do nome: a mesma da folha, em bordô
                    Rectangle().frame(height: max(2, tamanho * 0.022))
                        .foregroundStyle(.clear)
                        .overlay(Line().stroke(tema.bordoDoIcone,
                            style: StrokeStyle(lineWidth: max(2, tamanho * 0.022), dash: [tamanho * 0.07, tamanho * 0.05])))
                        .offset(y: tamanho * 0.10)
                }
        }
    }
}

struct Line: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
}

struct Bloco: View {
    let tema: Tema
    let titulo: String
    let lingua: String
    let subtitulo: String
    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            NaMascara(lado: 150) { IconeRemendo(tema: tema) }
            VStack(alignment: .leading, spacing: 22) {
                Assinatura(tema: tema, tamanho: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(titulo).font(.system(size: 26, weight: .semibold)).foregroundStyle(tema.tinta)
                    Text(subtitulo).font(.system(size: 22)).foregroundStyle(tema.grafite)
                }
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
            Text(lingua).font(.system(size: 18)).foregroundStyle(tema.grafite)
        }
        .padding(44)
        .frame(width: 1060, height: 330)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(tema.papel))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.black.opacity(0.06)))
    }
}

struct Amostra: View {
    let nome: String
    let papel: String
    let claro: UInt32
    let escuro: UInt32
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Color(claro)
                Color(escuro)
            }
            .frame(width: 330, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
            Text(nome).font(.system(size: 30, weight: .bold, design: .serif))
            Text(papel).font(.system(size: 21)).foregroundStyle(Tema.claro.grafite)
            Text(String(format: "#%06X  ·  #%06X", claro, escuro)).font(.system(size: 17).monospacedDigit())
                .foregroundStyle(Tema.claro.grafite)
        }
        .frame(width: 330, alignment: .leading)
    }
}

struct Prancha2: View {
    let t = Tema.claro
    var body: some View {
        VStack(alignment: .leading, spacing: 64) {
            VStack(alignment: .leading, spacing: 14) {
                Text("A marca").font(.system(size: 64, weight: .bold, design: .serif))
                Text("O nome em New York, a fonte que já dá nome às peças no app, com a costura das folhas por baixo. O nome na loja muda por idioma; o ícone é o mesmo.")
                    .font(.system(size: 26)).foregroundStyle(t.grafite).frame(width: 1500, alignment: .leading)
            }
            HStack(spacing: 60) {
                Bloco(tema: .claro, titulo: "Seam: Fashion, Measured", lingua: "inglês", subtitulo: "Market data behind every piece")
                Bloco(tema: .escuro, titulo: "Seam: moda, medida", lingua: "português", subtitulo: "Os dados por trás de cada peça")
            }
            VStack(alignment: .leading, spacing: 30) {
                Text("Cor: cada uma com um papel, e só um").font(.system(size: 44, weight: .bold, design: .serif))
                HStack(alignment: .top, spacing: 36) {
                    Amostra(nome: "Papel", papel: "fundo de toda tela", claro: 0xF7F5EF, escuro: 0x1A1917)
                    Amostra(nome: "Folha", papel: "todo conteúdo", claro: 0xFFFFFF, escuro: 0x262523)
                    Amostra(nome: "Bordô", papel: "só o que se toca", claro: 0x8A1C2E, escuro: 0xF0899A)
                    Amostra(nome: "Caneta", papel: "só dado", claro: 0x2743D6, escuro: 0x8FA2FF)
                    Amostra(nome: "Marca-texto", papel: "uma vez por tela", claro: 0xF7E27A, escuro: 0x5E5421)
                    Amostra(nome: "Cinza da peça", papel: "só atrás de peça recortada", claro: 0xCBCBCB, escuro: 0x3A3936)
                }
            }
            VStack(alignment: .leading, spacing: 30) {
                Text("Tipo: New York nomeia, SF informa").font(.system(size: 44, weight: .bold, design: .serif))
                HStack(alignment: .top, spacing: 120) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Casacos e jaquetas").font(.system(size: 56, weight: .bold, design: .serif))
                        Text("manchete, título de folha, nome de peça").font(.system(size: 21)).foregroundStyle(t.grafite)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("12 peças parecidas · dados de 20/09").font(.system(size: 40))
                        Text("corpo, linhas, números; sempre com Dynamic Type").font(.system(size: 21)).foregroundStyle(t.grafite)
                    }
                }
            }
        }
        .padding(80)
        .frame(width: 2400, alignment: .leading)
        .background(PapelPontilhado(tema: t))
        .foregroundStyle(t.tinta)
    }
}

@MainActor func salvar<V: View>(_ v: V, _ nome: String, escala: CGFloat = 1) {
    let r = ImageRenderer(content: v); r.scale = escala
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("falhou", nome); return }
    try! png.write(to: URL(fileURLWithPath: nome)); print("ok", nome, img.size)
}

MainActor.assumeIsolated {
    salvar(Prancha(), "prancha-icones.png")
    salvar(Prancha2(), "prancha-marca.png")
    for (nome, v) in [("remendo", AnyView(IconeRemendo(tema: .claro))), ("fita", AnyView(IconeFita(tema: .claro))),
                      ("costura", AnyView(IconeCostura(tema: .claro)))] {
        salvar(v.frame(width: 1024, height: 1024), "icone-\(nome)-1024.png")
    }
}
