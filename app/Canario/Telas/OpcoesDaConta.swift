import SwiftUI
import UIKit

/// Destinos da folha de conta, com retorno à tela de origem.
struct TelaDoMenu: View {
    /// A ENTRADA, e não o texto dela.
    ///
    /// Este `switch` era `switch nome { case "Settings": ... }`, com o rótulo
    /// exibido servindo de identificador. Com a interface em português nenhum
    /// caso casaria e todo item do menu cairia no `default`, abrindo o Q&A —
    /// sem erro e sem teste vermelho, porque os dois lados liam o mesmo
    /// literal. O enum resolve a categoria inteira do problema, e não só a
    /// ocorrência: agora falta um caso é erro de compilação.
    let entrada: EntradaDoMenu
    var aoVoltarParaMenu: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var voltar: () -> Void {
        aoVoltarParaMenu ?? { dismiss() }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch entrada {
                case .favoritos: FavoritosDoMenu(aoVoltar: voltar)
                case .conta: ContaDoMenu(aoVoltar: voltar)
                case .termos: TermosDoMenu(aoVoltar: voltar)
                case .ajustes: AjustesDoMenu(aoVoltar: voltar)
                case .privacidade: PrivacidadeDoMenu(aoVoltar: voltar)
                case .perguntas: PerguntasDoMenu(aoVoltar: voltar)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
        .papelDaEdicao()
        .tint(Edicao.bordo)
    }
}

/// Cabeçalho comum aos destinos da folha de conta.
struct CabecalhoDoMenu: View {
    let titulo: LocalizedStringKey
    let aoVoltar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: aoVoltar) {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Edicao.bordo)
                    .frame(width: 44, height: 44)
                    .background(Edicao.cartao, in: Circle())
            }
            .accessibilityLabel("Back")
            Text(titulo)
                .font(Edicao.Tipo.manchete)
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
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

    var body: some View {
        VStack(spacing: 0) {
            CabecalhoDoMenu(titulo: "Favorites", aoVoltar: aoVoltar)
                .padding(.horizontal, Edicao.margem)
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
                                        .font(Edicao.Tipo.nome)
                                    Text(peca.termoIds.compactMap { rotulos[$0] }.joined(separator: " · "))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(minHeight: 66)
                        }
                        .listRowBackground(Edicao.cartao)
                        .swipeActions {
                            Button("Unfavorite", systemImage: "heart.slash", role: .destructive) {
                                desfavoritar(peca)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .papelDaEdicao()
        .tint(Edicao.bordo)
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
        // O painel do menu é uma das duas cores da marca (#0E1116 ou #BBE5ED,
        // invertidas pelo território) e a peça ficava direto sobre ela. Mesmo
        // aqui, onde a miniatura é sobretudo "qual é esta", a moldura neutra é
        // barata e evita a única coisa que não pode acontecer no app: a mesma
        // peça parecer de duas cores em duas telas.
        SubstratoDaPeca(raio: Tokens.Raio.etiqueta, respiro: Tokens.Espaco.xs) {
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFit()
            } else {
                PecaSemFoto(simbolo: "tshirt", tamanho: 30)
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
    var body: some View {
        VStack(spacing: 0) {
            CabecalhoDoMenu(titulo: "Terms", aoVoltar: aoVoltar)
                .padding(.horizontal, Edicao.margem)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                    Text("Product terms")
                        .font(Edicao.Tipo.secao)
                        .accessibilityAddTraits(.isHeader)
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
                .padding(.horizontal, Edicao.margem)
                .padding(.bottom, 40)
            }
        }
        .papelDaEdicao()
        .tint(Edicao.bordo)
    }

}

private struct AjustesDoMenu: View {
    var aoVoltar: () -> Void
    @State private var quantidade = 0
    @State private var confirmarExclusao = false
    @State private var preferenciaVisual = PreferenciaDaAnaliseVisual.perguntar
    @State private var carregouPreferenciaVisual = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @ObservedObject private var idioma = GestorDeIdioma.shared

    private var explicacaoDaPreferencia: String {
        switch preferenciaVisual {
        case .perguntar:
            return frase("You'll be asked once, the first time you analyze a photo. Your answer is remembered and can be changed here.")
        case .nuvem:
            return frase("Recommended for more complete attribute suggestions. Only the reduced, metadata-free image you confirm is analyzed.")
        case .aparelho:
            return frase("Analysis stays on this iPhone and does not use the shared cloud-analysis limit.")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CabecalhoDoMenu(titulo: "Settings", aoVoltar: aoVoltar)
                .padding(.horizontal, Edicao.margem)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                    secaoIdioma
                    if Supabase.analiseRemotaHabilitada { secaoAnaliseVisual }
                    secaoAcessibilidade
                    secaoArmazenamentoLocal
                    botaoExcluirArmario
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, Edicao.margem)
                .padding(.bottom, 40)
            }
        }
        .papelDaEdicao()
        .tint(Edicao.bordo)
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

    private var secaoIdioma: some View {
        Folha(espaco: 0) {
            CabecalhoDaFolha(titulo: Text("Language"), simbolo: "globe")
                .padding(.bottom, 8)
            opcaoDeIdioma(titulo: Text("Match iPhone language"), opcao: .sistema)
            CosturaDaEdicao()
            // Os nomes nativos permitem achar a saída mesmo após trocar de idioma.
            opcaoDeIdioma(titulo: Text(verbatim: Idioma.ingles.nomeNativo), opcao: .ingles)
            CosturaDaEdicao()
            opcaoDeIdioma(titulo: Text(verbatim: Idioma.portugues.nomeNativo), opcao: .portugues)
            CosturaDaEdicao()
            Text("This changes the whole app: screens, messages, attribute names, dates and prices. Headlines keep the language their source published in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }

    private func opcaoDeIdioma(titulo: Text, opcao: PreferenciaDeIdioma) -> some View {
        Button {
            idioma.preferencia = opcao
        } label: {
            HStack(spacing: 4) {
                titulo.foregroundStyle(.primary)
                if opcao == .sistema {
                    Text(verbatim: " · \(idioma.preferencia == .sistema ? idioma.atual.nomeNativo : PreferenciaDeIdioma.sistema.resolvido(preferidosDoSistema: Locale.preferredLanguages).nomeNativo)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if idioma.preferencia == opcao {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Edicao.bordo)
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(idioma.preferencia == opcao ? .isSelected : [])
    }

    private var secaoAnaliseVisual: some View {
        Folha(espaco: 0) {
            CabecalhoDaFolha(titulo: Text("Visual analysis"), simbolo: "camera.aperture")
                .padding(.bottom, 8)
            opcaoAnaliseVisual(titulo: "Ask me the first time", opcao: .perguntar)
            CosturaDaEdicao()
            opcaoAnaliseVisual(titulo: "Always use the cloud", opcao: .nuvem)
            CosturaDaEdicao()
            opcaoAnaliseVisual(titulo: "Always on this iPhone", opcao: .aparelho)
            CosturaDaEdicao()
            Text(explicacaoDaPreferencia)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .disabled(!carregouPreferenciaVisual)
    }

    private func opcaoAnaliseVisual(titulo: LocalizedStringKey,
                                    opcao: PreferenciaDaAnaliseVisual) -> some View {
        Button {
            preferenciaVisual = opcao
        } label: {
            HStack {
                Text(titulo).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if preferenciaVisual == opcao {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Edicao.bordo)
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(preferenciaVisual == opcao ? .isSelected : [])
    }

    private var secaoAcessibilidade: some View {
        Folha {
            CabecalhoDaFolha(titulo: Text("Accessibility"), simbolo: "accessibility")
            HStack {
                Text("Reduce motion")
                Spacer(minLength: 8)
                Text(reduzirMovimento ? "On" : "Off")
                    .font(.body.weight(.semibold))
            }
            .frame(minHeight: 44)
            CosturaDaEdicao()
            Text("The app follows the iPhone accessibility setting for motion and text size.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var secaoArmazenamentoLocal: some View {
        Folha {
            CabecalhoDaFolha(titulo: Text("Local storage"), simbolo: "internaldrive")
            HStack {
                Text("Closet items")
                Spacer(minLength: 8)
                Text(String(quantidade)).font(Edicao.Tipo.numero)
            }
            .frame(minHeight: 44)
            CosturaDaEdicao()
            Text("Saved attributes and thumbnails stay in Application Support on this iPhone and are excluded from backup.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var botaoExcluirArmario: some View {
        Button {
            confirmarExclusao = true
        } label: {
            Label("Delete local closet", systemImage: "trash")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .disabled(quantidade == 0)
    }
}

private struct PrivacidadeDoMenu: View {
    var aoVoltar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CabecalhoDoMenu(titulo: "Privacy", aoVoltar: aoVoltar)
                .padding(.horizontal, Edicao.margem)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                    Text("Privacy in this build")
                        .font(Edicao.Tipo.secao)
                        .accessibilityAddTraits(.isHeader)
                        BlocoInformativo(
                            icone: "text.bubble",
                            titulo: "Readings you request",
                            texto: "When you request a reading, the words you entered, any follow-up answer, confirmed photo attributes and optional price go to our Supabase service. The service uses OpenAI to interpret the request and write evidence-backed sentences. It does not send your original photo. A hash of the request and its interpretation can be kept for seven days to make repeated readings consistent; your saved readings stay on this iPhone.")
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
                            texto: "If you sign in, Supabase processes your account identifier, email when provided, and the Closet details needed for sync. Seam does not store your password itself. You can use the app without an account and delete a connected account from Account settings.")
                        BlocoInformativo(
                            icone: "arrow.triangle.2.circlepath.icloud",
                            titulo: "What syncs",
                            texto: "Item names, confirmed attribute ids, optional target price and channel, favorites, explicit similar-item choices and reduced metadata-free thumbnails can sync. Original photos and calculated market readings do not. A separately authorized cloud photo analysis is not attached to the account.")
                }
                .padding(.horizontal, Edicao.margem)
                .padding(.bottom, 40)
            }
        }
        .papelDaEdicao()
        .tint(Edicao.bordo)
    }
}

private struct PerguntasDoMenu: View {
    var aoVoltar: () -> Void
    /// A pergunta tem CHAVE estável e TEXTO traduzível, e as duas são coisas
    /// diferentes.
    ///
    /// Era uma tupla `(String, String)` desenhada por `Text(pergunta.0)` — e
    /// `Text` de uma `String` não localiza nada, então as seis perguntas e as
    /// seis respostas, o maior bloco de texto do app, ficavam em inglês numa
    /// interface em português sem nada acusar.
    ///
    /// Ao traduzir, o `ForEach(perguntas, id: \.0)` quebrou: o id era o
    /// PRÓPRIO texto. É a terceira vez que este projeto encontra a mesma
    /// doença — o rótulo servindo de identidade — depois do menu lateral e do
    /// `Modo` da tela de conta. Aqui ela nasce resolvida.
    private struct Pergunta: Identifiable {
        let id: String
        let pergunta: LocalizedStringKey
        let resposta: LocalizedStringKey
    }

    private let perguntas: [Pergunta] = [
        Pergunta(id: "movimento_confirmado",
                 pergunta: "What is a confirmed movement?",
                 resposta: "Two consecutive weeks outside the usual range, with at least two independent evidence legs agreeing, such as search interest and relevant fashion coverage. One week alone is not a movement, however large the reading looks, and a spike in a single source is shown separately instead of being promoted to a trend."),
        Pergunta(id: "reposicao_conta",
                 pergunta: "When does a restock count?",
                 resposta: "Only after a second visit confirms it: a size has to disappear, come back and stay available. A size that reappears for a single day may be a catalog correction rather than a buying decision, so the newest confirmed restock is usually from the day before."),
        Pergunta(id: "datas_diferentes",
                 pergunta: "Why can two dates be different?",
                 resposta: "Google search interest and editorial sources close their weeks on different schedules. The app shows the date attached to each signal and does not silently pretend they are the same observation."),
        Pergunta(id: "similares_recomendacao",
                 pergunta: "Are Similar Pieces recommendations?",
                 resposta: "No. They are observed products sharing the selected attributes. Price, discount and availability describe the store at collection time; they are not purchase advice."),
        Pergunta(id: "acompanha_peca",
                 pergunta: "Does the app follow my garment over time?",
                 resposta: "No. Opening a saved Closet item recalculates today's market reading for its attributes. The app does not claim that your personal garment rose or fell in the market."),
        Pergunta(id: "frescor_trends",
                 pergunta: "How fresh is Weekly Trends?",
                 resposta: "Search interest uses the latest closed Google Trends week available under the collection cadence. Fashion coverage uses publication dates. Each section shows its own evidence date so freshness can be audited."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            CabecalhoDoMenu(titulo: "Q&A", aoVoltar: aoVoltar)
                .padding(.horizontal, Edicao.margem)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                    ForEach(perguntas) { pergunta in
                        Folha {
                            CabecalhoDaFolha(titulo: Text(pergunta.pergunta))
                            Text(pergunta.resposta)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, Edicao.margem)
                .padding(.bottom, 40)
            }
        }
        .papelDaEdicao()
        .tint(Edicao.bordo)
    }

}

struct BlocoInformativo: View {
    let icone: String
    /// `LocalizedStringKey`, e não `String`, pelo motivo já medido em
    /// `BotaoDeEntrada`: com `String` o Xcode não enxerga o literal do lado de
    /// quem chama, e o texto continua funcionando — só que sem tradução, sem
    /// erro e sem entrar no catálogo. Termos, Privacidade e Q&A são o maior
    /// bloco de texto do app; passar despercebido aqui seria a maior metade da
    /// interface ficando em inglês dentro do português.
    let titulo: LocalizedStringKey
    let texto: LocalizedStringKey

    var body: some View {
        Folha {
            CabecalhoDaFolha(titulo: Text(titulo), simbolo: icone)
            Text(texto)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TextoComTitulo: View {
    let titulo: LocalizedStringKey
    let texto: LocalizedStringKey

    var body: some View {
        Folha {
            CabecalhoDaFolha(titulo: Text(titulo))
            Text(texto)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
