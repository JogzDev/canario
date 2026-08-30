import SwiftUI
import UIKit

struct MenuLateral: View {
    let fechar: () -> Void
    let escolher: (String) -> Void
    /// O menu é chrome, não conteúdo: ele não tem território próprio, herda o
    /// da aba de trás e inverte as duas cores da marca em cima disso. Vem por
    /// ambiente porque `Raiz` é quem sabe a aba visível -- ver `fundoDoMenu`.
    @Environment(\.territorio) private var territorio

    /// A aresta esquerda do botão de busca, contada a partir da borda direita.
    ///
    /// Ele mora no rodapé à direita: 62 pt de diâmetro a 20 pt da borda. O
    /// painel e a sombra dele têm de parar antes disso -- com o painel a 79%
    /// da largura sobravam 2 pt de folga, e a sombra atravessava esse vão e
    /// escurecia o canto do botão. Relatado assim: *"fica cortando um
    /// pouquinho do ícone da lupa"*.
    ///
    /// 82 é o botão; os 26 restantes são o respiro que mantém a sombra inteira
    /// deste lado da divisa.
    private static let folgaAteABusca: CGFloat = 82 + 26

    var body: some View {
        GeometryReader { geo in
            let largura = min(geo.size.width * 0.79,
                              geo.size.width - Self.folgaAteABusca)
            ZStack(alignment: .leading) {
                // Sem véu: o JP quis ver a faixa limpa, mostrando a tela de
                // trás como ela é. O toque nela continua fechando o menu, e
                // para isso a área precisa existir mesmo transparente --
                // `Color.clear` sozinho não recebe toque.
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: fechar)
                    .accessibilityHidden(true)

                // A sombra pertence à BORDA do painel, e estava no VStack de
                // conteúdo -- que não tem fundo. O resultado era um borrão de
                // 22 pt atrás de cada letra, deslocado 10 pt, e nenhuma sombra
                // na divisa entre painel e faixa. Sem o véu ela é a única coisa
                // que separa o painel do que está atrás, então fica -- só mais
                // curta, para caber na folga acima.
                //
                // CONFLITO DE 30/08, resolvido para cá: a `BranchFadul` ainda
                // trazia `Tokens.Cor.azulMarca`, que é o valor de antes da
                // inversão por território. O Davi não desfez nada -- ele
                // ramificou antes dela existir.
                Tokens.Cor.fundoDoMenu(territorio)
                    .frame(width: largura)
                    .ignoresSafeArea()
                    .shadow(color: .black.opacity(0.20), radius: 10, x: 3)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(EntradaDoMenu.acoes, id: \.self) { entrada in
                            Button(entrada.titulo) { escolher(entrada.titulo) }
                                .font(.system(size: 29, weight: .semibold))
                                .foregroundStyle(Tokens.Cor.tintaDoMenu(territorio))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 92)
                        }
                    }
                    .padding(.top, 100)

                    Spacer()

                    HStack(spacing: Tokens.Espaco.m) {
                        ForEach(EntradaDoMenu.leituras, id: \.self) { entrada in
                            Button(entrada.titulo) { escolher(entrada.titulo) }
                                .font(.system(size: 15, weight: .medium))
                                // 0,72 era medida para branco sobre azul
                                // escuro. Com o par invertido ela cai a 3,5:1
                                // no painel claro, abaixo do mínimo da Apple
                                // para 15 pt; 0,85 devolve os dois lados
                                // acima de 4,5:1 sem igualar o rodapé ao topo.
                                .foregroundStyle(
                                    Tokens.Cor.tintaDoMenu(territorio).opacity(0.85))
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(.bottom, Tokens.Espaco.g)
                }
                .padding(.leading, 20)
                .padding(.trailing, 26)
                .frame(width: largura)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Destinos reais do menu com controle de navegação e retorno ao Menu Lateral.
/// Destinos reais do menu. Eles ficam neste arquivo para não introduzir uma
/// dependência nova no projeto Xcode de lista explícita; cada tela descreve o
/// comportamento que o binário tem hoje, sem prometer conta ou IA ainda não
/// conectadas.
struct TelaDoMenu: View {
    let nome: String
    var aoVoltarParaMenu: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var voltar: () -> Void {
        aoVoltarParaMenu ?? { dismiss() }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch nome {
                case "Favorites": FavoritosDoMenu(aoVoltar: voltar)
                case "Account": ContaDoMenu(aoVoltar: voltar)
                case "Terms": TermosDoMenu(aoVoltar: voltar)
                case "Settings": AjustesDoMenu(aoVoltar: voltar)
                case "Privacy": PrivacidadeDoMenu(aoVoltar: voltar)
                default: PerguntasDoMenu(aoVoltar: voltar)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Componente visual reutilizável de cabeçalho padronizado para todas as telas do Menu Lateral.
struct CabecalhoDoMenu: View {
    let titulo: String
    let aoVoltar: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Button(action: aoVoltar) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.55), in: Circle())
                }
                Spacer()
            }

            Text(titulo)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
        }
    }
}

