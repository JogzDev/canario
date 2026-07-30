import SwiftUI

/// Aba **Explorar** (§27): valor de esforço zero na abertura.
///
/// O §27 pede quatro blocos: ruptura da semana, reposições da semana, novidades
/// por cluster e o digest do que mudou. Hoje só o último existe — os três
/// primeiros dependem da tabela de eventos, que ainda não é computada.
///
/// A tela **declara isso** em vez de esconder. Mostrar bloco vazio sem explicar
/// faz o app parecer quebrado; dizer o que falta e por quê é o que a regra 6
/// pede, e é a mesma honestidade que o marco de demo 3 quer demonstrar.
struct Explorar: View {
    @State private var todos: [IndiceSemanal] = []

    /// Um termo por linha, com a mudança MAIS RECENTE dele.
    ///
    /// Sem isto o mesmo termo aparecia várias vezes — "Casaco e jaqueta" saía
    /// duas vezes, nas semanas 13/07 e 06/07. Digest é resumo do que mudou, não
    /// histórico: repetir o termo gasta a atenção do usuário sem informar.
    private var mudaram: [IndiceSemanal] {
        var vistos = Set<String>()
        return todos.filter { vistos.insert($0.termoId).inserted }
    }
    @State private var rotulos: [String: String] = [:]
    @State private var carregando = true
    @State private var erro: String?

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
            .navigationTitle("Explorar")
        }
        .task { await carregar() }
    }

    private var conteudo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                digest
                pendentes
            }
            .padding(Tokens.Espaco.m)
        }
    }

    /// O bloco que existe: o que mudou de estado nas semanas recentes.
    private var digest: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            Text("O que mudou").font(Tokens.Fonte.secao)
            if mudaram.isEmpty {
                CoberturaInsuficiente(
                    titulo: "Nenhum termo mudou de estado",
                    explicacao: "Nas semanas recentes, nenhum atributo cruzou os limiares que a §22 exige para declarar mudança.",
                    oQueTem: "Isso é resultado, não ausência de dado: os limiares existem justamente para uma semana isolada não virar notícia.")
            } else {
                ForEach(mudaram) { i in
                    Cartao {
                        HStack(alignment: .firstTextBaseline) {
                            Text(rotulos[i.termoId] ?? i.termoId).font(Tokens.Fonte.corpo)
                            Spacer()
                            // O número junto do selo: o estado diz a direção, o
                            // índice diz o tamanho. Só o rótulo informava pouco.
                            Text(i.indice.map { String(format: "%+.2f", $0) } ?? "—")
                                .font(Tokens.Fonte.numero)
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                            SeloEstado(estado: i.estado, motivo: nil)
                        }
                        LinhaInsumo(texto: Perna.frase(i.pernasAtivas) + " · semana de \(i.semana)")
                    }
                }
            }
        }
    }

    /// Os blocos que a §27 pede e que ainda não têm dado. Declarados, não ocultos.
    private var pendentes: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.m) {
            Text("Ainda sem cobertura").font(Tokens.Fonte.secao)
            CoberturaInsuficiente(
                titulo: "Ruptura e reposições da semana",
                explicacao: "Dependem dos eventos de grade, que o motor ainda não computa. Reposição exige ver um tamanho sair e voltar de forma persistente, e a coleta de varejo começou em 24/07.",
                oQueTem: "O histórico necessário se acumula sozinho a cada noite de coleta.")
            CoberturaInsuficiente(
                titulo: "Novidades por cluster",
                explicacao: "Depende do primeiro avistamento por produto ao longo de várias semanas.",
                oQueTem: nil)
        }
    }

    private func carregar() async {
        carregando = true
        erro = nil
        do {
            async let i: [IndiceSemanal] = Supabase.shared.buscar(
                "indices_semanais",
                "select=*&estado=in.(\"em alta\",\"em queda\",pico)&order=semana.desc&limit=200")
            async let t: [Termo] = Supabase.shared.buscar(
                "termos", "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca")
            todos = try await i
            rotulos = Dictionary(uniqueKeysWithValues: try await t.map { ($0.id, $0.rotulo) })
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}
