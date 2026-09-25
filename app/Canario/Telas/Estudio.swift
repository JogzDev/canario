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
    @State private var leituras: [LeituraGuardada] = []

    var body: some View {
        NavigationStack {
            ZStack {
                ParedeDoAcervo(pecas: pecas)
                    .ignoresSafeArea()
                cartao.padding(.horizontal, 28)
            }
            .navigationTitle(Text("Studio"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: abrirConta) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel(Text("Account"))
                }
                if !leituras.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ScrollView {
                                leiturasFeitas
                                    .padding(.horizontal, Edicao.margem)
                                    .padding(.vertical, 20)
                            }
                            .papelDaEdicao()
                            .navigationTitle(Text("Readings made"))
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel(Text("Readings made"))
                    }
                }
            }
        }
        .tint(Edicao.bordo)
        .sheet(isPresented: $importando, onDismiss: {
            carregarPecas()
            carregarLeituras()
        }) {
            ImportarPeca(termos: termos) { carregarPecas() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closetFoiSincronizado)) { _ in
            carregarPecas()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closetMudouDeUsuario)) { _ in
            carregarLeituras()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leituraFoiGuardada)) { _ in
            carregarLeituras()
        }
        .onAppear { carregarLeituras() }
        .task {
            carregarPecas()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-CanarioUITestLeiturasFeitas") {
                leituraDeTeste()
                return
            }
            #endif
            if ProcessInfo.processInfo.arguments.contains("-CanarioUITestImportacao")
                || ProcessInfo.processInfo.arguments.contains("-CanarioUITestDetalhes")
                || LeituraDaPeca.testeDeInterfaceAtivo {
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

    private var leiturasFeitas: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChamadaDaEdicao(texto: frase("Readings made"))
                .accessibilityAddTraits(.isHeader)
            ForEach(leituras) { registro in
                NavigationLink {
                    LeituraDaPeca(pedido: registro.pedido, descricao: registro.descricao,
                                  precoInicial: registro.precoDaPessoa,
                                  registroInicial: registro)
                } label: {
                    Folha {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(verbatim: registro.nome)
                                .font(Edicao.Tipo.nome)
                                .foregroundStyle(.primary)
                            if let data = registro.leitura.painelObservadoEm {
                                Text(frase("Panel of \(Formato.data(data))"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let pecas = registro.resumo.pecas,
                               let marcas = registro.resumo.marcas {
                                Text(frase("Pieces: \(String(pecas)) · brands: \(String(marcas))"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let mediana = registro.resumo.precoMediano {
                                Text(frase("Median price: \(Formato.dinheiro(mediana))"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

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

    private func carregarLeituras() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CanarioUITestLeiturasFeitas") { return }
        #endif
        Task { @MainActor in leituras = await LeiturasSalvas.shared.todas() }
    }

    #if DEBUG
    private func leituraDeTeste() {
        guard let resposta = try? LeituraEspecifica.decodificar(Data("""
        {"nome":"saia midi plissada","painel_observado_em":"2026-09-24",
         "frases":[{"texto":"Há uma peça do painel neste recorte.","fatos":["total"]}],
         "fatos":{"total":{"pecas":1,"marcas":1,"provas":[17]},
                   "preco":{"minimo":299,"mediana":299,"maximo":299,"provas":[17]}},
         "pecas":[{"id":17,"titulo":"Saia midi plissada","marca":"Marca de teste",
                   "preco":299,"url":"https://example.invalid/peca"}],
         "parecidas":[],"perguntas":[]}
        """.utf8)) else { return }
        leituras = [LeituraGuardada(pedido: "saia midi plissada", descricao: nil,
                                   precoDaPessoa: 350, leitura: resposta)]
    }
    #endif
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
    private let velocidades: [Double] = [18, 22, 19]

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
            // Papel cheio até abaixo do título grande, e só então a parede
            // aparece: o título nunca fica sobre uma foto.
            LinearGradient(stops: [.init(color: Edicao.papel, location: 0),
                                   .init(color: Edicao.papel, location: 0.55),
                                   .init(color: Edicao.papel.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 330)
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