private struct FavoritosDoMenu: View {
    var aoVoltar: () -> Void
    @State private var pecas: [PecaSalva] = []
    @State private var termos: [Termo] = []
    /// Guardado, não computado: a lista lê `rotulos` duas vezes por linha, e
    /// como propriedade computada cada leitura percorria a taxonomia inteira.
    /// Mesmo defeito que travava o Closet; ver `ArmarioVisivel.swift`.
    @State private var rotulos: [String: String] = [:]

    private let corFundo = Tokens.Cor.ceuFixo

    var body: some View {
        ZStack {
            corFundo.ignoresSafeArea()

            VStack(spacing: 0) {
                CabecalhoDoMenu(titulo: "Favorites", aoVoltar: aoVoltar)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

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
                                    MiniaturaFavorita(peca: peca)
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
            }
        }
        .task { await carregar() }
    }

    @MainActor
    private func carregar() async {
        pecas = await PecasSalvas.shared.todas().filter { $0.favorita ?? false }
        termos = (try? await CatalogoDeTermos.shared.carregar()) ?? []
        rotulos = Dictionary(uniqueKeysWithValues:
            termos.map { ($0.id, Traducao.rotuloExibido($0)) })
    }

    private func desfavoritar(_ peca: PecaSalva) {
        pecas.removeAll { $0.id == peca.id }
        var atualizada = peca
        atualizada.favorita = false
        Task { await PecasSalvas.shared.salvar(atualizada) }
    }
}

private struct MiniaturaFavorita: View {
    let peca: PecaSalva
    @State private var imagem: UIImage?

    var body: some View {
        Group {
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "tshirt")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Tokens.Cor.azulMarca)
            }
        }
        .frame(width: 66, height: 78)
        .task(id: peca.miniaturaArquivo) {
            guard let dados = await PecasSalvas.shared.miniatura(de: peca) else {
                imagem = nil
                return
            }
            imagem = await MiniaturaParaTela.imagem(de: dados)
        }
    }
}

private struct TermosDoMenu: View {
    var aoVoltar: () -> Void
    private let corFundo = Tokens.Cor.ceuFixo

    var body: some View {
        ZStack {
            corFundo.ignoresSafeArea()

            VStack(spacing: 0) {
                CabecalhoDoMenu(titulo: "Terms", aoVoltar: aoVoltar)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                ScrollView {
                    PaginaInformativa {
                        Text("Product terms")
                            .font(.title2.bold())
                        Text("Effective August 13, 2026")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextoComTitulo(
                            titulo: "What the app provides",
                            texto: "The app organizes public fashion-market signals and the clothing attributes you confirm. Trend labels are evidence summaries, not forecasts, financial advice or guarantees of sales.")
                        TextoComTitulo(
                            titulo: "Store information",
                            texto: "Prices, stock, product images and links come from the named stores and can change after collection. Purchases happen on the store website under that store's terms; this app is not the seller.")
                        TextoComTitulo(
                            titulo: "Your Closet",
                            texto: "You control the items you save. Without an account they stay on this iPhone. After you sign in, item details and private reduced thumbnails can sync across your devices; original photos remain local. Removing an item also removes its synchronized record.")
                        TextoComTitulo(
                            titulo: "Fair use of the service",
                            texto: "Do not use the app to overload source websites, bypass access controls, copy third-party catalogs or misrepresent its readings as facts about future demand.")
                        TextoComTitulo(
                            titulo: "Corrections",
                            texto: "Source coverage and classifications can be wrong. The app exposes dates and evidence so a reading can be checked and corrected rather than treated as unquestionable.")
                    }
                }
            }
        }
    }
}

