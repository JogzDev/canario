import PhotosUI
import SwiftUI
import UIKit
import ImageIO

/// O Armário local (A10, A18, A19).
///
/// Continua guardando somente o que o usuário confirmou. Índice, estado e
/// gráfico são recomputados do painel quando a peça abre; a miniatura é a única
/// cópia visual persistente e fica no aparelho, sem metadados.
struct MinhasPecas: View {
    @State private var pecas: [PecaSalva] = []
    @State private var termos: [Termo] = []
    @State private var carregando = true
    @State private var erro: String?
    @State private var processandoFotos: Set<UUID> = []
    @State private var editando: PecaSalva?
    @State private var compartilhando = false

    private let colunas = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    private var rotulos: [String: String] {
        Dictionary(uniqueKeysWithValues: termos.map { ($0.id, Traducao.rotuloExibido($0)) })
    }

    private var categorias: [String: String] {
        Dictionary(uniqueKeysWithValues: termos.filter { $0.dimensao == "categoria" }
            .map { ($0.id, Traducao.rotuloExibido($0)) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if carregando {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pecas.isEmpty {
                    vazio
                } else {
                    grade
                }
            }
            .background(Tokens.Cor.ceu.ignoresSafeArea())
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        Comparar()
                    } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        compartilhando = true
                    } label: {
                        Label("Share or export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(pecas.isEmpty)
                }
            }
        }
        .task { await carregar() }
        .onReceive(NotificationCenter.default.publisher(for: .closetMudouDeUsuario)) { _ in
            Task { await carregar() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closetFoiSincronizado)) { _ in
            Task { await carregar() }
        }
        .sheet(isPresented: $compartilhando) {
            CompartilharCloset(pecas: pecas, termos: termos)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var vazio: some View {
        VStack(spacing: Tokens.Espaco.m) {
            Image(systemName: "tshirt")
                .font(.system(size: 42))
                .foregroundStyle(Tokens.Cor.acao)
            Text("No clothes yet").font(Tokens.Fonte.secao)
            Text("Clothes you save from Add stay here, ready to open again and compare.")
                .font(Tokens.Fonte.corpo)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Tokens.Espaco.g)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grade: some View {
        ScrollView {
            VStack(spacing: Tokens.Espaco.m) {
                if let erro {
                    Text(erro)
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: colunas, spacing: 20) {
                    ForEach(pecas) { peca in
                        CartaoDoArmario(
                            peca: peca,
                            termos: termos,
                            rotulos: rotulos,
                            categoria: peca.termoIds.compactMap { categorias[$0] }.first,
                            idsDeCategoria: Set(categorias.keys),
                            processandoFoto: processandoFotos.contains(peca.id),
                            aoEscolherFoto: { item in
                                await substituirFoto(de: peca, por: item)
                            },
                            aoFavoritar: { favoritar(peca) },
                            aoRenomear: { editando = peca },
                            aoApagar: { apagar(peca) })
                    }
                }

                Text("\(pecas.count) of \(PecasSalvas.teto) · Market readings are recalculated whenever you open an item.")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, Tokens.Espaco.s)
            }
            .padding(.horizontal, 20)
            .padding(.top, Tokens.Espaco.s)
            .padding(.bottom, 100)
        }
        .refreshable { await carregar() }
        .sheet(item: $editando) { peca in
            EditorDaPeca(peca: peca) { nova in
                atualizar(nova)
                editando = nil
            }
            .presentationDetents([.medium])
        }
    }

    @MainActor
    private func carregar() async {
        carregando = true
        erro = nil
        pecas = await PecasSalvas.shared.todas()
        // A grade local não depende da rede. Os ids continuam sendo nomes
        // provisórios por alguns milissegundos até o catálogo chegar.
        carregando = false
        do {
            termos = try await CatalogoDeTermos.shared.carregar()
        } catch {
            erro = "The taxonomy is unavailable right now. Your clothes and photos are still on this iPhone."
        }
    }

    @MainActor
    private func substituirFoto(de peca: PecaSalva,
                                 por item: PhotosPickerItem) async -> Data? {
        processandoFotos.insert(peca.id)
        defer { processandoFotos.remove(peca.id) }
        do {
            guard let dados = try await item.loadTransferable(type: Data.self),
                  let imagem = MiniaturaLocal.imagem(de: dados),
                  let miniatura = await MiniaturaLocal.dados(de: imagem) else {
                erro = "I couldn't read that image. Try another photo."
                return nil
            }
            guard await PecasSalvas.shared.salvar(
                peca, miniaturaDados: miniatura) else {
                erro = "I couldn't save that photo. Your existing item was not changed."
                return nil
            }
            pecas = await PecasSalvas.shared.todas()
            erro = nil
            return miniatura
        } catch {
            erro = "I couldn't read that image. Try another photo."
            return nil
        }
    }

    private func apagar(_ peca: PecaSalva) {
        pecas.removeAll { $0.id == peca.id }
        Task { await PecasSalvas.shared.apagar(peca.id) }
    }

    private func favoritar(_ peca: PecaSalva) {
        guard let indice = pecas.firstIndex(where: { $0.id == peca.id }) else { return }
        pecas[indice].favorita = !(pecas[indice].favorita ?? false)
        let atualizada = pecas[indice]
        Task { await PecasSalvas.shared.salvar(atualizada) }
    }

    private func atualizar(_ peca: PecaSalva) {
        guard let indice = pecas.firstIndex(where: { $0.id == peca.id }) else { return }
        pecas[indice] = peca
        Task { await PecasSalvas.shared.salvar(peca) }
    }
}

private struct PacoteDeAtividade: Identifiable {
    let id = UUID()
    let itens: [Any]
}

/// Um único ponto de saída para link, redes sociais e planilha. A seleção fica
/// dentro da folha para o Closet não adquirir um segundo modo permanente.
private struct CompartilharCloset: View {
    let pecas: [PecaSalva]
    let termos: [Termo]
    @Environment(\.dismiss) private var dismiss
    @State private var selecionadas: Set<UUID>
    @State private var atividade: PacoteDeAtividade?
    @State private var preparando = false
    @State private var erro: String?

