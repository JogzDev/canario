import SwiftUI
import UniformTypeIdentifiers

/// Entrada por arquivo: print, foto ou PDF (§28, com a revogação parcial do A7).
///
/// O desenho segue o v0 da §28 — **formulário primeiro**: o arquivo pré-preenche
/// os atributos e o usuário confirma ou corrige. É o humano no circuito que
/// derruba a exigência de acurácia da leitura, e por isso o app pode usar OCR
/// simples em vez de um modelo treinado.
///
/// Sem câmera, sem fototeca, sem retenção: o seletor de documentos entrega o
/// arquivo, o texto é extraído em memória e nada é guardado.
struct ImportarPeca: View {
    let termos: [Termo]

    @State private var mostrandoSeletor = false
    @State private var lendo = false
    @State private var erro: String?
    @State private var detectados: Set<String> = []
    @State private var confirmou = false
    @State private var nomeDoArquivo: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if lendo {
                    Carregando()
                } else if confirmou {
                    RelatorioDaPeca(termos: termos.filter { detectados.contains($0.id) })
                } else {
                    formulario
                }
            }
            .navigationTitle("Analisar uma peça")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $mostrandoSeletor,
            // Só o que dá para ler: imagem e PDF. Nada de câmera.
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { resultado in
            Task { await processar(resultado) }
        }
    }

    // MARK: Formulário

    private var formulario: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                importador
                if let erro {
                    CoberturaInsuficiente(
                        titulo: "Não consegui ler o arquivo",
                        explicacao: erro,
                        oQueTem: "Você pode marcar os atributos à mão abaixo — o resultado é o mesmo.")
                }
                atributos
                if detectados.count >= 1 {
                    Button {
                        confirmou = true
                    } label: {
                        Text("Ver leitura de \(detectados.count) atributo\(detectados.count == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(Tokens.Espaco.m)
        }
    }

    private var importador: some View {
        Cartao {
            Text("Print, foto ou PDF").font(Tokens.Fonte.secao)
            Text("Leio o texto do arquivo no próprio aparelho e marco os atributos que reconhecer. Nada é enviado nem guardado.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            Button {
                erro = nil
                mostrandoSeletor = true
            } label: {
                Label("Escolher arquivo", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            if let nomeDoArquivo {
                LinhaInsumo(texto: "Lido: \(nomeDoArquivo)")
            }
        }
    }

    /// Os atributos, agrupados por dimensão. O que o arquivo sugeriu vem
    /// marcado; tudo é editável, porque a §28 exige que as tags sejam sempre
    /// corrigíveis pelo usuário.
    private var atributos: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.m) {
            HStack {
                Text("Atributos da peça").font(Tokens.Fonte.secao)
                Spacer()
                if !detectados.isEmpty {
                    Button("Limpar") { detectados.removeAll() }
                        .font(Tokens.Fonte.miudo)
                }
            }
            ForEach(dimensoes, id: \.self) { dimensao in
                VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                    Text(dimensao.capitalized)
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                    FluxoDeChips(
                        termos: termos.filter { $0.dimensao == dimensao },
                        marcados: $detectados)
                }
            }
        }
    }

    private var dimensoes: [String] {
        var vistas: [String] = []
        for t in termos where !vistas.contains(t.dimensao) { vistas.append(t.dimensao) }
        return vistas
    }

    // MARK: Leitura

    private func processar(_ resultado: Result<[URL], Error>) async {
        guard case .success(let urls) = resultado, let url = urls.first else { return }
        lendo = true
        erro = nil
        nomeDoArquivo = url.lastPathComponent
        do {
            let texto = try await LeitorDeArquivo.texto(de: url)
            // O MESMO tradutor que converte título de produto em atributo. O
            // print de uma página de produto tem exatamente esse texto.
            let achados = Traducao.termos(para: texto, em: termos)
            detectados = Set(achados.map(\.id))
            if detectados.isEmpty {
                erro = "Li o arquivo, mas nenhum termo da taxonomia apareceu no texto."
            }
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        lendo = false
    }
}

/// Chips de seleção, quebrando linha conforme couber.
struct FluxoDeChips: View {
    let termos: [Termo]
    @Binding var marcados: Set<String>

    var body: some View {
        FlowLayout(espaco: Tokens.Espaco.s) {
            ForEach(termos) { termo in
                let ativo = marcados.contains(termo.id)
                Button {
                    if ativo { marcados.remove(termo.id) } else { marcados.insert(termo.id) }
                } label: {
                    Text(termo.rotulo)
                        .font(Tokens.Fonte.miudo)
                        .padding(.horizontal, Tokens.Espaco.s)
                        .padding(.vertical, Tokens.Espaco.xs)
                        .background(ativo ? Tokens.Cor.tinta : Tokens.Cor.superficie)
                        .foregroundStyle(ativo ? Tokens.Cor.fundo : Tokens.Cor.tinta)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Layout que quebra linha. Existe porque `LazyVGrid` com largura fixa deixaria
/// buraco entre chips de tamanhos muito diferentes ("Liso" e "Boho e artesanal").
struct FlowLayout: Layout {
    var espaco: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largura = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alturaDaLinha: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x + t.width > largura, x > 0 {
                x = 0; y += alturaDaLinha + espaco; alturaDaLinha = 0
            }
            x += t.width + espaco
            alturaDaLinha = max(alturaDaLinha, t.height)
        }
        return CGSize(width: largura, height: y + alturaDaLinha)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alturaDaLinha: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x + t.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += alturaDaLinha + espaco; alturaDaLinha = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espaco
            alturaDaLinha = max(alturaDaLinha, t.height)
        }
    }
}