private struct AjustesDoMenu: View {
    var aoVoltar: () -> Void
    @State private var quantidade = 0
    @State private var confirmarExclusao = false
    /// Três estados, não dois. O interruptor anterior só sabia dizer
    /// nuvem/aparelho e mapeava `perguntar` para "nuvem ligada" -- então,
    /// enquanto a escolha ainda não tinha sido feita, os Ajustes afirmavam uma
    /// coisa e o fluxo de Add fazia outra: perguntava. Quem visse a tela não
    /// tinha como saber por quê. O estado agora aparece como ele é.
    @State private var preferenciaVisual = PreferenciaDaAnaliseVisual.perguntar
    @State private var carregouPreferenciaVisual = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    private let corFundo = Tokens.Cor.ceuFixo
    private let corLinha = Color.white.opacity(0.65)

    private var explicacaoDaPreferencia: String {
        switch preferenciaVisual {
        case .perguntar:
            return "You'll be asked once, the first time you analyze a photo. Your answer is remembered and can be changed here."
        case .nuvem:
            return "Recommended for more complete attribute suggestions. Only the reduced, metadata-free image you confirm is analyzed."
        case .aparelho:
            return "Analysis stays on this iPhone and does not use the shared cloud-analysis limit."
        }
    }

    var body: some View {
        ZStack {
            corFundo.ignoresSafeArea()

            GeometryReader { proxy in
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "gearshape")
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width * 0.75, height: proxy.size.width * 0.75)
                            .foregroundStyle(Color.white.opacity(0.32))
                            .offset(x: proxy.size.width * 0.14, y: proxy.size.width * 0.18)
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                CabecalhoDoMenu(titulo: "Settings", aoVoltar: aoVoltar)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if Supabase.analiseRemotaHabilitada {
                            secaoAnaliseVisual
                        }

                        secaoAcessibilidade

                        secaoArmazenamentoLocal

                        botaoExcluirArmario
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
        }
        .task {
            quantidade = await PecasSalvas.shared.todas().count
            preferenciaVisual = await PreferenciasDaAnaliseVisual.shared.preferencia()
            carregouPreferenciaVisual = true
        }
        .onChange(of: preferenciaVisual) { _, nova in
            guard carregouPreferenciaVisual else { return }
            Task { await PreferenciasDaAnaliseVisual.shared.definir(nova) }
        }
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

