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
            // Sem título grande: o campo de busca no rodapé já diz o que esta
            // tela é, e o cabeçalho só empurrava o resultado para baixo.
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $texto,
                        prompt: "Search by garment, fabric, cut, pattern…")
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

    /// Busca é um VERBO, e esta tela estava desenhada como um lugar.
    ///
    /// No iOS 26 o sistema já faz o que se queria: ao entrar na busca, a barra
    /// inferior encolhe e a lupa vira um campo de texto no rodapé. O que fazia
    /// isto parecer "mais uma tela" era o que ficava por cima do campo — um
    /// título grande, dois parágrafos de explicação e um botão de importar.
    ///
    /// O botão saiu porque duplicava a aba Add inteira. O comentário que estava
    /// aqui dizia, sobre outra duplicata: "o mesmo botão em dois lugares só
    /// divide a atenção". Este era o terceiro lugar.
    ///
    /// Sobrou o que ajuda quem parou na frente de um campo vazio: exemplos do
    /// que dá para digitar.
    private var abertura: some View {
        VStack(spacing: Tokens.Espaco.s) {
            Text("Search by garment, fabric, cut, pattern…")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            Text("Try: " + sugestoes.prefix(3).joined(separator: ", "))
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Tokens.Espaco.g)
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
