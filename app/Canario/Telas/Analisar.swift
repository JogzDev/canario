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
            .navigationTitle("Analisar")
            .searchable(text: $texto, prompt: "Descreva a peça: vestido de bolinha, saia midi…")
            .sheet(isPresented: $importando) {
                ImportarPeca(termos: termos)
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
                    titulo: "Não acompanho este termo ainda",
                    explicacao: "“\(texto)” não está na taxonomia. Ela é uma lista fechada e revisada, e prefiro dizer que não sei a inventar uma leitura.",
                    oQueTem: "Termos próximos: " + sugestoes.joined(separator: ", ")
                )
                .padding(Tokens.Espaco.m)
            }
        } else {
            List {
                if descreveUmaPeca {
                    Section("Você descreveu uma peça") {
                        NavigationLink {
                            RelatorioDaPeca(termos: casados)
                        } label: {
                            VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                                Text(casados.map(\.rotulo).joined(separator: " + "))
                                    .font(Tokens.Fonte.corpo)
                                LinhaInsumo(texto: "Ler como conjunto, e não como \(casados.count) atributos soltos.")
                            }
                        }
                    }
                }
                Section(descreveUmaPeca ? "Ou atributo por atributo" : "Atributos") {
                    ForEach(casados) { termo in
                        NavigationLink {
                            RelatorioDoTermo(termo: termo)
                        } label: {
                            LinhaTermo(termo: termo, indice: indices[termo.id])
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
                Text("Busque por um atributo ou descreva a peça.")
                    .font(Tokens.Fonte.corpo)
                Text("Acompanho \(termos.count) termos. O que você digitar é traduzido para eles — não é filtro de texto livre.")
                    .font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                Divider()
                // O único atalho de importação da tela. O que ficava no canto
                // superior direito saiu: aquele lugar é de configurações, e o
                // mesmo botão em dois lugares só divide a atenção.
                Button {
                    importando = true
                } label: {
                    Label("Importar print, foto ou PDF", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(termos.isEmpty)
                Text("Leio o arquivo no próprio aparelho: título por reconhecimento de texto, cor pelo pixel. Nada é enviado nem guardado.")
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
            .prefix(5).map(\.rotulo)
    }

    private func carregar() async {
        carregando = true
        erro = nil
        do {
            termos = try await Supabase.shared.buscar(
                "termos", "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca,palavras_pt,palavras_en&order=dimensao,id")
            let recentes: [IndiceSemanal] = try await Supabase.shared.buscar(
                "indices_do_app", "select=*&order=semana.desc&limit=400")
            var mapa: [String: IndiceSemanal] = [:]
            for i in recentes where mapa[i.termoId] == nil { mapa[i.termoId] = i }
            indices = mapa
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

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
            HStack {
                Text(termo.rotulo).font(Tokens.Fonte.corpo)
                Spacer()
                SeloEstado(estado: indice?.estado,
                           motivo: "Menos de duas pernas ativas nesta semana.")
            }
            Text(termo.dimensao)
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            if let indice {
                LinhaInsumo(texto: Perna.frase(indice.pernasAtivas) + " · semana de \(Formato.data(indice.semana))")
            }
        }
        .padding(.vertical, Tokens.Espaco.xs)
    }
}
