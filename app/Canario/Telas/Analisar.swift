import SwiftUI

/// Aba **Analisar** (§27): entrada por busca textual.
///
/// A §11 é explícita: "a barra de busca do app nunca vira filtro de texto cru".
/// A string do usuário é traduzida para termos da taxonomia via rótulos,
/// sinônimos e as mesmas palavras que o coletor usa; o que não casar gera
/// resposta honesta, em vez de silêncio ou de resultado vazio.
///
/// ## O que o JP apontou em 31/07
///
/// Ele buscou **"vestido de bolinha"** e recebeu só "Vestido". Dois defeitos
/// diferentes no mesmo resultado:
///
/// 1. `bolinha` não estava no vocabulário. A taxonomia tinha `poá`, que é o
///    nome técnico, e não o nome que o comprador usa. Corrigido no termo
///    `geometrica`, que agora responde aos dois.
/// 2. Mesmo com as duas palavras reconhecidas, a tela listaria dois termos
///    soltos — e, como ele disse, vestido de bolinha "claramente não é a mesma
///    coisa que vestido, e não teria as mesmas estatísticas". Uma busca que
///    descreve **uma peça** tem de responder sobre a peça, não sobre cada
///    palavra dela em separado.
///
/// Por isso a busca com dois ou mais atributos passa a oferecer a leitura do
/// conjunto — o mesmo caminho da entrada por arquivo, que já funcionava assim.
struct Analisar: View {
    var aoFechar: (() -> Void)?
    @State private var termos: [Termo] = []
    @State private var texto = ""
    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var carregando = true
    @State private var erro: String?
    @State private var importando = false

    /// A tradução vive em `Traducao`, que é testada. Aqui a tela só consome.
    private var casados: [Termo] {
        Traducao.termos(para: texto, em: termos)
    }

    /// Quando a busca descreve uma peça, e não um atributo isolado.
    private var descreveUmaPeca: Bool {
        Set(casados.map(\.dimensao)).count >= 2
    }

    private var descricaoDaBusca: String {
        Traducao.descricaoAmigavel(casados, consulta: texto)
    }

    var body: some View {
        NavigationStack {
            Group {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else {
                    lista
                }
            }
            .navigationTitle("Search")
            .searchable(text: $texto, prompt: "Describe an item: polka-dot dress, midi skirt…")
            .sheet(isPresented: $importando) {
                ImportarPeca(termos: termos)
            }
            .toolbar {
                if let aoFechar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: aoFechar)
                    }
                }
            }
        }
        .task { await carregar() }
    }

    @ViewBuilder
    private var lista: some View {
        if texto.isEmpty {
            abertura
        } else if casados.isEmpty {
            ScrollView {
                CoberturaInsuficiente(
                    titulo: "This term isn't tracked yet",
                    explicacao: "“\(texto)” is outside the reviewed vocabulary, so there is no market reading for it yet.",
                    oQueTem: "Try: " + sugestoes.joined(separator: ", ")
                )
                .padding(Tokens.Espaco.m)
            }
        } else {
            List {
                if descreveUmaPeca {
                    Section("Your item") {
                        NavigationLink {
                            RelatorioDaPeca(termos: casados, pecaSalva: nil,
                                           descricaoAmigavel: descricaoDaBusca)
                        } label: {
                            VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                                Text(descricaoDaBusca)
                                    .font(Tokens.Fonte.corpo)
                                LinhaInsumo(texto: "Open the combined reading and similar pieces.")
                            }
                        }
                    }
                }
                Section(descreveUmaPeca ? "Or explore each attribute" : "Attributes") {
                    ForEach(casados) { termo in
                        NavigationLink {
                            RelatorioDoTermo(termo: termo)
                        } label: {
                            LinhaTermo(termo: termo, indice: indices[termo.id],
                                       rotulo: Traducao.rotuloAmigavel(termo, na: texto))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var abertura: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.m) {
                Text("Search for an attribute or describe an item.")
                    .font(Tokens.Fonte.corpo)
                Text("The app tracks \(termos.count) reviewed fashion terms and maps your wording to them.")
                    .font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                Divider()
                // O único atalho de importação da tela. O que ficava no canto
                // superior direito saiu: aquele lugar é de configurações, e o
                // mesmo botão em dois lugares só divide a atenção.
                Button {
                    importando = true
                } label: {
                    Label("Analyze a photo or file", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.bordered)
                .disabled(termos.isEmpty)
                Text(Supabase.analiseRemotaHabilitada
                     ? "The photo stays on your iPhone until you explicitly approve a one-time visual analysis."
                     : "This build analyzes the file on your iPhone. Nothing is uploaded or stored unless you save the item.")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Espaco.m)
        }
    }

    /// Sugestão simples: os primeiros termos de cada dimensão. Não é busca
    /// aproximada — é só não deixar o usuário na parede.
    private var sugestoes: [String] {
        var vistas = Set<String>()
        return termos.filter { vistas.insert($0.dimensao).inserted }
            .prefix(5).map(Traducao.rotuloExibido)
    }

    private func carregar() async {
        carregando = true
        erro = nil
        do {
            // Ambos são snapshots compartilhados e normalmente já foram
            // aquecidos pela Home. Nenhuma troca de aba reabre o mesmo TLS.
            async let t = CatalogoDeTermos.shared.carregar()
            async let i = CatalogoDeIndices.shared.carregar()
            termos = try await t
            carregando = false
            let recentes = try await i
            // A linha mais nova pode ter só busca OU editorial e, portanto,
            // nenhum estado. Quando há um estado realmente medido nas 12
            // semanas anteriores, mostramos esse último estado com sua data.
            indices = SelecaoDeEstado.porTermo(recentes)
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}

/// Uma linha de resultado: rótulo, dimensão, estado e as pernas que o sustentam.
struct LinhaTermo: View {
    let termo: Termo
    let indice: IndiceSemanal?
    var rotulo: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
            HStack {
                Text(rotulo ?? Traducao.rotuloExibido(termo)).font(Tokens.Fonte.corpo)
                Spacer()
                SeloEstado(estado: indice?.estado,
                           motivo: "Fewer than two independent sources agree.",
                           leitura: indice?.indice)
            }
            Text(Traducao.rotuloDaDimensao(termo.dimensao))
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            if let indice {
                LinhaInsumo(texto: Perna.frase(indice.pernasAtivas)
                            + " · updated \(Formato.data(indice.semana))")
            }
        }
        .padding(.vertical, Tokens.Espaco.xs)
    }
}
