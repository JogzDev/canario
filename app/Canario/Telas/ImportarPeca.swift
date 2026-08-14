import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

/// Entrada por arquivo: print, foto ou PDF (§28, com a revogação parcial do A7).
///
/// O desenho segue o v0 da §28 — **formulário primeiro**: o arquivo pré-preenche
/// os atributos e o usuário confirma ou corrige. É o humano no circuito que
/// derruba a exigência de acurácia da leitura, e por isso o app pode usar OCR e
/// medição de cor em vez de um modelo treinado.
///
/// **Três entradas, uma leitura (A12).** Arquivo, fototeca e câmera terminam no
/// mesmo `LeitorDeArquivo`: OCR do texto, cor do pixel, atributos marcados no
/// formulário. Câmera e fototeca entraram em 07/08, desfazendo o corte do A7.
///
/// A imagem original continua só em memória. A18 autoriza uma exceção explícita
/// e local: quando o usuário salva a peça no Closet, uma miniatura reamostrada,
/// sem metadados, pode ser persistida e é apagada com a peça.
struct ImportarPeca: View {
    let termos: [Termo]

    @State private var mostrandoSeletor = false
    @State private var mostrandoCamera = false
    @State private var daFototeca: PhotosPickerItem?
    @State private var lendo = false
    @State private var erro: String?
    @State private var detectados: Set<String> = []
    @State private var confirmou = false
    @State private var nomeDoArquivo: String?
    @State private var procedencia: [String] = []
    @State private var precoDigitado = ""
    @State private var miniaturaJPEG: Data?
    @State private var imagemPendente: CGImage?
    @State private var nomePendente: String?
    @State private var opcoesDeAlvo: [MiniaturaLocal.OpcaoDeAlvo] = []
    @State private var alvoEscolhido: Int?
    @FocusState private var precoEmFoco: Bool

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
                } else if imagemPendente != nil {
                    confirmacaoDoAlvo
                } else if confirmou {
                    RelatorioDaPeca(termos: termos.filter { detectados.contains($0.id) },
                                    precoAlvo: precoAlvo,
                                    miniaturaJPEG: miniaturaJPEG,
                                    pecaSalva: nil)
                } else {
                    formulario
                }
            }
            .navigationTitle("Analyze an item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
        .fullScreenCover(isPresented: $mostrandoCamera) {
            CapturaDeCamera { imagem in
                mostrandoCamera = false
                guard let imagem else { return }   // cancelou
                Task { await prepararConfirmacao(imagem, nome: "camera photo") }
            }
            .ignoresSafeArea()
        }
        .onChange(of: daFototeca) { _, item in
            guard let item else { return }
            Task { await processarDaFototeca(item) }
        }
    }

    // MARK: Formulário

    /// A câmera não sabe qual peça da cena interessa, e o segmentador do iOS
    /// sabe separar instâncias mas não sabe qual delas está à venda. Esta tela
    /// fecha as duas lacunas antes de qualquer atributo ser sugerido.
    private var confirmacaoDoAlvo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                    Text("Which item should I analyze?")
                        .font(Tokens.Fonte.titulo)
                    Text("Select the garment you meant to add. Category, color and attributes will be read only after you confirm it.")
                        .font(Tokens.Fonte.apoio)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }

                if let escolhida = opcaoEscolhida {
                    PreviaDoAlvo(dados: escolhida.dados, id: escolhida.id,
                                 altura: 320, selecionada: true)
                    Text(escolhida.tipo == .fotoCompleta
                         ? "Use the full photo when the isolated options remove part of the garment."
                         : "Background removed on this device.")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }

                if opcoesDeAlvo.count > 1 {
                    VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                        Text("Other options")
                            .font(Tokens.Fonte.secao)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Tokens.Espaco.s) {
                                ForEach(opcoesDeAlvo) { opcao in
                                    Button {
                                        alvoEscolhido = opcao.id
                                    } label: {
                                        VStack(spacing: Tokens.Espaco.xs) {
                                            PreviaDoAlvo(dados: opcao.dados, id: opcao.id,
                                                         altura: 112,
                                                         selecionada: alvoEscolhido == opcao.id)
                                            Text(opcao.rotulo)
                                                .font(Tokens.Fonte.miudo)
                                                .foregroundStyle(Tokens.Cor.tinta)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Select \(opcao.rotulo.lowercased())")
                                }
                            }
                        }
                    }
                }

                Button {
                    Task { await confirmarAlvo() }
                } label: {
                    Label("Analyze this item", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(opcaoEscolhida == nil)

                Button("Choose another photo") { cancelarConfirmacao() }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .padding(Tokens.Espaco.m)
        }
    }

    private var opcaoEscolhida: MiniaturaLocal.OpcaoDeAlvo? {
        opcoesDeAlvo.first { $0.id == alvoEscolhido }
    }

    private var formulario: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                importador
                if let erro {
                    CoberturaInsuficiente(
                        titulo: "I couldn't read this file",
                        explicacao: erro,
                        oQueTem: "You can select the attributes below and continue.")
                }
                if !procedencia.isEmpty { oQueLi }
                atributos
                precoOpcional
                if !detectados.isEmpty {
                    Button {
                        confirmou = true
                    } label: {
                        Text("Analyze \(detectados.count) attribute\(detectados.count == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { precoEmFoco = false }
            }
        }
    }

    private var importador: some View {
        Cartao {
            Text("Photo or file").font(Tokens.Fonte.secao)
            Text("Leio o arquivo no próprio aparelho. O original não é guardado; ao salvar no Closet, fica apenas uma miniatura local sem metadados.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            // A câmera vem primeiro porque é o gesto mais direto de quem está
            // com a peça na mão -- que é a situação do comprador em showroom.
            // Some no simulador e em aparelho sem câmera, em vez de abrir nada.
            if CapturaDeCamera.disponivel {
                Button {
                    erro = nil
                    mostrandoCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $daFototeca, matching: .images,
                         photoLibrary: .shared()) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                erro = nil
                mostrandoSeletor = true
            } label: {
                Label("Choose a file or PDF", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if let nomeDoArquivo {
                LinhaInsumo(texto: "Loaded: \(nomeDoArquivo)")
            }
        }
    }

    /// Regra 3: o usuário precisa saber de onde saiu cada marcação. Sem isto,
    /// uma cor sugerida pelo pixel parece um fato tão firme quanto um título
    /// lido por extenso, e as duas não têm a mesma força.
    private var oQueLi: some View {
        Cartao {
            Text("What I read from this file").font(Tokens.Fonte.secao)
            ForEach(procedencia, id: \.self) { LinhaInsumo(texto: $0) }
            LinhaInsumo(texto: "Review every suggestion. Your confirmed selection is what counts.")
        }
    }

    /// Os atributos, agrupados por dimensão. O que o arquivo sugeriu vem
    /// marcado; tudo é editável, porque a §28 exige que as tags sejam sempre
    /// corrigíveis pelo usuário.
    private var atributos: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.m) {
            HStack {
                Text("Item attributes").font(Tokens.Fonte.secao)
                Spacer()
                if !detectados.isEmpty {
                    Button("Clear") { detectados.removeAll() }
                        .font(Tokens.Fonte.miudo)
                }
            }
            ForEach(dimensoes, id: \.self) { dimensao in
                VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                    Text(rotuloDaDimensao(dimensao))
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
            Text("Your intended price").font(Tokens.Fonte.secao)
            Text("Optional. If you add it, I show its position among similar pieces in the panel — a price position, not a judgment.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            TextField("R$ 0,00", text: $precoDigitado)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($precoEmFoco)
                .submitLabel(.done)
        }
    }

    private var dimensoes: [String] {
        let categorias = Set(termos.lazy
            .filter { $0.dimensao == "categoria" && detectados.contains($0.id) }
            .map(\.id))
        let permitidas = FormularioDaPeca.dimensoesPermitidas(categorias: categorias)
        var vistas: [String] = []
        for t in termos where permitidas.contains(t.dimensao) && !vistas.contains(t.dimensao) {
            vistas.append(t.dimensao)
        }
        return vistas
    }

    private func rotuloDaDimensao(_ dimensao: String) -> String {
        [
            "categoria": "Category",
            "cor": "Color",
            "estampa": "Pattern",
            "tecido": "Material",
            "estetica": "Style",
            "comprimento": "Length",
            "silhueta": "Silhouette",
            "cintura": "Waist",
        ][dimensao] ?? dimensao.capitalized
    }

    // MARK: Leitura

    /// Fototeca: o item vira imagem em memória e segue o mesmo caminho.
    private func processarDaFototeca(_ item: PhotosPickerItem) async {
        daFototeca = nil
        lendo = true
        erro = nil
        guard let dados = try? await item.loadTransferable(type: Data.self),
              let imagem = MiniaturaLocal.imagem(de: dados) else {
            erro = "I couldn't open this photo."
            lendo = false
            return
        }
        await prepararConfirmacao(imagem, nome: "photo library image")
    }

    /// Câmera e fototeca passam pelo mesmo portão visual. A opção pré-selecionada
    /// ainda exige um toque explícito no botão de confirmação.
    private func prepararConfirmacao(_ imagem: CGImage, nome: String) async {
        lendo = true
        erro = nil
        procedencia = []
        detectados = []
        let opcoes = await MiniaturaLocal.opcoesDeAlvo(de: imagem)
        guard !opcoes.isEmpty else {
            erro = "I could not prepare this image. Choose another photo or file."
            lendo = false
            return
        }
        imagemPendente = imagem
        nomePendente = nome
        opcoesDeAlvo = opcoes
        alvoEscolhido = opcoes.first?.id
        lendo = false
    }

    private func confirmarAlvo() async {
        guard let original = imagemPendente, let escolha = opcaoEscolhida else { return }
        let imagem: CGImage?
        switch escolha.tipo {
        case .primeiroPlano:
            imagem = MiniaturaLocal.imagem(de: escolha.dados)
        case .fotoCompleta:
            imagem = original
        }
        guard let imagem else {
            erro = "I could not open the selected item. Choose another option."
            return
        }

        let nome = nomePendente ?? "selected image"
        imagemPendente = nil
        nomePendente = nil
        opcoesDeAlvo = []
        alvoEscolhido = nil
        miniaturaJPEG = escolha.dados
        await analisarImagemConfirmada(imagem, nome: nome)
    }

    private func cancelarConfirmacao() {
        imagemPendente = nil
        nomePendente = nil
        opcoesDeAlvo = []
        alvoEscolhido = nil
        daFototeca = nil
    }

    /// Só a peça confirmada termina no leitor compartilhado.
    private func analisarImagemConfirmada(_ imagem: CGImage, nome: String) async {
        lendo = true
        erro = nil
        procedencia = []
        nomeDoArquivo = nome
        let leitura = await LeitorDeArquivo.ler(imagem)
        let achado = Importacao.atributos(de: leitura, em: termos)
        let reconheceuPeca = FormularioDaPeca.temCategoria(achado.marcados, termos: termos)
        detectados = reconheceuPeca ? achado.marcados : []
        procedencia = achado.procedencia
        let marcas = Importacao.marcasNoTexto(leitura.texto)
        if !marcas.isEmpty {
            procedencia.append("Brand text recognized on device: \(marcas.joined(separator: ", ")). This is context, not proof of model or material.")
        }
        if !reconheceuPeca {
            erro = "I could not identify a garment with enough confidence. Choose its category below before adding any other attribute."
        }
        lendo = false
    }

    private func processar(_ resultado: Result<[URL], Error>) async {
        guard case .success(let urls) = resultado, let url = urls.first else { return }
        lendo = true
        erro = nil
        procedencia = []
        nomeDoArquivo = url.lastPathComponent
        miniaturaJPEG = await MiniaturaLocal.dados(doArquivo: url)
        do {
            let leitura = try await LeitorDeArquivo.ler(url)
            let achado = Importacao.atributos(de: leitura, em: termos)
            let reconheceuPeca = FormularioDaPeca.temCategoria(achado.marcados, termos: termos)
            detectados = reconheceuPeca ? achado.marcados : []
            procedencia = achado.procedencia
            let marcas = Importacao.marcasNoTexto(leitura.texto)
            if !marcas.isEmpty {
                procedencia.append("Brand text recognized on device: \(marcas.joined(separator: ", ")). This is context, not proof of model or material.")
            }
            if !reconheceuPeca {
                erro = "I could not identify a garment with enough confidence. Choose its category below before adding any other attribute."
            }
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        lendo = false
    }
}

/// Decodifica as opções fora da main thread. Uma confirmação com quatro
/// instâncias não pode reintroduzir o engasgo que A22 removeu do Closet.
private struct PreviaDoAlvo: View {
    let dados: Data
    let id: Int
    let altura: CGFloat
    let selecionada: Bool

    @State private var imagem: UIImage?

    private var compacta: Bool { altura < 160 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Raio.cartao)
                .fill(Tokens.Cor.superficie)
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFit()
                    .padding(Tokens.Espaco.s)
            } else {
                ProgressView()
            }
        }
        .frame(width: compacta ? 128 : nil)
        .frame(maxWidth: compacta ? nil : .infinity)
        .frame(height: altura)
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Raio.cartao)
                .stroke(selecionada ? Tokens.Cor.acao : Tokens.Cor.borda,
                        lineWidth: selecionada ? 3 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.cartao))
        .task(id: id) {
            imagem = nil
            imagem = await MiniaturaParaTela.imagem(de: dados)
        }
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
