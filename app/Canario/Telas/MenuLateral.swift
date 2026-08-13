import SwiftUI
import UIKit

struct MenuLateral: View {
    let fechar: () -> Void
    let escolher: (String) -> Void

    private let itens = ["Favorites", "Account", "Terms", "Settings", "Privacy", "Q&A"]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.08)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: fechar)
                    .accessibilityHidden(true)

                Tokens.Cor.azulMarca
                    .frame(width: geo.size.width * 0.79)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(itens, id: \.self) { item in
                            Button(item) { escolher(item) }
                                .font(.system(size: 29, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 104)
                        }
                    }
                    // O controle de fechar pertence à raiz e ocupa a mesma
                    // posição do ellipsis. A lista começa abaixo dele.
                    .padding(.top, 100)
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.trailing, 26)
                .frame(width: geo.size.width * 0.79)
                .frame(maxHeight: .infinity)
                .shadow(color: .black.opacity(0.24), radius: 22, x: 10)
            }
        }
    }
}

/// Destinos reais do menu. Eles ficam neste arquivo para não introduzir uma
/// dependência nova no projeto Xcode de lista explícita; cada tela descreve o
/// comportamento que o binário tem hoje, sem prometer conta ou IA ainda não
/// conectadas.
struct TelaDoMenu: View {
    let nome: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch nome {
                case "Favorites": FavoritosDoMenu()
                case "Account": ContaDoMenu()
                case "Terms": TermosDoMenu()
                case "Settings": AjustesDoMenu()
                case "Privacy": PrivacidadeDoMenu()
                default: PerguntasDoMenu()
                }
            }
            .background(Tokens.Cor.ceu.opacity(0.28).ignoresSafeArea())
            .navigationTitle(nome)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

private struct FavoritosDoMenu: View {
    @State private var pecas: [PecaSalva] = []
    @State private var termos: [Termo] = []
    @State private var miniaturas: [UUID: Data] = [:]

    private var rotulos: [String: String] {
        Dictionary(uniqueKeysWithValues: termos.map { ($0.id, $0.rotulo) })
    }

