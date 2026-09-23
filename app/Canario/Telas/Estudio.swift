import SwiftUI
import UIKit

/// O Estúdio: onde a pessoa traz uma peça para o Seam ler.
///
/// Substitui a tela do manequim da 1.x. O fundo é uma parede das peças do
/// Acervo, em colunas que andam devagar em sentidos alternados — a ideia do JP
/// a partir de um anúncio da Osklen (23/09/2026). Quem está começando vê a
/// parede nascer em croqui: os contornos que o app já desenha para a
/// taxonomia ocupam os lugares vazios, e cada peça adicionada toma o lugar de
/// um deles. A parede é decorativa: com Reduzir Movimento ela fica parada, e o
/// VoiceOver passa direto por ela.
struct Estudio: View {
    var abrirConta: () -> Void = {}
    @State private var termos: [Termo] = []
    @State private var buscandoTermos = false
    @State private var erro: String?
    @State private var importando = false
    @State private var pecas: [UIImage] = []

    var body: some View {
        NavigationStack {
            ZStack {
                ParedeDoAcervo(pecas: pecas)
                    .ignoresSafeArea()
                cartao
                    .padding(.horizontal, 28)
            }
            .navigationTitle(Text("Studio"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: abrirConta) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel(Text("Account"))
                }
            }
        }
        .tint(Edicao.bordo)
        .sheet(isPresented: $importando, onDismiss: carregarPecas) {
            // O fluxo de importação ainda é o da 1.x e foi desenhado para o
            // claro; ele entra na v4 no percurso da Leitura.
            ImportarPeca(termos: termos) { carregarPecas() }
                .preferredColorScheme(.light)
        }
        .task {
            carregarPecas()
            if ProcessInfo.processInfo.arguments.contains("-CanarioUITestImportacao")
                || ProcessInfo.processInfo.arguments.contains("-CanarioUITestDetalhes") {
                termos = [
                    Termo(id: "vestido", rotulo: "Dress", dimensao: "categoria", exclusiva: true,
                          sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil),
                    Termo(id: "preto", rotulo: "Black", dimensao: "cor", exclusiva: false,
                          sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil),
                ]
                importando = true
                return
            }
            // Adianta o catálogo para o toque no botão abrir sem espera.
            try? await Task.sleep(for: .seconds(1))
            termos = (try? await CatalogoDeTermos.shared.carregar()) ?? termos
        }
    }

    // MARK: O cartão

    private var cartao: some View {
        VStack(spacing: 14) {
            Text("What do you have in hand?")
                .font(Edicao.Tipo.manchete)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Photograph a piece to see what the market is doing with pieces like it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { abrirImportacao() } label: {
                Group {
                    if buscandoTermos {
                        ProgressView().tint(.white)
                    } else {
                        Label("Photograph a piece", systemImage: "camera")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Edicao.bordoCheio)
            .disabled(buscandoTermos)
            .accessibilityLabel(Text("Add a clothing item"))
            .padding(.top, 6)
            if let erro {
                Button("Try again") { abrirImportacao() }
                    .font(.footnote.weight(.semibold))
                    .accessibilityHint(Text(verbatim: erro))
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background { Vidro(raio: 28) }
    }

    private func abrirImportacao() {
        erro = nil
        if !termos.isEmpty { importando = true; return }
        Task {
            buscandoTermos = true
            defer { buscandoTermos = false }
            do {
                termos = try await CatalogoDeTermos.shared.carregar()
                importando = true
            } catch {
                erro = frase("Could not load the taxonomy.")
            }
        }
    }

    private func carregarPecas() {
        Task { @MainActor in
            var imagens: [UIImage] = []
            for peca in await PecasSalvas.shared.todas() {
                if let dados = await PecasSalvas.shared.miniatura(de: peca),
                   let imagem = await MiniaturaParaTela.imagem(de: dados) {
                    imagens.append(imagem)
                }
                if imagens.count == ParedeDoAcervo.maximo { break }
            }
            pecas = imagens
        }
    }
}

// MARK: - A parede

/// Colunas de peças que andam devagar, em sentidos alternados.
struct ParedeDoAcervo: View {
    let pecas: [UIImage]
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    static let maximo = 60
    private let colunas = 3
    private let porColuna = 5
    /// Pontos por segundo; cada coluna com a sua, para a parede não andar em bloco.
    private let velocidades: [Double] = [9, 12, 10]

    /// Peça da pessoa ou lugar vazio em croqui.
    private enum Quadro { case peca(UIImage), croqui(IconeDaTaxonomia.Glifo) }

    private static let croquis: [IconeDaTaxonomia.Glifo] = [.vestido, .camisa, .saia, .calca, .macacao, .short]

    private func quadros(coluna: Int) -> [Quadro] {
        // As peças se distribuem pelas colunas na ordem em que foram salvas;
        // o que faltar para encher a coluna vira croqui.
        let minhas = stride(from: coluna, to: pecas.count, by: colunas).map { Quadro.peca(pecas[$0]) }
        let faltam = max(0, porColuna - minhas.count)
        let vazios = (0..<faltam).map { i in Quadro.croqui(Self.croquis[(coluna * 2 + i) % Self.croquis.count]) }
        return minhas + vazios
    }

    var body: some View {
        GeometryReader { g in
            let espaco: CGFloat = 12
            let largura = (g.size.width - espaco * CGFloat(colunas + 1)) / CGFloat(colunas)
            let altura = largura * 1.35
            TimelineView(.animation(paused: reduzirMovimento)) { tempo in
                let t = tempo.date.timeIntervalSinceReferenceDate
                HStack(alignment: .top, spacing: espaco) {
                    ForEach(0..<colunas, id: \.self) { c in
                        let itens = quadros(coluna: c)
                        let ciclo = (altura + espaco) * CGFloat(itens.count)
                        let andou = reduzirMovimento ? 0 : CGFloat(t * velocidades[c % velocidades.count])
                            .truncatingRemainder(dividingBy: ciclo)
                        // Colunas pares sobem, ímpares descem.
                        let deslocamento = c % 2 == 0 ? -andou : andou - ciclo
                        VStack(spacing: espaco) {
                            // Duas voltas da mesma coluna: quando uma sai, a outra já entrou.
                            ForEach(0..<(itens.count * 2), id: \.self) { i in
                                quadro(itens[i % itens.count], largura: largura, altura: altura)
                            }
                        }
                        .offset(y: deslocamento)
                        .frame(width: largura, height: g.size.height, alignment: .top)
                        .clipped()
                    }
                }
                .padding(.horizontal, espaco)
            }
        }
        .background(Edicao.parede)
        // O título e a barra ficam sobre papel: a parede nasce do caderno.
        .overlay(alignment: .top) {
            LinearGradient(colors: [Edicao.papel, Edicao.papel.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Edicao.papel.opacity(0), Edicao.papel], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func quadro(_ q: Quadro, largura: CGFloat, altura: CGFloat) -> some View {
        switch q {
        case .peca(let imagem):
            ImagemDaPeca(imagem: imagem, respiro: 8)
                .frame(width: largura, height: altura)
        case .croqui(let glifo):
            RoundedRectangle(cornerRadius: Edicao.raioDaPeca, style: .continuous)
                .strokeBorder(Edicao.caneta.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .overlay {
                    GlifoDeVestuario(glifo: glifo)
                        .stroke(Edicao.grafite.opacity(0.45),
                                style: StrokeStyle(lineWidth: largura * 0.6 * GlifoDeVestuario.pesoDoTraco * 0.5,
                                                   lineCap: .round, lineJoin: .round))
                        .padding(largura * 0.2)
                }
                .frame(width: largura, height: altura)
        }
    }
}
