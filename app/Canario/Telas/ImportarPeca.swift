import SwiftUI
import UniformTypeIdentifiers

/// Entrada por arquivo: print, foto ou PDF (§28, com a revogação parcial do A7).
///
/// O desenho segue o v0 da §28 — **formulário primeiro**: o arquivo pré-preenche
/// os atributos e o usuário confirma ou corrige. É o humano no circuito que
/// derruba a exigência de acurácia da leitura, e por isso o app pode usar OCR e
/// medição de cor em vez de um modelo treinado.
///
/// Sem câmera, sem fototeca, sem retenção: o seletor de documentos entrega o
/// arquivo, o conteúdo é lido em memória e nada é guardado.
struct ImportarPeca: View {
    let termos: [Termo]

    @State private var mostrandoSeletor = false
    @State private var lendo = false
    @State private var erro: String?
    @State private var detectados: Set<String> = []
    @State private var confirmou = false
    @State private var nomeDoArquivo: String?
    @State private var procedencia: [String] = []
    @State private var precoDigitado = ""

    /// §29.5 — contexto condicional. Opcional de propósito: sem ele o relatório
    /// funciona igual, e com ele entra o percentil de preço que a §5 autoriza
    /// como substituto da previsão proibida.
    private var precoAlvo: Double? {
        let limpo = precoDigitado
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(limpo), v > 0 else { return nil }
        return v
    }

    @Environment(\.dismiss) private var dismiss

    /// Tipos aceitos, nomeados um a um.
    ///
    /// `.image` sozinho cobre JPG em tese, mas arquivo vindo de WhatsApp e de
    /// Arquivos às vezes chega declarado como tipo genérico, e aí o seletor
    /// deixava o item cinza. Nomear os tipos concretos resolve o caso real.
    private let tiposAceitos: [UTType] = [.pdf, .jpeg, .png, .heic, .heif, .tiff, .image]

    var body: some View {
        NavigationStack {
            Group {
                if lendo {
                    Carregando()
                } else if confirmou {
                    RelatorioDaPeca(termos: termos.filter { detectados.contains($0.id) },
                                    precoAlvo: precoAlvo)
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
            allowedContentTypes: tiposAceitos,
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
                if !procedencia.isEmpty { oQueLi }
                atributos
                precoOpcional
                if !detectados.isEmpty {
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
            Text("Leio o arquivo no próprio aparelho e marco os atributos que reconhecer. Nada é enviado nem guardado.")
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

    /// Regra 3: o usuário precisa saber de onde saiu cada marcação. Sem isto,
    /// uma cor sugerida pelo pixel parece um fato tão firme quanto um título
    /// lido por extenso, e as duas não têm a mesma força.
    private var oQueLi: some View {
        Cartao {
            Text("O que eu li deste arquivo").font(Tokens.Fonte.secao)
            ForEach(procedencia, id: \.self) { LinhaInsumo(texto: $0) }
            LinhaInsumo(texto: "Confira e corrija o que estiver errado: é a sua marcação que vale.")
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

    /// §29.5 — o único campo que o usuário digita, e ele é opcional.
    private var precoOpcional: some View {
        Cartao {
            Text("Preço que você pretende praticar").font(Tokens.Fonte.secao)
            Text("Opcional. Se preencher, mostro onde ele cai entre as peças parecidas do painel — é posição de preço, não julgamento do seu preço.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            TextField("R$ 0,00", text: $precoDigitado)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
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
        procedencia = []
        nomeDoArquivo = url.lastPathComponent
        do {
            let leitura = try await LeitorDeArquivo.ler(url)
            let achado = Importacao.atributos(de: leitura, em: termos)
            detectados = achado.marcados
            procedencia = achado.procedencia
            if achado.marcados.isEmpty {
                erro = "Abri o arquivo, mas nada dele bateu com a taxonomia."
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
