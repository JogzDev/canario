import SwiftUI

/// A leitura específica de uma peça (2.0): "jaqueta napoleão", "saia midi
/// plissada", ou a peça de uma foto.
///
/// Cada frase é um botão: tocar abre a prova, as peças do painel que
/// sustentam aquela frase. Parecidas aparecem à parte, fora dos números. As
/// perguntas de refinamento e o preço da peça da pessoa refazem a leitura.
struct LeituraDaPeca: View {
    static var testeDeInterfaceAtivo: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-CanarioUITestLeituraDaFoto")
        #else
        false
        #endif
    }

    let pedido: String
    var descricao: DescricaoDaPeca? = nil

    @State private var leitura: LeituraEspecifica?
    @State private var erro: String?
    @State private var limiteDoDia = false
    @State private var carregando = true
    @State private var refinamento: String?
    @State private var preco: Double?
    @State private var precoDigitado = ""
    @State private var fraseAberta: LeituraEspecifica.Frase?
    @FocusState private var editandoPreco: Bool

    /// `precoInicial`: o preço que a pessoa já informou para a peça do Acervo;
    /// a posição de preço vem na primeira leitura, sem pedir de novo.
    init(pedido: String, descricao: DescricaoDaPeca? = nil, precoInicial: Double? = nil) {
        self.pedido = pedido
        self.descricao = descricao
        _preco = State(initialValue: precoInicial)
        _precoDigitado = State(initialValue: precoInicial.map { Formato.dinheiroExato($0) } ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                if carregando {
                    LendoOPainel()
                        .padding(.top, 40)
                } else if limiteDoDia {
                    ContentUnavailableView {
                        Label("Daily reading limit reached", systemImage: "hourglass")
                    } description: {
                        Text("Each reading checks the whole panel. Try again tomorrow.")
                    }
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await ler() } }
                } else if let leitura {
                    conteudo(leitura)
                }
            }
            .padding(.horizontal, Edicao.margem)
            .padding(.bottom, 40)
        }
        .papelDaEdicao()
        .navigationTitle(Text(verbatim: leitura?.nome ?? pedido))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: chaveDaLeitura) { await ler() }
        .sheet(item: $fraseAberta) { frase in
            if let leitura {
                ProvaDaFrase(frase: frase, pecas: leitura.provas(de: frase))
            }
        }
    }

    /// Refinar ou informar o preço refaz a leitura; nada mais refaz.
    private var chaveDaLeitura: String {
        "\(pedido)|\(refinamento ?? "")|\(preco.map { String($0) } ?? "")"
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func conteudo(_ leitura: LeituraEspecifica) -> some View {
        cabecalho(leitura)
        if leitura.foraDeEscopo == true {
            Folha {
                Text("This isn't a garment the panel tracks. The reading covers women's clothing from the monitored brands.")
                    .font(.body)
            }
        } else {
            Folha(espaco: 0) {
                ForEach(Array(leitura.frases.enumerated()), id: \.offset) { indice, frase in
                    if indice > 0 { CosturaDaEdicao().padding(.vertical, 12) }
                    LinhaDaFrase(frase: frase, temProva: !leitura.provas(de: frase).isEmpty) {
                        fraseAberta = frase
                    }
                }
            }
            if !leitura.perguntas.isEmpty {
                refinar(leitura.perguntas)
            }
            if !leitura.pecas.isEmpty {
                precoDaPessoa
            }
            if !leitura.parecidas.isEmpty {
                parecidas(leitura.parecidas)
            }
        }
    }

    private func cabecalho(_ leitura: LeituraEspecifica) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ChamadaDaEdicao(texto: frase("Reading"))
            Text(verbatim: leitura.nome ?? pedido)
                .font(Edicao.Tipo.manchete)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let explicacao = leitura.explicacao, !explicacao.isEmpty {
                Text(verbatim: explicacao)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let data = leitura.painelObservadoEm {
                let resumo = leitura.pecas.count == 1
                    ? frase("Panel of \(Formato.data(data)) · 1 piece read")
                    : frase("Panel of \(Formato.data(data)) · \(String(leitura.pecas.count)) pieces read")
                Text(resumo)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    private func refinar(_ perguntas: [LeituraEspecifica.Pergunta]) -> some View {
        Folha {
            CabecalhoDaFolha(titulo: Text("Narrow it down"), simbolo: "slider.horizontal.3")
            ForEach(perguntas, id: \.self) { pergunta in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: pergunta.pergunta)
                        .font(.subheadline)
                    FlowLayout(espaco: 8) {
                        ForEach(pergunta.opcoes, id: \.self) { opcao in
                            Button {
                                refinamento = opcao
                            } label: {
                                Text(verbatim: opcao)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(refinamento == opcao ? Edicao.bordo : Edicao.caneta)
                        }
                    }
                }
            }
        }
    }

    private var precoDaPessoa: some View {
        Folha {
            CabecalhoDaFolha(titulo: Text("Where does your price sit?"),
                             nota: frase("Type what your piece costs to compare it with the pieces above."),
                             simbolo: "tag")
            HStack(spacing: 10) {
                TextField(text: $precoDigitado, prompt: Text(verbatim: "R$ 450")) {
                    Text("Price of your piece")
                }
                .keyboardType(.decimalPad)
                .focused($editandoPreco)
                .textFieldStyle(.roundedBorder)
                Button("Compare") {
                    editandoPreco = false
                    preco = Self.valor(de: precoDigitado)
                }
                .buttonStyle(.borderedProminent)
                .tint(Edicao.bordoCheio)
                .disabled(Self.valor(de: precoDigitado) == nil)
            }
        }
    }

    private func parecidas(_ pecas: [LeituraEspecifica.Peca]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CabecalhoDaFolha(titulo: Text("Close, but not the same"),
                             nota: frase("Outside the numbers above: they share part of the construction."))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(pecas) { peca in
                        CartaoDaPecaLida(peca: peca)
                            .frame(width: 150)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Carga

    private func ler() async {
        carregando = true
        erro = nil
        limiteDoDia = false
        defer { carregando = false }
        #if DEBUG
        if Self.testeDeInterfaceAtivo {
            leitura = try? LeituraEspecifica.decodificar(Data("""
            {"versao":"teste-de-interface","nome":"vestido preto",
             "painel_observado_em":"2026-09-24",
             "frases":[{"texto":"Uma peça do painel corresponde ao pedido.","fatos":["total"]}],
             "fatos":{"total":{"pecas":1,"provas":[1]}},
             "pecas":[{"id":1,"titulo":"Vestido preto","marca":"Marca de teste",
                       "preco":450,"url":"https://example.invalid/peca"}],
             "parecidas":[],"perguntas":[]}
            """.utf8))
            return
        }
        #endif
        do {
            leitura = try await Supabase.shared.lerPeca(
                texto: pedido, refinamento: refinamento, descricao: descricao, preco: preco)
        } catch is CancellationError {
            return
        } catch Supabase.Falha.resposta(let codigo, _) where codigo == 429 {
            limiteDoDia = true
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? frase("The reading could not be made.")
        }
    }

    /// "R$ 1.299,90", "1299.9", "450" -> número.
    static func valor(de texto: String) -> Double? {
        var limpo = texto.replacingOccurrences(of: "R$", with: "")
            .trimmingCharacters(in: .whitespaces)
        if limpo.contains(",") {
            limpo = limpo.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard let v = Double(limpo), v > 0, v < 100_000 else { return nil }
        return v
    }
}

extension LeituraEspecifica.Frase: Identifiable {
    var id: String { texto }
}

// MARK: - Uma frase

private struct LinhaDaFrase: View {
    let frase: LeituraEspecifica.Frase
    let temProva: Bool
    let abrir: () -> Void

    var body: some View {
        Button(action: abrir) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: frase.texto)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if temProva {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Edicao.caneta)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!temProva)
        .accessibilityHint(temProva ? Text("Shows the pieces behind this sentence") : Text(""))
    }
}

// MARK: - A prova

/// As peças do painel por trás de uma frase.
private struct ProvaDaFrase: View {
    let frase: LeituraEspecifica.Frase
    let pecas: [LeituraEspecifica.Peca]
    @Environment(\.dismiss) private var fechar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: frase.texto)
                        .font(Edicao.Tipo.citacao)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pecas.count == 1
                         ? Canario.frase("1 piece from the panel backs this sentence.")
                         : Canario.frase("\(String(pecas.count)) pieces from the panel back this sentence."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                        ForEach(pecas) { peca in
                            CartaoDaPecaLida(peca: peca)
                        }
                    }
                }
                .padding(Edicao.margem)
            }
            .papelDaEdicao()
            .navigationTitle(Text("Proof"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { fechar() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Uma peça do painel: foto da loja, marca, nome, preço e o caminho para a loja.
private struct CartaoDaPecaLida: View {
    let peca: LeituraEspecifica.Peca

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FotoDoPainel(endereco: peca.imagemUrl)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Edicao.raioDaPeca, style: .continuous))
            Text(verbatim: peca.marca)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: peca.titulo)
                .font(Edicao.Tipo.nome)
                .lineLimit(2)
            if let preco = peca.preco {
                HStack(spacing: 6) {
                    Text(verbatim: Formato.dinheiro(preco))
                        .font(Edicao.Tipo.numero)
                    if peca.remarcada, let original = peca.precoOriginal {
                        Text(verbatim: Formato.dinheiro(original))
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let url = peca.url.flatMap(URL.init(string:)) {
                Link(destination: url) {
                    Label("Open in the store", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .tint(Edicao.bordo)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Enquanto lê

/// A leitura leva de 15 a 40 s. Dizer o passo em que está troca "travou?" por
/// "está lendo", sem fingir velocidade.
private struct LendoOPainel: View {
    @State private var passo = 0
    private let passos = [
        "Understanding what you asked…",
        "Finding pieces like it in the panel…",
        "Checking each piece…",
        "Counting prices, markdowns and restocks…",
        "Writing the reading…",
    ]

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(LocalizedStringKey(passos[min(passo, passos.count - 1)]))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .task {
            while passo < passos.count - 1 {
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.easeInOut) { passo += 1 }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