    private var secaoAnaliseVisual: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visual analysis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 0) {
                opcaoAnaliseVisual(titulo: "Ask me the first time", opcao: .perguntar)
                divisorCard
                opcaoAnaliseVisual(titulo: "Always use the cloud", opcao: .nuvem)
                divisorCard
                opcaoAnaliseVisual(titulo: "Always on this iPhone", opcao: .aparelho)
                divisorCard

                Text(explicacaoDaPreferencia)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(cardBackground)
            .disabled(!carregouPreferenciaVisual)
        }
    }

    private func opcaoAnaliseVisual(titulo: String, opcao: PreferenciaDaAnaliseVisual) -> some View {
        Button {
            preferenciaVisual = opcao
        } label: {
            HStack {
                Text(titulo)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if preferenciaVisual == opcao {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var secaoAcessibilidade: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accessibility")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Reduce motion")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(reduzirMovimento ? "On" : "Off")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                divisorCard

                Text("The app follows the iPhone accessibility setting for motion and text size.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(cardBackground)
        }
    }

    private var secaoArmazenamentoLocal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local storage")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Closet items")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(quantidade))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                divisorCard

                Text("Saved attributes and thumbnails stay in Application Support on this iPhone and are excluded from backup.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(cardBackground)
        }
    }

    private var botaoExcluirArmario: some View {
        Button {
            confirmarExclusao = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                Text("Delete local closet")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Color.red.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.7), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(quantidade == 0)
        .opacity(quantidade == 0 ? 0.5 : 1.0)
    }

    private var divisorCard: some View {
        Rectangle()
            .fill(corLinha)
            .frame(height: 1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.85), Color.white.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct PrivacidadeDoMenu: View {
    var aoVoltar: () -> Void
    private let corFundo = Tokens.Cor.ceuFixo

    var body: some View {
        ZStack {
            corFundo.ignoresSafeArea()

            VStack(spacing: 0) {
                CabecalhoDoMenu(titulo: "Privacy", aoVoltar: aoVoltar)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                ScrollView {
                    PaginaInformativa {
                        Text("Privacy in this build")
                            .font(.title2.bold())
                        if Supabase.analiseRemotaHabilitada {
                            BlocoInformativo(
                                icone: "camera",
                                titulo: "Photos you choose",
                                texto: "Camera and Photo Library access happen only after you tap the corresponding action. After you select the target garment, the app asks for separate permission before sending a reduced, metadata-free copy through Supabase to OpenAI for attribute suggestions. The app does not store the submitted image. OpenAI may retain abuse-monitoring logs for up to 30 days.")
                        } else {
                            BlocoInformativo(
                                icone: "camera",
                                titulo: "Photos you choose",
                                texto: "Camera and Photo Library access happen only after you tap the corresponding action. Visual reading in this build stays on the iPhone; cloud analysis is disabled.")
                        }
                        BlocoInformativo(
                            icone: "internaldrive",
                            titulo: "A small local thumbnail",
                            texto: "When you save an item, the app can keep a resized thumbnail without photo metadata. The original is not copied. Signed-in accounts can synchronize that reduced thumbnail privately; deleting the item deletes its thumbnail.")
                        BlocoInformativo(
                            icone: "network",
                            titulo: "Store images and links",
                            texto: "Similar-product images load directly from the store's image host. The store or its CDN can therefore receive the network information normally sent when an image is requested.")
                        BlocoInformativo(
                            icone: "person.crop.circle.badge.checkmark",
                            titulo: "Optional account",
                            texto: "If you sign in, Supabase processes your account identifier, email when provided, and the Closet details needed for sync. DataDrobe does not store your password itself. You can use the app without an account and delete a connected account from Account settings.")
                        BlocoInformativo(
                            icone: "arrow.triangle.2.circlepath.icloud",
                            titulo: "What syncs",
                            texto: "Item names, confirmed attribute ids, optional target price and channel, favorites, explicit similar-item choices and reduced metadata-free thumbnails can sync. Original photos and calculated market readings do not. A separately authorized cloud photo analysis is not attached to the account.")
                    }
                }
            }
        }
    }
}

private struct PerguntasDoMenu: View {
    var aoVoltar: () -> Void
    private let corFundo = Tokens.Cor.ceuFixo

    private let perguntas: [(String, String)] = [
        ("What is a confirmed movement?", "Two consecutive weeks outside the usual range, with at least two independent evidence legs agreeing, such as search interest and relevant fashion coverage. One week alone is not a movement, however large the reading looks, and a spike in a single source is shown separately instead of being promoted to a trend."),
        ("When does a restock count?", "Only after a second visit confirms it: a size has to disappear, come back and stay available. A size that reappears for a single day may be a catalog correction rather than a buying decision, so the newest confirmed restock is usually from the day before."),
        ("Why can two dates be different?", "Google search interest and editorial sources close their weeks on different schedules. The app shows the date attached to each signal and does not silently pretend they are the same observation."),
        ("Are Similar Pieces recommendations?", "No. They are observed products sharing the selected attributes. Price, discount and availability describe the store at collection time; they are not purchase advice."),
        ("Does the app follow my garment over time?", "No. Opening a saved Closet item recalculates today's market reading for its attributes. The app does not claim that your personal garment rose or fell in the market."),
        ("How fresh is Weekly Trends?", "Search interest uses the latest closed Google Trends week available under the collection cadence. Fashion coverage uses publication dates. Each section shows its own evidence date so freshness can be audited.")
    ]

    var body: some View {
        ZStack {
            corFundo.ignoresSafeArea()

            VStack(spacing: 0) {
                CabecalhoDoMenu(titulo: "Q&A", aoVoltar: aoVoltar)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(perguntas, id: \.0) { pergunta in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pergunta.0)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)

                                Text(pergunta.1)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .lineSpacing(3)
                            }
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.85), Color.white.opacity(0.50)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
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

struct BlocoInformativo: View {
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
