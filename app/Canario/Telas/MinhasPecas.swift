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
    var menuAberto = false
    var alternarMenu: (() -> Void)?
    @State private var pecas: [PecaSalva] = []
    @State private var termos: [Termo] = []
    @State private var carregando = true
    @State private var erro: String?
    @State private var processandoFotos: Set<UUID> = []
    @State private var editando: PecaSalva?
    @State private var compartilhando = false
    @State private var filtrando = false
    @State private var somenteFavoritas = false
    @State private var atributosFiltrados: Set<String> = []
    @State private var busca = ""
    @State private var buscaApresentada = false

    private let colunas = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    /// Construído UMA vez por carregamento da taxonomia, nunca dentro do
    /// `body`. Era uma propriedade computada acessada de dentro do laço de
    /// filtragem e três vezes por card; ver `ArmarioVisivel.swift`.
    @State private var catalogo = CatalogoDoArmario(termos: [])

    private var filtro: FiltroDoArmario {
        FiltroDoArmario(somenteFavoritas: somenteFavoritas,
                        atributos: atributosFiltrados,
                        busca: busca)
    }

    private var temFiltro: Bool { filtro.ativo }

    private var pecasVisiveis: [PecaSalva] {
        filtro.aplicar(a: pecas, catalogo: catalogo)
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
            .papelDaEdicao()
            .navigationTitle(Text("Archive"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let alternarMenu {
                        BotaoDoMenu(menuAberto: menuAberto, acao: alternarMenu)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            filtrando = true
                        } label: {
                            Label("Filter Archive", systemImage: temFiltro
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                        Button {
                            compartilhando = true
                        } label: {
                            Label("Share or export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(pecas.isEmpty)
                    }
                }
            }
            .searchable(text: $busca, isPresented: $buscaApresentada,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Search names or attributes")
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
        .sheet(isPresented: $filtrando) {
            FiltroDoCloset(
                termos: termos,
                somenteFavoritas: $somenteFavoritas,
                selecionados: $atributosFiltrados)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var vazio: some View {
        ContentUnavailableView {
            Label {
                Text("Nothing in the Archive yet").font(Edicao.Tipo.secao)
            } icon: {
                Image(systemName: "hanger").foregroundStyle(Edicao.bordo)
            }
        } description: {
            Text("Pieces you bring through the Studio stay here, yours or references, ready to open again and compare.")
        }
    }

    private var grade: some View {
        // Uma avaliação por passagem do `body`. Antes `pecasVisiveis` era lido
        // três vezes aqui (isEmpty, ForEach e a contagem do rodapé), e cada
        // leitura refazia a filtragem inteira.
        let visiveis = pecasVisiveis
        return ScrollView {
            VStack(spacing: Tokens.Espaco.m) {
                if let erro {
                    Text(erro)
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if visiveis.isEmpty {
                    ContentUnavailableView(
                        "No matching clothes",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(
                            "Try removing an attribute or clearing the search."))
                        .frame(minHeight: 360)
                } else {
                    LazyVGrid(columns: colunas, spacing: 20) {
                        ForEach(visiveis) { peca in
                            CartaoDoArmario(
                                peca: peca,
                                termos: termos,
                                rotulos: catalogo.rotulos,
                                categoria: catalogo.categoria(de: peca),
                                idsDeCategoria: catalogo.idsDeCategoria,
                                processandoFoto: processandoFotos.contains(peca.id),
                                aoEscolherFoto: { item in
                                    await substituirFoto(de: peca, por: item)
                                },
                                aoFavoritar: { favoritar(peca) },
                                aoRenomear: { editando = peca },
                                aoApagar: { apagar(peca) })
                        }
                    }
                }

                Text("\(visiveis.count) shown · \(pecas.count) saved of \(PecasSalvas.teto) · Market readings are recalculated whenever you open an item.")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, Tokens.Espaco.s)
            }
            .padding(.horizontal, 20)
            .padding(.top, Tokens.Espaco.s)
            .padding(.bottom, 100)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onChanged { gesto in
                // O drawer nativo abre ao puxar a lista para baixo. Ao voltar
                // a empurrá-la para cima, fechamos a busca vazia como o Music.
                if gesto.translation.height < -12 && busca.isEmpty {
                    buscaApresentada = false
                }
            })
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
            catalogo = CatalogoDoArmario(termos: termos)
        } catch {
            erro = frase("The taxonomy is unavailable right now. Your clothes and photos are still on this iPhone.")
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
                erro = frase("I couldn't read that image. Try another photo.")
                return nil
            }
            guard await PecasSalvas.shared.salvar(
                peca, miniaturaDados: miniatura) else {
                erro = frase("I couldn't save that photo. Your existing item was not changed.")
                return nil
            }
            pecas = await PecasSalvas.shared.todas()
            erro = nil
            return miniatura
        } catch {
            erro = frase("I couldn't read that image. Try another photo.")
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

/// Filtro local e barato: nenhuma consulta ao servidor e nenhuma nova cópia do
/// armário. Dimensões se somam; opções da mesma dimensão se alternam.
private struct FiltroDoCloset: View {
    let termos: [Termo]
    @Binding var somenteFavoritas: Bool
    @Binding var selecionados: Set<String>
    @Environment(\.dismiss) private var dismiss

    private struct Opcao: Identifiable {
        let id: String
        let rotulo: String
        let dimensao: String
        let ids: Set<String>
    }

    private var dimensoes: [String] {
        Array(Set(opcoes.map(\.dimensao))).sorted {
            Traducao.rotuloDaDimensao($0) < Traducao.rotuloDaDimensao($1)
        }
    }

    private var opcoes: [Opcao] {
        // A A48 acabou com `motivo_estampa`: `conversacional` virou a família
        // inteira e não precisa mais ser agrupado com nada. O agrupamento
        // artificial "Conversational prints" some junto com o motivo dele.
        let tricos = Set(["malha", "trico_croche"]).intersection(termos.map(\.id))
        var resultado = termos.compactMap { termo -> Opcao? in
            if tricos.contains(termo.id) { return nil }
            return Opcao(id: termo.id, rotulo: Traducao.rotuloExibido(termo),
                         dimensao: termo.dimensao, ids: [termo.id])
        }
        if !tricos.isEmpty {
            resultado.append(Opcao(id: "knit_and_crochet",
                                   rotulo: frase("Knit & crochet"),
                                   dimensao: "tecido", ids: tricos))
        }
        let prioridadeDeEstampa = ["animal_print", "floral", "listra", "xadrez",
                                   "geometrica", "conversacional", "liso"]
        return resultado.sorted { esquerda, direita in
            if esquerda.dimensao == "estampa", direita.dimensao == "estampa" {
                return (prioridadeDeEstampa.firstIndex(of: esquerda.id) ?? 99)
                    < (prioridadeDeEstampa.firstIndex(of: direita.id) ?? 99)
            }
            return esquerda.rotulo.localizedCaseInsensitiveCompare(direita.rotulo)
                == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Favorites only", isOn: $somenteFavoritas)
                }
                ForEach(dimensoes, id: \.self) { dimensao in
                    Section(Traducao.rotuloDaDimensao(dimensao)) {
                        ForEach(opcoes.filter { $0.dimensao == dimensao }) { opcao in
                            Button {
                                if opcao.ids.isSubset(of: selecionados) {
                                    selecionados.subtract(opcao.ids)
                                } else {
                                    selecionados.formUnion(opcao.ids)
                                }
                            } label: {
                                HStack {
                                    Text(opcao.rotulo)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if !selecionados.isDisjoint(with: opcao.ids) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Tokens.Cor.acao)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        somenteFavoritas = false
                        selecionados = []
                    }
                    .disabled(!somenteFavoritas && selecionados.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
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
        self.catalogo = CatalogoDoArmario(termos: termos)
        _selecionadas = State(initialValue: Set(pecas.map(\.id)))
    }

    private var escolhidas: [PecaSalva] { pecas.filter { selecionadas.contains($0.id) } }
    /// Montado uma vez na inicialização da folha, não a cada linha da lista.
    private let catalogo: CatalogoDoArmario
    private var rotulos: [String: String] { catalogo.rotulos }

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
                                Text(NomeCompartilhavel.resolver(peca, catalogo: catalogo))
                                    .foregroundStyle(.primary)
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
                if preparando { ProgressView(frase("Preparing export…")) }
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
        guard !escolhidas.isEmpty else { erro = frase("Choose at least one item."); return }
        preparando = true
        Task { @MainActor in
            var itens: [Any] = escolhidas.compactMap { peca in
                PecaCompartilhada(
                    nome: NomeCompartilhavel.resolver(peca, catalogo: catalogo),
                    termoIds: peca.termoIds).url
            }
            if escolhidas.count == 1, let peca = escolhidas.first {
                let atributos = peca.termoIds.compactMap { rotulos[$0] }
                let dados = await PecasSalvas.shared.miniatura(de: peca)
                let miniatura: UIImage?
                if let dados {
                    miniatura = await MiniaturaParaTela.imagem(de: dados)
                } else {
                    miniatura = nil
                }
                itens.insert(CartaoCompartilhavel.imagem(
                    nome: NomeCompartilhavel.resolver(peca, catalogo: catalogo),
                    atributos: atributos,
                    miniatura: miniatura), at: 0)
            }
            atividade = PacoteDeAtividade(itens: itens)
            erro = nil
            preparando = false
        }
    }

    private func exportar(mercado: Bool) {
        guard !escolhidas.isEmpty else { erro = frase("Choose at least one item."); return }
        preparando = true
        Task {
            let url = await ExportadorDoCloset.csv(
                pecas: escolhidas, termos: termos, incluirMercado: mercado)
            preparando = false
            if let url { atividade = PacoteDeAtividade(itens: [url]); erro = nil }
            else { erro = frase("The spreadsheet could not be created. Try again.") }
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
    /// O seletor virou item de menu, e menu não pode conter um
    /// `PhotosPicker` que se apresenta sozinho: ele é acionado por este
    /// sinalizador, e o seletor mora fora do menu.
    @State private var escolhendoFoto = false

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
                        // O card é vidro sobre o céu da marca, e a miniatura
                        // ficava direto sobre esse azul translúcido. A grade do
                        // Closet é onde a pessoa compara peças entre si, então
                        // é onde um fundo cromático mais atrapalha: o mesmo
                        // azul entra em todas as fotos ao mesmo tempo. O vidro
                        // continua sendo o card; a foto ganha a moldura neutra
                        // por dentro dele.
                        SubstratoDaPeca(raio: Tokens.Raio.cartao,
                                        respiro: Tokens.Espaco.s) {
                            if let miniatura {
                                Image(uiImage: miniatura)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                PecaSemFoto(simbolo: "tshirt", tamanho: 46)
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
                                .font(Edicao.Tipo.nome)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if let detalhe = peca.detalhe(
                                comRotulos: rotulos,
                                semOsTermos: peca.temApelido ? [] : idsDeCategoria) {
                                Text(detalhe)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

            }

            CosturaDaEdicao().padding(.top, 6)
            HStack(spacing: 4) {
                Button(action: aoFavoritar) {
                    Image(systemName: (peca.favorita ?? false) ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle((peca.favorita ?? false) ? Edicao.bordo : .primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((peca.favorita ?? false) ? "Remove from Favorites" : "Add to Favorites")

                Spacer(minLength: 0)

                // Um botão só, pedido em 26/08. Antes eram dois — a foto
                // ocupava a largura toda com texto ("Add photo"/"Edit photo") e
                // ainda sobrava um `ellipsis` ao lado. Trocar foto é tão pouco
                // frequente quanto renomear e apagar; as três moram no mesmo
                // lugar e o card fica com coração de um lado, ações do outro.
                Menu {
                    Button {
                        escolhendoFoto = true
                    } label: {
                        Label(temFoto ? "Edit photo" : "Add photo",
                              systemImage: temFoto ? "photo.on.rectangle" : "photo.badge.plus")
                    }
                    .disabled(processandoFoto)
                    Button(action: aoRenomear) {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: aoApagar) {
                        Label("Delete from Archive", systemImage: "trash")
                    }
                } label: {
                    Group {
                        if processandoFoto {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Item actions")
            }
        }
        .padding(10)
        // Altura FIXA, não mínima: com `minHeight` cada card crescia conforme o
        // próprio texto e a grade ficava com dois vizinhos de alturas
        // diferentes. O conteúdo agora encosta no topo e o excesso é cortado
        // pelo nome/detalhe, que já são limitados a duas linhas.
        .frame(height: 268, alignment: .top)
        .clipped()
        .background {
            RoundedRectangle(cornerRadius: Edicao.raio, style: .continuous)
                .fill(Edicao.cartao)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .overlay { CosturaDaFolha() }
        .contextMenu {
            Button(action: aoFavoritar) {
                Label((peca.favorita ?? false) ? "Unfavorite" : "Favorite",
                      systemImage: (peca.favorita ?? false) ? "heart.slash" : "heart")
            }
            Button(action: aoRenomear) {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive, action: aoApagar) {
                Label("Delete from Archive", systemImage: "trash")
            }
        }
        .photosPicker(isPresented: $escolhendoFoto,
                      selection: $fotoEscolhida, matching: .images)
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
        .accessibilityAction(named: "Delete from Archive", aoApagar)
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