    init(pecas: [PecaSalva], termos: [Termo]) {
        self.pecas = pecas
        self.termos = termos
        _selecionadas = State(initialValue: Set(pecas.map(\.id)))
    }

    private var escolhidas: [PecaSalva] { pecas.filter { selecionadas.contains($0.id) } }
    private var rotulos: [String: String] {
        Dictionary(uniqueKeysWithValues: termos.map { ($0.id, Traducao.rotuloExibido($0)) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Choose items") {
                    ForEach(pecas) { peca in
                        Button {
                            if selecionadas.contains(peca.id) { selecionadas.remove(peca.id) }
                            else { selecionadas.insert(peca.id) }
                        } label: {
                            HStack {
                                Text(peca.nome(comRotulos: rotulos)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selecionadas.contains(peca.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Tokens.Cor.acao)
                            }
                        }
                    }
                }
                Section("Share") {
                    Button { compartilharLinks() } label: {
                        Label("Links and social networks", systemImage: "link")
                    }
                    Button { exportar(mercado: false) } label: {
                        Label("Spreadsheet · attributes only", systemImage: "tablecells")
                    }
                    Button { exportar(mercado: true) } label: {
                        Label("Spreadsheet · include market readings", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
                if preparando { ProgressView("Preparing export…") }
                if let erro { Text(erro).font(Tokens.Fonte.miudo).foregroundStyle(.secondary) }
            }
            .navigationTitle("Share or export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecionadas.count == pecas.count ? "Clear" : "All") {
                        selecionadas = selecionadas.count == pecas.count ? [] : Set(pecas.map(\.id))
                    }
                }
            }
        }
        .sheet(item: $atividade) { pacote in
            FolhaDeAtividades(itens: pacote.itens)
                .presentationDetents([.medium, .large])
        }
    }

    private func compartilharLinks() {
        guard !escolhidas.isEmpty else { erro = "Choose at least one item."; return }
        var itens: [Any] = escolhidas.compactMap { peca in
            PecaCompartilhada(nome: peca.nome(comRotulos: rotulos), termoIds: peca.termoIds).url
        }
        if escolhidas.count == 1, let peca = escolhidas.first {
            let atributos = peca.termoIds.compactMap { rotulos[$0] }
            itens.insert(CartaoCompartilhavel.imagem(
                nome: peca.nome(comRotulos: rotulos), atributos: atributos), at: 0)
        }
        atividade = PacoteDeAtividade(itens: itens)
        erro = nil
    }

    private func exportar(mercado: Bool) {
        guard !escolhidas.isEmpty else { erro = "Choose at least one item."; return }
        preparando = true
        Task {
            let url = await ExportadorDoCloset.csv(
                pecas: escolhidas, termos: termos, incluirMercado: mercado)
            preparando = false
            if let url { atividade = PacoteDeAtividade(itens: [url]); erro = nil }
            else { erro = "The spreadsheet could not be created. Try again." }
        }
    }
}

/// Card do Figma: a peça é protagonista, inteira e sem um recorte quadrado que
/// coma mangas ou barra. O card só oferece foto a itens antigos que ainda não
/// têm uma; substituição mora no detalhe da peça.
private struct CartaoDoArmario: View {
    let peca: PecaSalva
    let termos: [Termo]
    let rotulos: [String: String]
    let categoria: String?
    /// Quais ids são de categoria, para o detalhe não repetir o título.
    let idsDeCategoria: Set<String>
    let processandoFoto: Bool
    let aoEscolherFoto: (PhotosPickerItem) async -> Data?
    let aoFavoritar: () -> Void
    let aoRenomear: () -> Void
    let aoApagar: () -> Void

