import SwiftUI
import Charts

/// Relatório de um termo (§29, adaptado ao que existe hoje).
///
/// A ordem dos blocos segue a §29: resumo por template determinístico, índice
/// com pernas declaradas, minigráfico, insumos com fonte e data, e limites
/// declarados no fim.
///
/// **Sem LLM** (§29 proíbe na v1): o parágrafo-resumo é template fixo com slots
/// preenchidos exclusivamente por valores que o motor computou.
struct RelatorioDoTermo: View {
    let termo: Termo

    @State private var serie: [PontoSerie] = []
    @State private var indices: [IndiceSemanal] = []
    @State private var coberturas: [Cobertura] = []
    @State private var carregando = true
    @State private var erro: String?

    private var atual: IndiceSemanal? { indices.first }

    /// §8: sem cobertura, não há índice nem estado — só o que existe com
    /// honestidade. O portão vem antes de qualquer número na tela.
    ///
    /// A cobertura tem de ser a da MESMA SEMANA do índice exibido. Liberar a
    /// semana A com a cobertura da semana B é o mesmo erro de comparar
    /// declarado com gravado de dias diferentes — e foi o que aconteceu no
    /// primeiro teste: o índice era de 20/07 (4 peças, deveria bloquear) e a
    /// cobertura consultada era de 27/07 (364 peças, liberou).
    private var temCobertura: Bool {
        guard let semanaDoIndice = atual?.semana else { return false }
        guard let c = coberturas.first(where: { $0.semana == semanaDoIndice }) else {
            // Sem medição de cobertura para esta semana, não se afirma nada.
            return false
        }
        return c.suficiente
    }

