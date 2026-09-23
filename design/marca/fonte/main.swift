import SwiftUI
import AppKit

// Ícone final do Seam: a fita métrica desenhando o S.
// Três aparências, como o iOS pede: clara, escura e tingida.

enum Aparencia { case clara, escura, tingida }

struct Deslocada {
    /// A mesma curva deslocada `d` para o lado da normal: bordas impressas da fita.
    static func caminho(_ c: CurvaS, _ d: CGFloat) -> Path {
        var p = Path()
        for i in 0..<c.pontos.count {
            let a = c.pontos[max(0, i - 1)], b = c.pontos[min(c.pontos.count - 1, i + 1)]
            let t = CGVector(dx: b.x - a.x, dy: b.y - a.y); let len = max(0.0001, hypot(t.dx, t.dy))
            let q = CGPoint(x: c.pontos[i].x - t.dy / len * d, y: c.pontos[i].y + t.dx / len * d)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }
}

struct Marca {
    let ponto: CGPoint
    let normal: CGVector
    let angulo: Angle
    let indice: Int
}

func marcasDaFita(_ c: CurvaS, passo: CGFloat, inicio: CGFloat) -> [Marca] {
    var out: [Marca] = []
    var acumulado: CGFloat = 0, proxima = inicio, n = 0
    for i in 1..<(c.pontos.count - 1) {
        let a = c.pontos[i - 1], b = c.pontos[i + 1]
        acumulado += hypot(c.pontos[i].x - a.x, c.pontos[i].y - a.y)
        guard acumulado >= proxima else { continue }
        proxima += passo; n += 1
        let t = CGVector(dx: b.x - a.x, dy: b.y - a.y); let len = hypot(t.dx, t.dy)
        out.append(Marca(ponto: c.pontos[i], normal: CGVector(dx: -t.dy / len, dy: t.dx / len),
                         angulo: .radians(atan2(t.dy, t.dx)), indice: n))
    }
    return out
}

struct IconeSeam: View {
    let aparencia: Aparencia
    var fundoTransparente = false

