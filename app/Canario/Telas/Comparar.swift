import SwiftUI

/// Aba **Comparar** (§27): ranking relativo entre os termos que o usuário
/// escolhe, com uma linha de motivo por item — nunca só o número.
///
/// O disclaimer da §27 é fixo na tela e não é decoração: é a regra inviolável 1
/// aparecendo onde ela mais pode ser violada, que é justamente num ranking.
struct Comparar: View {
    @State private var termos: [Termo] = []
    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var escolhidos: Set<String> = []
    @State private var carregando = true
    @State private var erro: String?

    private let maximo = 6   // §27: de 2 a 6 peças

    var body: some View {
        NavigationStack {
            Group {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else {
                    conteudo
                }
            }
            .navigationTitle("Comparar")
        }
        .task { await carregar() }
    }

    private var conteudo: some View {
        VStack(spacing: 0) {
            aviso
            List {
                if escolhidos.count >= 2 {
                    Section("Ranking relativo") {
                        ForEach(Array(ranking.enumerated()), id: \.element.id) { posicao, termo in
                            linhaRanking(posicao: posicao + 1, termo: termo)
                        }
                    }
                }
                Section(escolhidos.count >= 2 ? "Trocar seleção" : "Escolha de 2 a \(maximo)") {
                    ForEach(termos) { termo in
                        Button {
                            alternar(termo.id)
                        } label: {
                            HStack {
                                Image(systemName: escolhidos.contains(termo.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(escolhidos.contains(termo.id)
                                                     ? Tokens.Cor.tinta : Tokens.Cor.semDado)
                                Text(termo.rotulo).foregroundStyle(Tokens.Cor.tinta)
                                Spacer()
                                Text(termo.dimensao)
                                    .font(Tokens.Fonte.miudo)
                                    .foregroundStyle(Tokens.Cor.tintaFraca)
                            }
                        }
                        .disabled(!escolhidos.contains(termo.id) && escolhidos.count >= maximo)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// §27: disclaimer fixo. "Não é previsão de venda" está aqui porque um
    /// ranking é exatamente onde o usuário mais tende a ler previsão.
    private var aviso: some View {
        Text("Ranking relativo entre os termos que você escolheu, calculado agora sobre dados já coletados. Não é previsão de venda.")
            .font(Tokens.Fonte.miudo)
            .foregroundStyle(Tokens.Cor.tintaFraca)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Espaco.m)
            .background(Tokens.Cor.superficie)
    }

    /// Ordena pelo índice. Quem não tem índice vai para o fim, e a linha de
    /// motivo diz o porquê — em vez de aparecer como se fosse o pior colocado.
    private var ranking: [Termo] {
        termos.filter { escolhidos.contains($0.id) }
            .sorted { (indices[$0.id]?.indice ?? -.infinity) > (indices[$1.id]?.indice ?? -.infinity) }
    }

    private func linhaRanking(posicao: Int, termo: Termo) -> some View {
        let i = indices[termo.id]
        return VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
            HStack {
                Text("\(posicao)").font(Tokens.Fonte.numero)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                Text(termo.rotulo).font(Tokens.Fonte.corpo)
                Spacer()
                Text(i?.indice.map { String(format: "%+.2f", $0) } ?? "—")
                    .font(Tokens.Fonte.numero)
            }
            // §27: uma linha de motivo por item, nunca só o número.
            LinhaInsumo(texto: motivo(termo: termo, indice: i))
        }
        .padding(.vertical, Tokens.Espaco.xs)
    }

    private func motivo(termo: Termo, indice: IndiceSemanal?) -> String {
        guard let indice, let valor = indice.indice else {
            return "Sem índice: nenhuma perna deste termo atingiu o mínimo de história."
        }
        let pernas = Perna.frase(indice.pernasAtivas)
        let direcao = valor >= 0 ? "acima" : "abaixo"
        return "Índice \(direcao) da própria média histórica, \(pernas), semana de \(Formato.data(indice.semana))."
    }

    private func alternar(_ id: String) {
        if escolhidos.contains(id) { escolhidos.remove(id) }
        else if escolhidos.count < maximo { escolhidos.insert(id) }
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