    @State private var miniatura: UIImage?
    @State private var fotoEscolhida: PhotosPickerItem?

    private var temFoto: Bool { miniatura != nil }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                NavigationLink {
                    RelatorioDaPeca(
                        termos: termos.filter { peca.termoIds.contains($0.id) },
                        precoAlvo: peca.precoAlvo,
                        pecaSalva: peca)
                } label: {
                    VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                        ZStack {
                            if let miniatura {
                                Image(uiImage: miniatura)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(8)
                            } else {
                                Image(systemName: "tshirt")
                                    .font(.system(size: 46, weight: .light))
                                    .foregroundStyle(.secondary.opacity(0.48))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(maxWidth: 150, maxHeight: 150)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)

                        // Título e detalhe param de dizer a mesma coisa: o
                        // título é a categoria (ou o apelido, se a pessoa deu
                        // um) e o detalhe é o que sobra. Antes o título era a
                        // lista inteira truncada e o detalhe repetia a
                        // categoria, que já era a primeira palavra dela.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peca.temApelido
                                 ? peca.nome(comRotulos: rotulos)
                                 : (categoria ?? "Clothing"))
                                .font(Tokens.Fonte.corpo.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if let detalhe = peca.detalhe(
                                comRotulos: rotulos,
                                semOsTermos: peca.temApelido ? [] : idsDeCategoria) {
                                Text(detalhe)
                                    .font(Tokens.Fonte.miudo)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 0) {
                    Button(action: aoRenomear) {
                        Image(systemName: "pencil")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Tokens.Cor.noite)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Edit clothing name")

                    Button(action: aoFavoritar) {
                        Image(systemName: (peca.favorita ?? false) ? "heart.fill" : "heart")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle((peca.favorita ?? false) ? .red : Tokens.Cor.noite)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel((peca.favorita ?? false) ? "Remove from Favorites" : "Add to Favorites")
                }
                .buttonStyle(.plain)
            }

            if !temFoto {
                Divider().opacity(0.32)
                PhotosPicker(selection: $fotoEscolhida, matching: .images) {
                    HStack(spacing: 6) {
                        if processandoFoto {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "photo.badge.plus")
                        }
                        Text("Add photo").lineLimit(1)
                    }
                    .font(Tokens.Fonte.miudo.weight(.semibold))
                    .foregroundStyle(Tokens.Cor.acao)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(processandoFoto)
            }
        }
        .padding(10)
        .frame(minHeight: 250, alignment: .top)
        .background { Vidro(raio: 24) }
        .contextMenu {
            Button(action: aoFavoritar) {
                Label((peca.favorita ?? false) ? "Unfavorite" : "Favorite",
                      systemImage: (peca.favorita ?? false) ? "heart.slash" : "heart")
            }
            Button(action: aoRenomear) {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive, action: aoApagar) {
                Label("Delete from Closet", systemImage: "trash")
            }
        }
        .onChange(of: fotoEscolhida) { _, item in
            guard let item else { return }
            Task {
                if let nova = await aoEscolherFoto(item) {
                    miniatura = await MiniaturaParaTela.imagem(de: nova)
                }
                fotoEscolhida = nil
            }
        }
        .task(id: peca.miniaturaArquivo) {
            guard let dados = await PecasSalvas.shared.miniatura(de: peca) else {
                miniatura = nil
                return
            }
            miniatura = await MiniaturaParaTela.imagem(de: dados)
        }
        .accessibilityAction(named: "Delete from Closet", aoApagar)
    }
}

private struct EditorDaPeca: View {
    @State var peca: PecaSalva
    let salvar: (PecaSalva) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Clothing name", text: $peca.apelido)
                    .textInputAutocapitalization(.sentences)
                Section {
                    Toggle("Favorite", isOn: Binding(
                        get: { peca.favorita ?? false },
                        set: { peca.favorita = $0 ? true : nil }))
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { salvar(peca) }
                }
            }
        }
    }
}

/// Miniaturas persistidas podem ter até 720 px. `UIImage(data:)` no `body`
/// adia a descompressão e cobra esse custo da main thread durante o scroll.
/// ImageIO cria e descomprime fora dela exatamente no tamanho útil dos cards.
enum MiniaturaParaTela {
    static func imagem(de dados: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let fonte = CGImageSourceCreateWithData(dados as CFData, nil),
                  let imagem = CGImageSourceCreateThumbnailAtIndex(fonte, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: 384,
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: imagem)
        }.value
    }
}