    var fita: Color {
        switch aparencia { case .clara: Color(0xF7E27A); case .escura: Color(0xE8CF5E); case .tingida: Color(0xEDEDED) }
    }
    var tintaDaFita: Color { aparencia == .tingida ? Color(0x3A3A3A) : Color(0x1C1B19) }
    var fundo: some View {
        Group {
            switch aparencia {
            case .clara: LinearGradient(colors: [Color(0x9C2438), Color(0x7C1626)], startPoint: .top, endPoint: .bottom)
            case .escura: LinearGradient(colors: [Color(0x34101A), Color(0x1B080D)], startPoint: .top, endPoint: .bottom)
            case .tingida: Color.black
            }
        }
    }

    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            let curva = CurvaS(em: CGRect(x: 0, y: 0, width: s, height: s), raio: s * 0.165)
            let w = s * 0.120
            let marcas = marcasDaFita(curva, passo: s * 0.0285, inicio: s * 0.07)
            ZStack {
                if !fundoTransparente { fundo }
                // sombra curta: a fita pousa sobre o fundo
                if aparencia != .tingida {
                    curva.caminho.stroke(Color.black.opacity(0.28), style: StrokeStyle(lineWidth: w, lineCap: .butt))
                        .offset(y: s * 0.012).blur(radius: s * 0.012)
                }
                curva.caminho.stroke(fita, style: StrokeStyle(lineWidth: w, lineCap: .butt))
                // bordas impressas
                ForEach([w / 2 - s * 0.010, -(w / 2 - s * 0.010)], id: \.self) { d in
                    Deslocada.caminho(curva, d).stroke(tintaDaFita.opacity(0.22), lineWidth: s * 0.0035)
                }
                // marcas: curtas a cada passo, longas a cada cinco
                Tracado { _ in
                    var p = Path()
                    for m in marcas {
                        let borda = CGPoint(x: m.ponto.x + m.normal.dx * (w / 2 - s * 0.010),
                                            y: m.ponto.y + m.normal.dy * (w / 2 - s * 0.010))
                        let comp = w * (m.indice % 5 == 0 ? 0.40 : 0.20)
                        p.move(to: borda)
                        p.addLine(to: CGPoint(x: borda.x - m.normal.dx * comp, y: borda.y - m.normal.dy * comp))
                    }
                    return p
                }
                .stroke(tintaDaFita.opacity(0.85), style: StrokeStyle(lineWidth: s * 0.0075, lineCap: .butt))
                // números a cada dez: somem nos tamanhos pequenos, dão acabamento no grande
                ForEach(marcas.filter { $0.indice % 10 == 0 }, id: \.indice) { m in
                    Text("\(m.indice)")
                        .font(.system(size: s * 0.034, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tintaDaFita.opacity(0.78))
                        .rotationEffect(m.angulo + .degrees(90))
                        .position(x: m.ponto.x - m.normal.dx * w * 0.05, y: m.ponto.y - m.normal.dy * w * 0.05)
                }
                // ponteira de metal com dois rebites
                Ponteira(curva: curva, largura: w, s: s, tingida: aparencia == .tingida)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct Ponteira: View {
    let curva: CurvaS
    let largura: CGFloat
    let s: CGFloat
    let tingida: Bool
    var body: some View {
        let a = curva.pontos[0], b = curva.pontos[6]
        let t = CGVector(dx: a.x - b.x, dy: a.y - b.y); let len = hypot(t.dx, t.dy)
        let u = CGVector(dx: t.dx / len, dy: t.dy / len), n = CGVector(dx: -u.dy, dy: u.dx)
        let h = largura / 2 + s * 0.016, e = s * 0.034
        let metal = LinearGradient(colors: tingida ? [Color(0xD0D0D0), Color(0x8A8A8A)] : [Color(0xECE9E2), Color(0xA6A198)],
                                   startPoint: .top, endPoint: .bottom)
        return ZStack {
            Tracado { _ in
                var p = Path()
                p.move(to: CGPoint(x: a.x + n.dx * h, y: a.y + n.dy * h))
                p.addLine(to: CGPoint(x: a.x - n.dx * h, y: a.y - n.dy * h))
                p.addLine(to: CGPoint(x: a.x - n.dx * h + u.dx * e, y: a.y - n.dy * h + u.dy * e))
                p.addLine(to: CGPoint(x: a.x + n.dx * h + u.dx * e, y: a.y + n.dy * h + u.dy * e))
                p.closeSubpath()
                return p
            }
            .fill(metal)
            ForEach([-0.22, 0.22], id: \.self) { f in
                Circle().fill(metal).frame(width: s * 0.020, height: s * 0.020)
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: s * 0.002))
                    .position(x: a.x - u.dx * s * 0.030 + n.dx * largura * f, y: a.y - u.dy * s * 0.030 + n.dy * largura * f)
            }
        }
    }
}

// MARK: - Contexto: tela inicial e ficha da App Store

struct IconeGenerico: View {
    let simbolo: String
    let cor: Color
    let nome: String
    let lado: CGFloat
    let rotulo: Color
    var body: some View {
        VStack(spacing: lado * 0.10) {
            RoundedRectangle(cornerRadius: lado * 0.2237, style: .continuous).fill(cor)
                .frame(width: lado, height: lado)
                .overlay(Image(systemName: simbolo).font(.system(size: lado * 0.45, weight: .medium)).foregroundStyle(.white))
            Text(nome).font(.system(size: lado * 0.19)).foregroundStyle(rotulo)
        }
    }
}

struct TelaInicial: View {
    let aparencia: Aparencia
    var body: some View {
        let lado: CGFloat = 132
        let escuro = aparencia != .clara
        let rotulo: Color = .white
        let neutros: [(String, Color, String)] = escuro
            ? [("camera.fill", Color(0x2C2C2E), "Câmera"), ("photo.on.rectangle", Color(0x2C2C2E), "Fotos"),
               ("calendar", Color(0x2C2C2E), "Calendário"), ("map.fill", Color(0x2C2C2E), "Mapas"),
               ("envelope.fill", Color(0x2C2C2E), "Mail"), ("gearshape.fill", Color(0x2C2C2E), "Ajustes"),
               ("cloud.sun.fill", Color(0x2C2C2E), "Tempo")]
            : [("camera.fill", Color(0x8E8E93), "Câmera"), ("photo.on.rectangle", Color(0xFF9F0A), "Fotos"),
               ("calendar", Color(0xFF3B30), "Calendário"), ("map.fill", Color(0x34C759), "Mapas"),
               ("envelope.fill", Color(0x0A84FF), "Mail"), ("gearshape.fill", Color(0x8E8E93), "Ajustes"),
               ("cloud.sun.fill", Color(0x5AC8FA), "Tempo")]
        return VStack(spacing: 44) {
            ForEach(0..<2) { linha in
                HStack(spacing: 56) {
                    ForEach(0..<4) { col in
                        let i = linha * 4 + col
                        if i == 5 {
                            VStack(spacing: lado * 0.10) {
                                NaMascara(lado: lado) {
                                    if aparencia == .tingida {
                                        IconeSeam(aparencia: .tingida).colorMultiply(Color(0xF2B75B))
                                    } else { IconeSeam(aparencia: aparencia) }
                                }
                                Text("Seam").font(.system(size: lado * 0.19)).foregroundStyle(rotulo)
                            }
                        } else {
                            let k = i > 5 ? i - 1 : i
                            let (sim, cor, nome) = neutros[k]
                            if aparencia == .tingida {
                                IconeGenerico(simbolo: sim, cor: Color(0x1F1A12), nome: nome, lado: lado, rotulo: rotulo)
                                    .colorMultiply(Color(0xF2B75B))
                            } else {
                                IconeGenerico(simbolo: sim, cor: cor, nome: nome, lado: lado, rotulo: rotulo)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 60).padding(.horizontal, 50)
        .background(
            LinearGradient(colors: escuro ? [Color(0x1B2233), Color(0x0B0D14)] : [Color(0x9DB7D9), Color(0xE9C9B3)],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
    }
}

struct FichaDaLoja: View {
    let nome: String
    let subtitulo: String
    let obter: String
    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            NaMascara(lado: 200) { IconeSeam(aparencia: .clara) }
            VStack(alignment: .leading, spacing: 8) {
                Text(nome).font(.system(size: 40, weight: .bold)).foregroundStyle(Color(0x1C1B19))
                Text(subtitulo).font(.system(size: 30)).foregroundStyle(Color(0x6A6760))
                Spacer(minLength: 16)
                Text(obter).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 38).padding(.vertical, 12)
                    .background(Capsule().fill(Color(0x0A84FF)))
            }
            .frame(height: 200, alignment: .topLeading)
        }
        .padding(40)
        .frame(width: 1040, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color.black.opacity(0.06)))
    }
}

struct PranchaFinal: View {
    let t = Tema.claro
    func legenda(_ titulo: String, _ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo).font(.system(size: 34, weight: .bold, design: .serif))
            Text(texto).font(.system(size: 21)).foregroundStyle(t.grafite)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 64) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Seam, fita métrica").font(.system(size: 96, weight: .bold, design: .serif))
                Text("A fita da costureira desenha o S: medir é o que o app faz com a moda. Três aparências, como o iOS pede, e o ícone no lugar onde ele vai viver.")
                    .font(.system(size: 26)).foregroundStyle(t.grafite).frame(width: 1600, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 70) {
                VStack(alignment: .leading, spacing: 24) {
                    NaMascara(lado: 460) { IconeSeam(aparencia: .clara) }
                    legenda("Clara", "Bordô da marca e a fita em marca-texto.")
                }
                VStack(alignment: .leading, spacing: 24) {
                    NaMascara(lado: 460) { IconeSeam(aparencia: .escura) }
                    legenda("Escura", "Fundo quase preto com o bordô por baixo; a fita baixa o brilho.")
                }
                VStack(alignment: .leading, spacing: 24) {
                    NaMascara(lado: 460) { IconeSeam(aparencia: .tingida).colorMultiply(Color(0xF2B75B)) }
                    legenda("Tingida", "Em cinza; o iOS pinta com a cor que a pessoa escolher.")
                }
            }
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 24) {
                    TelaInicial(aparencia: .clara)
                    legenda("Na tela inicial", "Tamanho real de 60 pontos, entre apps do sistema.")
                }
                VStack(alignment: .leading, spacing: 24) {
                    TelaInicial(aparencia: .escura)
                    legenda("No modo escuro", "A fita continua sendo a primeira coisa que se vê.")
                }
            }
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 50) {
                    FichaDaLoja(nome: "Seam: moda, medida", subtitulo: "Os dados por trás de cada peça", obter: "Obter")
                    FichaDaLoja(nome: "Seam: Fashion, Measured", subtitulo: "Market data behind every piece", obter: "Get")
                }
                legenda("Na App Store", "O nome muda por idioma; o ícone é o mesmo.")
            }
        }
        .padding(80)
        .frame(width: 2400, alignment: .leading)
        .background(PapelPontilhado(tema: t))
        .foregroundStyle(t.tinta)
    }
}

MainActor.assumeIsolated {
    salvar(PranchaFinal(), "prancha-icone-final.png")
    salvar(IconeSeam(aparencia: .clara).frame(width: 1024, height: 1024), "AppIcon-clara-1024.png")
    salvar(IconeSeam(aparencia: .escura).frame(width: 1024, height: 1024), "AppIcon-escura-1024.png")
    salvar(IconeSeam(aparencia: .tingida, fundoTransparente: true).frame(width: 1024, height: 1024), "AppIcon-tingida-1024.png")
}