    private var coberturaDaSemana: Cobertura? {
        atual.flatMap { i in coberturas.first(where: { $0.semana == i.semana }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else if !temCobertura {
                    CoberturaInsuficiente(
                        titulo: "Ainda não vi peças suficientes",
                        explicacao: "Para mostrar um número aqui eu preciso de pelo menos \(coberturaDaSemana?.minimoPecas ?? 30) peças de \(coberturaDaSemana?.minimoMarcas ?? 8) marcas diferentes nesta semana. \(coberturaDaSemana?.oQueFalta ?? "Esta semana ainda não foi medida").",
                        oQueTem: "Prefiro dizer que não sei do que mostrar um número frágil.")
                    grafico
                    curva
                    insumos
                    limites
                } else {
                    resumo
                    indiceEEstado
                    grafico
                    curva
                    insumos
                    limites
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .navigationTitle(termo.rotulo)
        .navigationBarTitleDisplayMode(.large)
        .task { await carregar() }
    }

    // MARK: Blocos

    /// §24 no relatório do atributo.
    ///
    /// Fica **abaixo do gráfico e acima dos insumos** de propósito: é camada
    /// descritiva de varejo (B1.3), não entra no índice, e misturar as duas
    /// coisas faria parecer que a curva de tamanhos move o z-score. Não move.
    private var curva: some View {
        NavigationLink {
            CurvaDeTamanhosView(termo: termo)
        } label: {
            Cartao {
                HStack(alignment: .firstTextBaseline) {
                    Text("Curva de tamanhos").font(Tokens.Fonte.secao)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
                Text("Onde a grade quebra nas peças do painel que têm \(termo.rotulo.lowercased()).")
                    .font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                LinhaInsumo(texto: "Descritivo de varejo: não entra no índice nem no estado.")
            }
        }
        .buttonStyle(.plain)
    }

    /// §29.1 — template determinístico. Cada frase só existe se o número que a
    /// sustenta existir; nada é preenchido com valor plausível.
    private var resumo: some View {
        Cartao {
            Text(frase).font(Tokens.Fonte.corpo)
        }
    }

    private var frase: String {
        guard let atual, let valor = atual.indice else {
            return "Ainda não tenho índice para \(termo.rotulo) neste recorte."
        }
        let pernas = Perna.frase(atual.pernasAtivas)
        if let bruto = atual.estado, let e = Estado(rawValue: bruto) {
            return "\(termo.rotulo) está \(e.rotulo.lowercased()) e \(Leitura.emPalavras(valor)) na semana de \(Formato.data(atual.semana)). Leitura \(pernas)."
        }
        return "\(termo.rotulo) tem índice \(fmt(valor)) na semana de \(Formato.data(atual.semana)), mas não há cobertura para declarar um estado: isso exige duas fontes concordando. Leitura \(pernas)."
    }

    /// §29.3 — índice, estado e as pernas ativas declaradas.
    private var indiceEEstado: some View {
        Cartao {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    // K6: a leitura vem primeiro; o número técnico fica ao lado,
                    // menor, e nunca é apresentado como se fosse porcentagem.
                    Text(atual?.indice.map { Leitura.emPalavras($0) } ?? "sem leitura")
                        .font(Tokens.Fonte.secao)
                    Text(atual?.indice.map(fmt) ?? "—")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
                Spacer()
                SeloEstado(estado: atual?.estado,
                           motivo: "Só afirmo uma direção quando duas fontes concordam.")
            }
            if let z = atual?.indice {
                LinhaInsumo(texto: Leitura.explicacao(z))
            }
            LinhaInsumo(texto: Perna.frase(atual?.pernasAtivas))
            if atual?.estado == nil {
                LinhaInsumo(texto: "Mostro o número, mas ainda não digo se subiu ou caiu: por enquanto só uma fonte tem histórico suficiente.")
            }
        }
    }

    /// Minigráfico do §29.3, uma linha por perna.
    @ViewBuilder
    private var grafico: some View {
        let comZ = serie.filter { $0.z != nil }
        if comZ.isEmpty {
            CoberturaInsuficiente(
                titulo: "Ainda estou juntando histórico",
                explicacao: "Preciso de algumas semanas seguidas de um mesmo lugar antes de dizer se algo mudou. Nenhuma fonte chegou lá ainda.",
                oQueTem: serie.isEmpty ? nil : "Já coletei \(serie.count) medições — elas ficam guardadas até virarem histórico.")
        } else {
            Cartao {
                Text("Histórico").font(Tokens.Fonte.secao)
                Chart(comZ) { ponto in
                    LineMark(
                        x: .value("Semana", ponto.semana),
                        y: .value("z", ponto.z ?? 0)
                    )
                    .foregroundStyle(by: .value("Fonte", Perna.rotulo(ponto.fonte)))
                }
                .chartXAxis(.hidden)
                .frame(height: 160)
                .accessibilityLabel("Histórico por fonte ao longo das semanas")
                LinhaInsumo(texto: "Cada ponto compara a semana com as 12 anteriores deste mesmo atributo.")
            }
        }
    }

    /// §29.4 — um bloco por fator, com fonte e data.
    private var insumos: some View {
        Cartao {
            Text("Insumos").font(Tokens.Fonte.secao)
            ForEach(porFonte, id: \.0) { fonte, pontos in
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    Text(Perna.rotulo(fonte).capitalized).font(Tokens.Fonte.apoio)
                    if let v = Leitura.variacao(
                        recente: pontos.first?.valorBruto,
                        media: mediaDaJanela(pontos)) {
                        Text(v).font(Tokens.Fonte.apoio)
                    }
                    LinhaInsumo(texto: "\(pontos.count) semanas · mais recente em \(Formato.data(pontos.first?.semana ?? "—"))")
                }
                .padding(.vertical, Tokens.Espaco.xs)
            }
        }
    }

    private var porFonte: [(String, [PontoSerie])] {
        Dictionary(grouping: serie, by: \.fonte)
            .map { ($0.key, $0.value.sorted { $0.semana > $1.semana }) }
            .sorted { $0.0 < $1.0 }
    }

    /// §29.6 — limites declarados. Fica no relatório sempre, não só quando dá ruim.
    private var limites: some View {
        Cartao {
            Text("Limites").font(Tokens.Fonte.secao)
            LinhaInsumo(texto: "Não consideramos: seu histórico de vendas, seus custos, sua capacidade de produção.")
            LinhaInsumo(texto: "Sinal editorial carrega viés comercial de publicidade.")
            if termo.semPernaBusca == "sim" {
                LinhaInsumo(texto: "Não acompanho buscas para este atributo: o volume no Google é baixo demais para ser confiável.")
            }
        }
    }

    // MARK: Dados

    /// Média das 12 semanas anteriores à mais recente — a mesma janela do
    /// z-score (§21), para o percentual e o desvio falarem da mesma coisa.
    private func mediaDaJanela(_ pontos: [PontoSerie]) -> Double? {
        let janela = pontos.dropFirst().prefix(12).compactMap(\.valorBruto)
        guard !janela.isEmpty else { return nil }
        return janela.reduce(0, +) / Double(janela.count)
    }

    private func fmt(_ v: Double) -> String {
        Leitura.numero(v, casas: 2, sinal: true)
    }

    private func carregar() async {
        carregando = true
        erro = nil
        do {
            async let s: [PontoSerie] = Supabase.shared.buscar(
                "series_semanais",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=eq.\(termo.id)&order=semana.desc&limit=600")
            async let i: [IndiceSemanal] = Supabase.shared.buscar(
                "indices_semanais",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=eq.\(termo.id)&order=semana.desc&limit=60")
            async let c: [Cobertura] = Supabase.shared.buscar(
                "cobertura_por_celula",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=eq.\(termo.id)&order=semana.desc&limit=60")
            serie = try await s
            indices = try await i
            coberturas = try await c
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}
