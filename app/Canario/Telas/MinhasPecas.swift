import SwiftUI

/// As peças que o usuário já montou.
///
/// **Por que esta tela existe.** A §27 diz que Comparar *"pressupõe peças já
/// analisadas"*, e o app não guardava nenhuma — trocar de aba apagava tudo. Na
/// revisão de 03/08 isso apareceu como *"a tab Comparar tá bem confusa, não
/// entendi tão bem"*. A aba não estava confusa por desenho de tela: faltava o
/// insumo dela.
///
/// **O que ela não é.** Não é armário (§34, A10). Guarda só o que o usuário
/// digitou; todo número é recomputado do dado de hoje ao abrir o relatório.
/// Nenhum alerta, nenhum histórico por peça.
struct MinhasPecas: View {
    @State private var pecas: [PecaSalva] = []
    @State private var termos: [Termo] = []
    @State private var carregando = true
    @State private var erro: String?

    private var rotulos: [String: String] {
        Dictionary(uniqueKeysWithValues: termos.map { ($0.id, $0.rotulo) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if carregando {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pecas.isEmpty {
                    vazio
                } else {
                    lista
                }
            }
            .navigationTitle("Minhas peças")
            .toolbar {
                if !pecas.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
        }
        .task { await carregar() }
    }

    // MARK: - Estados

    private var vazio: some View {
        VStack(spacing: Tokens.Espaco.m) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Nenhuma peça ainda").font(Tokens.Fonte.secao)
            // Diz o que fazer, e não só o que falta.
            Text("As peças que você montar em Adicionar ficam aqui, "
                 + "prontas para abrir de novo e para comparar entre si.")
                .font(Tokens.Fonte.corpo)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Tokens.Espaco.g)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lista: some View {
        List {
            if let erro {
                Text(erro).font(Tokens.Fonte.corpo).foregroundStyle(.secondary)
            }

            Section {
                ForEach(pecas) { peca in
                    NavigationLink {
                        // O relatório é recomputado do dado de hoje: a peça
                        // salva só diz QUAIS atributos, nunca que número deu.
                        RelatorioDaPeca(termos: termos.filter {
                            peca.termoIds.contains($0.id)
                        })
                    } label: {
                        LinhaDaPecaSalva(peca: peca, rotulos: rotulos)
                    }
                }
                .onDelete { indices in
                    let alvos = indices.map { pecas[$0].id }
                    pecas.remove(atOffsets: indices)
                    Task { for id in alvos { await PecasSalvas.shared.apagar(id) } }
                }
            } footer: {
                Text("\(pecas.count) de \(PecasSalvas.teto). "
                     + "Os números são recalculados toda vez que você abre uma peça.")
                    .font(Tokens.Fonte.miudo)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Carga

    private func carregar() async {
        carregando = true
        erro = nil
        pecas = await PecasSalvas.shared.todas()
        do {
            termos = try await Supabase.shared.buscar(
                "termos",
                "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca,"
                + "palavras_pt,palavras_en&order=dimensao,id")
        } catch {
            // Sem a taxonomia a lista ainda serve: o nome cai no id, que é feio
            // e verdadeiro. Abrir o relatório é que não dá.
            erro = "Não consegui carregar a taxonomia agora. "
                 + "As peças estão aqui; os relatórios voltam quando a conexão voltar."
        }
        carregando = false
    }
}

/// Uma linha da lista: o nome e os atributos que a sustentam.
struct LinhaDaPecaSalva: View {
    let peca: PecaSalva
    let rotulos: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
            Text(peca.nome(comRotulos: rotulos))
                .font(Tokens.Fonte.corpo)
                .lineLimit(2)
            if !peca.termoIds.isEmpty {
                Text(peca.termoIds.compactMap { rotulos[$0] ?? $0 }
                        .joined(separator: " · "))
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
