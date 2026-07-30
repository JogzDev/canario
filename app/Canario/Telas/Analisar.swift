import SwiftUI

/// Aba **Analisar** (§27): entrada por busca textual.
///
/// A §11 é explícita: "a barra de busca do app nunca vira filtro de texto cru".
/// A string do usuário é traduzida para termos da taxonomia via rótulos e
/// sinônimos; o que não casar gera resposta honesta com sugestão dos termos
/// próximos, em vez de silêncio ou de resultado vazio.
///
/// A entrada por foto saiu da v1 (A7), então a busca textual é a única — o que
/// já era o padrão por decisão de privacidade.
struct Analisar: View {
    @State private var termos: [Termo] = []
    @State private var texto = ""
    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var carregando = true
    @State private var erro: String?

    /// A tradução vive em `Traducao`, que é testada. Aqui a tela só consome.
    private var casados: [Termo] {
        Traducao.termos(para: texto, em: termos)
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
            .searchable(text: $texto, prompt: "Descreva a peça: vestido floral midi…")
        }
        .task { await carregar() }
    }

    @ViewBuilder
    private var lista: some View {
        if texto.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Espaco.m) {
                    Text("Busque por um atributo ou categoria.")
                        .font(Tokens.Fonte.corpo)
                    Text("Acompanho \(termos.count) termos. O que você digitar é traduzido para eles — não é filtro de texto livre.")
                        .font(Tokens.Fonte.apoio)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Espaco.m)
            }
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
            List(casados) { termo in
                NavigationLink {
                    RelatorioDoTermo(termo: termo)
                } label: {
                    LinhaTermo(termo: termo, indice: indices[termo.id])
                }
            }
            .listStyle(.plain)
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
                "termos", "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca&order=dimensao,id")
            let recentes: [IndiceSemanal] = try await Supabase.shared.buscar(
                "indices_semanais", "select=*&order=semana.desc&limit=400")
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
                LinhaInsumo(texto: Perna.frase(indice.pernasAtivas) + " · semana de \(indice.semana)")
            }
        }
        .padding(.vertical, Tokens.Espaco.xs)
    }
}
