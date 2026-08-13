import PhotosUI
import SwiftUI
import UIKit

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

    private let colunas = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    private var rotulos: [String: String] {
        Dictionary(uniqueKeysWithValues: termos.map { ($0.id, $0.rotulo) })
    }

    private var categorias: [String: String] {
        Dictionary(uniqueKeysWithValues: termos.filter { $0.dimensao == "categoria" }
            .map { ($0.id, $0.rotulo) })
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
            }
        }
        .task { await carregar() }
    }

    private var vazio: some View {
        VStack(spacing: Tokens.Espaco.m) {
            Image(systemName: "tshirt")
                .font(.system(size: 42))
                .foregroundStyle(Tokens.Cor.azulMarca)
            Text("No clothes yet").font(Tokens.Fonte.secao)
            Text("Clothes you save from Add stay here, ready to open again and compare.")
                .font(Tokens.Fonte.corpo)
                .foregroundStyle(Tokens.Cor.azulMarca.opacity(0.78))
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
                        .foregroundStyle(Tokens.Cor.azulMarca)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: colunas, spacing: 20) {
                    ForEach(pecas) { peca in
                        CartaoDoArmario(
                            peca: peca,
                            termos: termos,
                            rotulos: rotulos,
                            categoria: peca.termoIds.compactMap { categorias[$0] }.first,
                            processandoFoto: processandoFotos.contains(peca.id),
                            aoEscolherFoto: { item in
                                await substituirFoto(de: peca, por: item)
                            },
                            aoApagar: { apagar(peca) })
                    }
                }

                Text("\(pecas.count) of \(PecasSalvas.teto) · Market readings are recalculated whenever you open an item.")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.azulMarca.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, Tokens.Espaco.s)
            }
            .padding(.horizontal, 20)
            .padding(.top, Tokens.Espaco.s)
            .padding(.bottom, 100)
        }
        .refreshable { await carregar() }
    }

    @MainActor
    private func carregar() async {
        carregando = true
        erro = nil
        pecas = await PecasSalvas.shared.todas()
        do {
            termos = try await Supabase.shared.buscar(
                "termos",
                "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca,"
                + "palavras_pt,palavras_en&order=dimensao,id")
        } catch {
            erro = "The taxonomy is unavailable right now. Your clothes and photos are still on this iPhone."
        }
        carregando = false
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
}

/// Card do Figma: a peça é protagonista, inteira e sem um recorte quadrado que
/// coma mangas ou barra. O botão de foto é explícito e funciona tanto para itens
/// antigos sem miniatura quanto para substituir uma foto ruim.
private struct CartaoDoArmario: View {
    let peca: PecaSalva
    let termos: [Termo]
    let rotulos: [String: String]
    let categoria: String?
    let processandoFoto: Bool
    let aoEscolherFoto: (PhotosPickerItem) async -> Data?
    let aoApagar: () -> Void

    @State private var miniatura: Data?
    @State private var fotoEscolhida: PhotosPickerItem?

    private var temFoto: Bool { miniatura.flatMap(UIImage.init(data:)) != nil }

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                RelatorioDaPeca(
                    termos: termos.filter { peca.termoIds.contains($0.id) },
                    precoAlvo: peca.precoAlvo,
                    pecaSalva: peca)
            } label: {
                VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                    ZStack {
                        if let miniatura, let imagem = UIImage(data: miniatura) {
                            Image(uiImage: imagem)
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                        } else {
                            Image(systemName: "tshirt")
                                .font(.system(size: 46, weight: .light))
                                .foregroundStyle(Tokens.Cor.azulMarca.opacity(0.48))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 182)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(peca.nome(comRotulos: rotulos))
                            .font(Tokens.Fonte.corpo.weight(.semibold))
                            .foregroundStyle(Tokens.Cor.noite)
                            .lineLimit(2)
                        Text(categoria ?? "Clothing")
                            .font(Tokens.Fonte.miudo)
                            .foregroundStyle(Tokens.Cor.azulMarca)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().opacity(0.32)

            PhotosPicker(selection: $fotoEscolhida, matching: .images) {
                HStack(spacing: 6) {
                    if processandoFoto {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: temFoto ? "photo.badge.arrow.down" : "photo.badge.plus")
                    }
                    Text(temFoto ? "Replace photo" : "Add photo")
                        .lineLimit(1)
                }
                .font(Tokens.Fonte.miudo.weight(.semibold))
                .foregroundStyle(Tokens.Cor.azulMarca)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .disabled(processandoFoto)
        }
        .padding(10)
        .background { Vidro(raio: 24) }
        .contextMenu {
            Button(role: .destructive, action: aoApagar) {
                Label("Delete from Closet", systemImage: "trash")
            }
        }
        .onChange(of: fotoEscolhida) { _, item in
            guard let item else { return }
            Task {
                if let nova = await aoEscolherFoto(item) { miniatura = nova }
                fotoEscolhida = nil
            }
        }
        .task(id: peca.miniaturaArquivo) {
            miniatura = await PecasSalvas.shared.miniatura(de: peca)
        }
        .accessibilityAction(named: "Delete from Closet", aoApagar)
    }
}
