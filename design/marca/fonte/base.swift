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


@MainActor func salvar<V: View>(_ v: V, _ nome: String, escala: CGFloat = 1) {
    let r = ImageRenderer(content: v); r.scale = escala
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("falhou", nome); return }
    try! png.write(to: URL(fileURLWithPath: nome)); print("ok", nome, img.size)
}