    var body: some View {
        Group {
            if pecas.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "heart",
                    description: Text("Tap the heart on a Closet item to keep it here."))
            } else {
                List(pecas) { peca in
                    NavigationLink {
                        RelatorioDaPeca(
                            termos: termos.filter { peca.termoIds.contains($0.id) },
                            precoAlvo: peca.precoAlvo,
                            pecaSalva: peca)
                    } label: {
                        HStack(spacing: 14) {
                            miniatura(de: peca)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(peca.nome(comRotulos: rotulos))
                                    .font(.headline)
                                Text(peca.termoIds.compactMap { rotulos[$0] }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .swipeActions {
                        Button("Unfavorite", systemImage: "heart.slash", role: .destructive) {
                            desfavoritar(peca)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .task { await carregar() }
    }

    @ViewBuilder
    private func miniatura(de peca: PecaSalva) -> some View {
        if let dados = miniaturas[peca.id], let imagem = UIImage(data: dados) {
            Image(uiImage: imagem)
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 78)
        } else {
            Image(systemName: "tshirt")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Tokens.Cor.azulMarca)
                .frame(width: 66, height: 78)
        }
    }

    @MainActor
    private func carregar() async {
        pecas = await PecasSalvas.shared.todas().filter { $0.favorita ?? false }
        termos = (try? await CatalogoDeTermos.shared.carregar()) ?? []
        var lidas: [UUID: Data] = [:]
        for peca in pecas {
            lidas[peca.id] = await PecasSalvas.shared.miniatura(de: peca)
        }
        miniaturas = lidas
    }

    private func desfavoritar(_ peca: PecaSalva) {
        pecas.removeAll { $0.id == peca.id }
        miniaturas[peca.id] = nil
        var atualizada = peca
        atualizada.favorita = false
        Task { await PecasSalvas.shared.salvar(atualizada) }
    }
}

private struct ContaDoMenu: View {
    @State private var quantidade = 0

    var body: some View {
        ScrollView {
            PaginaInformativa {
                BlocoInformativo(
                    icone: "iphone",
                    titulo: "Stored on this iPhone",
                    texto: "Your Closet currently lives only on this device. It contains \(quantidade) saved item\(quantidade == 1 ? "" : "s").")
                BlocoInformativo(
                    icone: "person.crop.circle.badge.xmark",
                    titulo: "No account connected",
                    texto: "This build does not collect an email address, password or profile, and it does not sync your Closet to another device.")
                BlocoInformativo(
                    icone: "lock.shield",
                    titulo: "No silent sign-in",
                    texto: "When account sync is introduced, it must explain what leaves the phone and ask you to sign in. This screen will never create an account in the background.")
            }
        }
        .task { quantidade = await PecasSalvas.shared.todas().count }
    }
}

private struct TermosDoMenu: View {
    var body: some View {
        ScrollView {
            PaginaInformativa {
                Text("Product terms")
                    .font(.title2.bold())
                Text("Effective August 13, 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextoComTitulo(
                    titulo: "What Canário provides",
                    texto: "Canário organizes public fashion-market signals and the clothing attributes you confirm. Trend labels are evidence summaries, not forecasts, financial advice or guarantees of sales.")
                TextoComTitulo(
                    titulo: "Store information",
                    texto: "Prices, stock, product images and links come from the named stores and can change after collection. Purchases happen on the store website under that store's terms; Canário is not the seller.")
                TextoComTitulo(
                    titulo: "Your Closet",
                    texto: "You control the items you save. Removing an item deletes its local record and thumbnail. Reinstalling the app can remove the entire local Closet because it is not synced in this build.")
                TextoComTitulo(
                    titulo: "Fair use of the service",
                    texto: "Do not use the app to overload source websites, bypass access controls, copy third-party catalogs or misrepresent Canário's readings as facts about future demand.")
                TextoComTitulo(
                    titulo: "Corrections",
                    texto: "Source coverage and classifications can be wrong. The app exposes dates and evidence so a reading can be checked and corrected rather than treated as unquestionable.")
            }
        }
    }
}

private struct AjustesDoMenu: View {
    @State private var quantidade = 0
    @State private var confirmarExclusao = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    var body: some View {
        List {
            Section("Accessibility") {
                LabeledContent("Reduce Motion") {
                    Text(reduzirMovimento ? "On" : "Off")
                }
                Text("Canário follows the iPhone accessibility setting for motion and text size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Local storage") {
                LabeledContent("Closet items", value: String(quantidade))
                Text("Saved attributes and thumbnails stay in Application Support on this iPhone and are excluded from backup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Delete local Closet", systemImage: "trash", role: .destructive) {
                    confirmarExclusao = true
                }
                .disabled(quantidade == 0)
            }
        }
        .scrollContentBackground(.hidden)
        .task { quantidade = await PecasSalvas.shared.todas().count }
        .alert("Delete the entire Closet?", isPresented: $confirmarExclusao) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await PecasSalvas.shared.apagarTudo()
                    quantidade = 0
                }
            }
        } message: {
            Text("This removes every saved item and thumbnail from this iPhone. It cannot be undone.")
        }
    }
}

private struct PrivacidadeDoMenu: View {
    var body: some View {
        ScrollView {
            PaginaInformativa {
                Text("Privacy in this build")
                    .font(.title2.bold())
                BlocoInformativo(
                    icone: "camera",
                    titulo: "Photos you choose",
                    texto: "Camera and Photo Library access happen only after you tap the corresponding action. Analysis currently runs on the iPhone; this build does not send your clothing photo to an AI service.")
                BlocoInformativo(
                    icone: "internaldrive",
                    titulo: "A small local thumbnail",
                    texto: "When you save an item, Canário can keep a resized thumbnail without photo metadata. The original is not copied. Deleting the item deletes its thumbnail.")
                BlocoInformativo(
                    icone: "network",
                    titulo: "Store images and links",
                    texto: "Similar-product images load directly from the store's image host. The store or its CDN can therefore receive the network information normally sent when an image is requested.")
                BlocoInformativo(
                    icone: "person.crop.circle.badge.xmark",
                    titulo: "No account data yet",
                    texto: "There is no sign-in in this build, so Canário does not collect an email address, password or synced Closet. This notice must change before account sync or remote photo analysis ships.")
            }
        }
    }
}

private struct PerguntasDoMenu: View {
    private let perguntas: [(String, String)] = [
        ("What is a confirmed movement?", "A direction supported by at least two independent evidence legs, such as search interest and relevant fashion coverage. A spike in one source is shown separately instead of being promoted to a trend."),
        ("Why can two dates be different?", "Google search interest and editorial sources close their weeks on different schedules. Canário shows the date attached to each signal and does not silently pretend they are the same observation."),
        ("What does Not confirmed mean?", "There may be a current reading, but there is not enough independent coverage to claim a direction. It is missing evidence, not a negative verdict about the garment."),
        ("Are Similar Pieces recommendations?", "No. They are observed products sharing the selected attributes. Price, discount and availability describe the store at collection time; they are not purchase advice."),
        ("Does Canário follow my garment over time?", "No. Opening a saved Closet item recalculates today's market reading for its attributes. The app does not claim that your personal garment rose or fell in the market."),
        ("How fresh is Weekly Trends?", "Search interest uses the latest closed Google Trends week available under the collection cadence. Fashion coverage uses publication dates. Each section shows its own evidence date so freshness can be audited.")
    ]

    var body: some View {
        List {
            ForEach(perguntas, id: \.0) { pergunta in
                Section(pergunta.0) {
                    Text(pergunta.1)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct PaginaInformativa<Conteudo: View>: View {
    let conteudo: Conteudo

    init(@ViewBuilder conteudo: () -> Conteudo) {
        self.conteudo = conteudo()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            conteudo
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlocoInformativo: View {
    let icone: String
    let titulo: String
    let texto: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icone)
                .font(.title2)
                .foregroundStyle(Tokens.Cor.azulMarca)
                .frame(width: 34)
            TextoComTitulo(titulo: titulo, texto: texto)
        }
    }
}

private struct TextoComTitulo: View {
    let titulo: String
    let texto: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(titulo).font(.headline)
            Text(texto)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
