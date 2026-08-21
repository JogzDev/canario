import SwiftUI
import Charts

/// Relatório de um termo (§29, adaptado ao que existe hoje).
///
/// A ordem dos blocos segue a §29: resumo por template determinístico, índice
/// com pernas declaradas, minigráfico e insumos com fonte e data.
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
    @State private var janelaEmMeses = 6
    @State private var curvaDisponivel = false

    private var maisRecente: IndiceSemanal? { indices.first }
    private var atual: IndiceSemanal? { SelecaoDeEstado.preferida(em: indices) }

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else if !temCobertura {
                    // O portão continua fechado no modelo; a interface apenas
                    // omite a afirmação que não pode sustentar, sem abrir o
                    // relatório com um cartão de fracasso.
                    grafico
                    curva
                    insumos
                } else {
                    resumo
                    indiceEEstado
                    grafico
                    curva
                    insumos
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .navigationTitle(Traducao.rotuloExibido(termo))
        .navigationBarTitleDisplayMode(.large)
        .task { await carregar() }
    }

    // MARK: Blocos

    /// §24 no relatório do atributo.
    ///
    /// Fica **abaixo do gráfico e acima dos insumos** de propósito: é camada
    /// descritiva de varejo (B1.3), não entra no índice, e misturar as duas
    /// coisas faria parecer que a curva de tamanhos move o z-score. Não move.
    @ViewBuilder
    private var curva: some View {
        if curvaDisponivel {
            NavigationLink {
                CurvaDeTamanhosView(termo: termo)
            } label: {
                Cartao {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Size availability").font(Tokens.Fonte.secao)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Tokens.Fonte.miudo)
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                    }
                    Text("Where size availability breaks among panel items with \(Traducao.rotuloExibido(termo).lowercased()).")
                        .font(Tokens.Fonte.apoio)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                    LinhaInsumo(texto: "Retail context only; it does not affect the index or state.")
                }
            }
            .buttonStyle(.plain)
        }
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
            return "There is no index for \(Traducao.rotuloExibido(termo)) in this panel cut yet."
        }
        let pernas = Perna.frase(atual.pernasAtivas)
        if let bruto = atual.estado, let e = Estado(rawValue: bruto) {
            let prefixo = atual.semana == maisRecente?.semana
                ? "In the latest week with a reading"
                : "In the latest week when two sources overlapped"
            return "\(prefixo), \(Formato.data(atual.semana)), \(Traducao.rotuloExibido(termo)) was \(e.rotulo.lowercased()) and \(Leitura.emPalavras(valor)). Reading \(pernas)."
        }
        return "\(Traducao.rotuloExibido(termo)) has an index of \(fmt(valor)) for the week of \(Formato.data(atual.semana)), but a state requires two agreeing sources. Reading \(pernas)."
    }

    /// §29.3 — índice, estado e as pernas ativas declaradas.
    private var indiceEEstado: some View {
        Cartao {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    // K6: a leitura vem primeiro; o número técnico fica ao lado,
                    // menor, e nunca é apresentado como se fosse porcentagem.
                    Text(atual?.indice.map { Leitura.emPalavras($0) } ?? "—")
                        .font(Tokens.Fonte.secao)
                    Text(atual?.indice.map(fmt) ?? "—")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
                Spacer()
                SeloEstado(estado: atual?.estado,
                           leitura: temCobertura ? atual?.indice : nil)
            }
            if let z = atual?.indice {
                LinhaInsumo(texto: Leitura.explicacao(z))
            }
            LinhaInsumo(texto: Perna.frase(atual?.pernasAtivas))
        }
    }

    /// Minigráfico do §29.3, uma linha por perna.
    @ViewBuilder
    private var grafico: some View {
        let comZ = serieComparavel
        if !comZ.isEmpty {
            Cartao {
                HStack {
                    Text("Comparable history").font(Tokens.Fonte.secao)
                    Spacer()
                    Picker("Period", selection: $janelaEmMeses) {
                        Text("3M").tag(3)
                        Text("6M").tag(6)
                        Text("1Y").tag(12)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 170)
                }
                Chart(comZ) { ponto in
                    LineMark(
                        x: .value("Week", Formato.dataISO(ponto.semana) ?? .distantPast),
                        y: .value("z", ponto.z ?? 0)
                    )
                    .foregroundStyle(by: .value("Source", Perna.rotulo(ponto.fonte)))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Weekly history by source")
                LinhaInsumo(texto: "To keep lines comparable, the chart shows only weeks measured by every displayed source. Each source's latest date remains listed below.")
            }
        }
    }

    private var serieComparavel: [PontoSerie] {
        let comZ = serie.filter { $0.z != nil && Formato.dataISO($0.semana) != nil }
        guard let semanaMaisNova = comZ.compactMap({ Formato.dataISO($0.semana) }).max(),
              let corte = Calendar(identifier: .iso8601).date(
                byAdding: .month, value: -janelaEmMeses, to: semanaMaisNova)
        else { return comZ }

        let naJanela = comZ.filter {
            guard let data = Formato.dataISO($0.semana) else { return false }
            return data >= corte
        }
        let fontes = Set(naJanela.map(\.fonte))
        guard fontes.count > 1 else { return naJanela }
        let porSemana = Dictionary(grouping: naJanela, by: \.semana)
        let compartilhadas = Set(porSemana.compactMap { semana, pontos in
            Set(pontos.map(\.fonte)).isSuperset(of: fontes) ? semana : nil
        })
        return naJanela.filter { compartilhadas.contains($0.semana) }
    }

    /// §29.4 — um bloco por fator, com fonte e data.
    private var insumos: some View {
        Cartao {
            Text("Sources").font(Tokens.Fonte.secao)
            ForEach(porFonte, id: \.0) { fonte, pontos in
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    Text(Perna.rotulo(fonte).capitalized).font(Tokens.Fonte.apoio)
                    if let v = Leitura.variacao(
                        recente: pontos.first?.valorBruto,
                        media: mediaDaJanela(pontos)) {
                        Text(v).font(Tokens.Fonte.apoio)
                    }
                    LinhaInsumo(texto: "\(pontos.count) weeks · latest on \(Formato.data(pontos.first?.semana ?? "—"))")
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
                "series_do_app",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=eq.\(termo.id)&order=semana.desc&limit=600")
            async let i = CatalogoDeIndices.shared.carregar()
            async let c: [Cobertura] = Supabase.shared.buscar(
                "cobertura_por_celula",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=eq.\(termo.id)&order=semana.desc&limit=60")
            async let t: [CurvaDeTamanhos.Faixa] = Supabase.shared.buscar(
                "curva_tamanhos",
                "select=*&termo_id=eq.\(termo.id)&sistema=eq.letra&rotulo=not.is.null&order=semana.desc&limit=60")
            serie = try await s
            indices = try await i.filter { $0.termoId == termo.id }
            coberturas = try await c
            let tamanhos = (try? await t) ?? []
            curvaDisponivel = CurvaDeTamanhos.consolidar(tamanhos)
                .reduce(0) { $0 + $1.nEmRisco } >= CurvaDeTamanhos.minimoEmRisco
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}
