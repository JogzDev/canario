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

    /// Constante: esta tela só existe dentro do mercado, e ler o ambiente aqui
    /// devolveria o valor do pai. Mesmo caso do `Explorar` e do `Comparar`.
    private let territorio: Territorio = .mercado

    @State private var serie: [PontoSerie] = []
    @State private var indices: [IndiceSemanal] = []
    @State private var coberturas: [Cobertura] = []
    @State private var carregando = true
    @State private var erro: String?
    @State private var janelaEmMeses = 6
    /// O cartão de explicação da escala, que abre no (i) ao lado do número.
    @State private var explicandoAEscala = false
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
                    cabecalho
                    grafico
                    curva
                    insumos
                } else {
                    cabecalho
                    grafico
                    curva
                    insumos
                }
            }
            .padding(Tokens.Espaco.m)
        }
        // O nome do termo é a manchete DA TELA no desenho da Bianca, em corpo
        // grande logo abaixo do voltar. Repeti-lo na barra seria dizer duas
        // vezes a mesma palavra a dois dedos de distância.
        // Declarado AQUI, e não só em quem empurra.
        //
        // O padrão era o local de push declarar o território, e ele vazava a
        // cada tela nova: o `Explorar` declarava ao abrir esta, esta não
        // declarava ao abrir o detalhe da fonte, e o detalhe abria preto. O
        // JP achou por baixo: *"quando eu clico em qualquer uma das paginas de
        // sources, eu vou pra uma pagina que nao segue o azul escuro nativo da
        // paleta do app, ela é preta"*. Tela que só existe no mercado diz isso
        // de si mesma; assim ninguém precisa lembrar de dizer por ela.
        .territorio(.mercado)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navegacaoDoMercado()
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
            // Divisor e linha, não cartão: no desenho da Bianca esta é uma
            // PORTA entre dois blocos de conteúdo, e cartão a fazia parecer
            // mais um bloco. O que ela leva continua sendo dito -- só que na
            // tela de destino, que é onde a pessoa vai lê-lo.
            VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                Divider().overlay(Tokens.Cor.bordaDo(territorio))
                NavigationLink {
                    CurvaDeTamanhosView(termo: termo)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Size availability")
                            .font(.system(size: 22, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Tokens.Fonte.secao)
                            .foregroundStyle(Tokens.Cor.acentoDo(territorio))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                LinhaInsumo(texto: frase("Where size availability breaks among panel items with \(Traducao.rotuloExibido(termo).lowercased()). Retail context only; it does not affect the index or state."))
                Divider().overlay(Tokens.Cor.bordaDo(territorio))
            }
        }
    }

    /// A manchete da tela: nome, número, selo e a leitura da semana.
    ///
    /// **Junta o que eram dois cartões.** A tela abria com um parágrafo e, logo
    /// abaixo, um cartão com o selo e o número repetindo o mesmo. Pior: o
    /// parágrafo dizia *"Skirt was within the usual range and slightly under
    /// the usual range"* -- as duas leituras coladas por um "and", que é a
    /// mesma contradição que o JP mandou tirar dos cartões da Trends. O selo é
    /// a faixa desta semana; o `estado` é movimento confirmado; e a manchete que
    /// concilia os dois já existe, em `Explicacao.porQue`.
    ///
    /// O número fica no tom da tinta, não no vermelho do desenho: em uma
    /// leitura "far above" ele sairia verde, e o JP já vetou número verde no
    /// painel da peça. Quem carrega a direção é o selo, que é medido.
    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(Traducao.rotuloExibido(termo))
                    .font(.system(size: 40, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                Spacer(minLength: Tokens.Espaco.s)
                if temCobertura, let z = atual?.indice {
                    Button {
                        explicandoAEscala.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(Tokens.Fonte.apoio)
                            .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Explicacao.tituloDaEscala)
                    Text(fmt(z))
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(Tokens.Cor.tintaDo(territorio))
                }
            }

            if temCobertura {
                SeloEstado(estado: atual?.estado, leitura: atual?.indice)
            }

            if explicandoAEscala {
                cartaoDaEscala
            }

            Text(manchete).font(Tokens.Fonte.apoio)
            LinhaInsumo(texto: Perna.baseadoEm(atual?.pernasAtivas))
        }
    }

    /// O "How is this number calculated?" do desenho, com texto de verdade.
    ///
    /// A Bianca deixou um lugar reservado -- *"put here explanation of how this
    /// index number is calculated"* --, e o texto já existia: é o mesmo que
    /// responde ao "1,15 o quê? Paçoquitas?" no painel da peça. Um texto só
    /// para a mesma pergunta em duas telas.
    private var cartaoDaEscala: some View {
        Cartao {
            HStack(alignment: .firstTextBaseline) {
                Text(Explicacao.tituloDaEscala).font(Tokens.Fonte.secao)
                Spacer()
                Button {
                    explicandoAEscala = false
                } label: {
                    Image(systemName: "xmark")
                        .font(Tokens.Fonte.miudo.weight(.semibold))
                        .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close explanation")
            }
            Text(Explicacao.textoDaEscala)
                .font(Tokens.Fonte.apoio)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A manchete da semana, sem repetir o que o selo já disse.
    ///
    /// Ela dizia *"was within the usual range **and** slightly under the usual
    /// range"* -- estado e faixa colados por um "and", como se fossem uma
    /// afirmação só. São duas perguntas, e `Explicacao.porQue` é quem responde
    /// a segunda sem contradizer a primeira; é a mesma manchete dos cartões da
    /// Trends, então as duas telas passam a falar igual.
    /// Renomeada de `frase` em 05/09: o nome sombreava a função global
    /// `frase(_:)` dentro de toda esta View, e nenhuma chamada de tradução
    /// aqui dentro alcançava a função certa.
    private var manchete: String {
        // O PORTÃO DA §8 VALE PARA A PROSA TAMBÉM.
        //
        // A tela escondia o número grande e o selo quando a cobertura não
        // sustenta, e logo abaixo a manchete dizia "The index is +2,14" -- eu
        // mesmo abri esse buraco ao trazer a manchete para o cabeçalho, que antes
        // só era montado do lado liberado. Recusar o número em corpo 34 e
        // sussurrá-lo em corpo 15 não é recusar.
        guard temCobertura else {
            return frase("The panel does not have enough coverage this week to state an index for \(Traducao.rotuloExibido(termo)). What each source measured on its own is below.")
        }
        guard let atual, let valor = atual.indice else {
            return frase("There is no index for \(Traducao.rotuloExibido(termo)) in this panel cut yet.")
        }
        let quando = atual.semana == maisRecente?.semana
            ? frase("Latest reading, \(Formato.data(atual.semana)).")
            : frase("Latest week when two sources overlapped, \(Formato.data(atual.semana)).")
        guard atual.estado != nil else {
            return frase("\(quando) The index is \(fmt(valor)), but a state requires two agreeing sources.")
        }
        return "\(quando) " + Explicacao.porQue(estado: atual.estado,
                                                indice: atual, series: serie)
    }

    /// §29.3 — índice, estado e as pernas ativas declaradas.
    private var indiceEEstado: some View {
        Cartao {
            // O selo é o título da leitura. Repeti-lo em preto ao lado fazia a
            // mesma manchete competir consigo mesma e ainda a espremia em duas linhas.
            SeloEstado(estado: atual?.estado,
                       leitura: temCobertura ? atual?.indice : nil)
            Text(atual?.indice.map(fmt) ?? "—")
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            if let z = atual?.indice {
                LinhaInsumo(texto: Leitura.explicacao(z))
            }
            LinhaInsumo(texto: Perna.baseadoEm(atual?.pernasAtivas))
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
                // O gráfico usa a MESMA cor de perna dos cartões de Sources.
                //
                // Com a escala padrão do Charts ele saía em azul, verde e
                // laranja de sistema -- e logo abaixo os mesmos quatro nomes
                // apareciam em âmbar, rosa, azul e verde-água. Duas paletas
                // para as mesmas quatro coisas na mesma tela: a legenda e os
                // cartões deixavam de se ensinar um ao outro. E o verde de
                // sistema ainda colidia com o verde dos selos de faixa.
                .chartForegroundStyleScale(
                    domain: escalaDeCor.map(\.0),
                    range: escalaDeCor.map(\.1))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Weekly history by source")
                LinhaInsumo(texto: frase("To keep lines comparable, the chart shows only weeks measured by every displayed source. Each source's latest date remains listed below."))
            }
        }
    }

    /// Rótulo -> cor, na ordem em que as pernas aparecem nos cartões, para a
    /// legenda do gráfico e a grade de Sources contarem a mesma história.
    private var escalaDeCor: [(String, Color)] {
        porFonte.map { fonte, _ in
            (Perna.rotulo(fonte),
             Tokens.Cor.corDaPerna(fonte)?.tinta ?? Tokens.Cor.acentoDo(territorio))
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

    /// §29.4 — um bloco por fator, com fonte e data. Agora em grade de dois.
    private var insumos: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sources").font(.system(size: 22, weight: .bold))
                BotaoDeAjuda(titulo: frase("What these percentages are"),
                             texto: Self.textoDasFontes,
                             rotulo: frase("What these percentages are"))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Tokens.Espaco.s),
                                GridItem(.flexible(), spacing: Tokens.Espaco.s)],
                      spacing: Tokens.Espaco.s) {
                ForEach(porFonte, id: \.0) { fonte, pontos in
                    NavigationLink {
                        DetalheDaFonteEditorial(termo: termo, fonte: fonte, pontos: pontos)
                    } label: {
                        CartaoDaPerna(fonte: fonte,
                                      variacao: variacaoDaFonte(fonte, pontos: pontos),
                                      leitura: resumoDaFonte(fonte, pontos: pontos),
                                      semanas: pontos.count,
                                      ultima: pontos.first?.semana)
                        // Numa `LazyVGrid` a linha toma a altura do item mais
                        // alto, e o mais baixo fica boiando com uma sobra
                        // embaixo. "Search" cabe numa linha e "Brazilian
                        // Editorial" em duas; "6 weeks" cabe e "235 weeks"
                        // quebra. O resultado eram quatro caixas de alturas
                        // diferentes -- o desalinhamento que o JP viu.
                        .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A unidade das quatro porcentagens, num lugar só.
    ///
    /// No desenho os cartões trazem "-40%" e nada mais, e a §3 não deixa: um
    /// número sem a régua não é auditável. Repetir a régua quatro vezes também
    /// não serve -- viraria a textura que o JP mandou tirar dos cartões da
    /// Trends. Então ela mora no "?" ao lado do título, uma vez.
    static var textoDasFontes: String {
        frase("Each card compares this source's latest measured week with its own average over the previous 12 weeks — the same window the index uses. It is the movement of that one source, not the combined index.\n\nA source with no comparable window yet says so instead of showing a number. Tap a card for the weekly history behind it.")
    }

    /// A variação em pontos percentuais, para a seta e o sinal.
    private func variacaoDaFonte(_ fonte: String, pontos: [PontoSerie]) -> Double? {
        guard let recente = pontos.first?.valorBruto,
              let media = mediaDaJanela(pontos), media > 0 else { return nil }
        return 100.0 * (recente - media) / media
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

    private func resumoDaFonte(_ fonte: String, pontos: [PontoSerie]) -> String {
        if fonte.hasPrefix("editorial"), pontos.first?.nAmostra == 0 {
            let anteriores = pontos.dropFirst().prefix(12).compactMap(\.nAmostra)
            let media = anteriores.isEmpty ? nil
                : Double(anteriores.reduce(0, +)) / Double(anteriores.count)
            if let media {
                return frase("0 articles in the latest 4-week window · previous-window average \(Leitura.numero(media, casas: 1))")
            }
            return frase("0 articles in the latest 4-week window")
        }
        return Leitura.variacao(recente: pontos.first?.valorBruto,
                                media: mediaDaJanela(pontos))
            ?? frase("No comparable window yet")
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
                "curva_tamanhos", CurvaDeTamanhos.consulta(termoId: termo.id, porRotulo: true))
            serie = try await s
            indices = try await i.filter { $0.termoId == termo.id }
            coberturas = try await c
            let tamanhos = (try? await t) ?? []
            let semanaDosTamanhos = tamanhos.map(\.semana).max()
            curvaDisponivel = CurvaDeTamanhos.consolidar(
                tamanhos.filter { $0.semana == semanaDosTamanhos })
                .reduce(0) { $0 + $1.nEmRisco } >= CurvaDeTamanhos.minimoEmRisco
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}

private struct DetalheDaFonteEditorial: View {
    let termo: Termo
    let fonte: String
    let pontos: [PontoSerie]

    private let territorio: Territorio = .mercado

    /// Só a janela recente entra no gráfico.
    ///
    /// `pontos` traz a série inteira -- 235 semanas na busca, 236 no editorial
    /// brasileiro. Desenhar tudo num cartão de 210 pt com um `PointMark` por
    /// semana produzia uma faixa sólida de marcas, sem eixo e sem leitura
    /// possível: *"os graficos dentro delas estão bem confusos"*. Um ano é o
    /// que dá para ler numa tela de telefone, e é a janela que responde à
    /// pergunta que traz a pessoa aqui -- como esta fonte se moveu.
    private static let semanasNoGrafico = 52

    private var ordenados: [PontoSerie] {
        pontos.sorted { $0.semana < $1.semana }.suffix(Self.semanasNoGrafico)
    }
    private var recente: PontoSerie? { pontos.max { $0.semana < $1.semana } }
    private var corDaFonte: Color {
        Tokens.Cor.corDaPerna(fonte)?.tinta ?? Tokens.Cor.acentoDo(territorio)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                Cartao {
                    Text(Perna.rotulo(fonte).capitalized).font(Tokens.Fonte.secao)
                    if fonte.hasPrefix("editorial") {
                        Text("\(recente?.nAmostra ?? 0) articles in the latest 4-week window")
                            .font(Tokens.Fonte.corpo)
                    } else if let bruto = recente?.valorBruto {
                        Text(Leitura.numero(bruto, casas: 2)).font(Tokens.Fonte.corpo)
                    }
                    LinhaInsumo(texto: frase("Latest measurement: \(Formato.data(recente?.semana ?? "—"))"))
                    // A unidade sai da TABELA do app, não do `meta` do banco.
                    //
                    // `meta.unidade` vem gravado em português -- "materias que
                    // citaram o termo" -- e estava aparecendo cru numa
                    // interface inteira em inglês. `Explicacao.unidade` já
                    // traduz as cinco pernas e é a mesma que o painel da peça
                    // usa; o `meta` fica como estava no banco, que é onde ele
                    // serve de registro.
                    LinhaInsumo(texto: Explicacao.unidade(daFonte: fonte).capitalizedPrimeira)
                }

                if !ordenados.compactMap(\.valorBruto).isEmpty {
                    Cartao {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Measured history").font(Tokens.Fonte.secao)
                            Spacer()
                            Text(janelaDoGrafico)
                                .font(Tokens.Fonte.miudo)
                                .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                        }
                        Chart(ordenados) { ponto in
                            if let valor = ponto.valorBruto,
                               let data = Formato.dataISO(ponto.semana) {
                                // O `PointMark` saiu: com uma marca por semana
                                // o gráfico virava uma faixa cheia. A linha
                                // sozinha mostra o movimento, que é o assunto.
                                LineMark(x: .value("Week", data),
                                         y: .value(frase("Measured value"), valor))
                                .interpolationMethod(.monotone)
                            }
                        }
                        .foregroundStyle(corDaFonte)
                        .chartYAxis {
                            AxisMarks(position: .trailing) {
                                AxisGridLine().foregroundStyle(.quaternary)
                                AxisValueLabel()
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisGridLine().foregroundStyle(.quaternary)
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .frame(height: 180)
                        LinhaInsumo(texto: frase("Vertical axis: \(Explicacao.unidade(daFonte: fonte))."))
                        LinhaInsumo(texto: fonte.hasPrefix("editorial")
                            ? frase("This is the source's measured value, not a forecast. Article evidence appears below.")
                            : frase("This is the source's measured value, not a forecast. Its inputs and sample appear below."))
                    }
                }

                evidenciaDaFonte
            }
            .padding(Tokens.Espaco.m)
        }
        .territorio(.mercado)
        .navigationTitle(Traducao.rotuloExibido(termo))
        .navigationBarTitleDisplayMode(.inline)
        .navegacaoDoMercado()
    }

    /// "52 weeks" ou o que houver, para o eixo não mentir sobre o alcance.
    private var janelaDoGrafico: String {
        let n = ordenados.count
        return n < Self.semanasNoGrafico
            ? frase("\(String(n)) weeks measured") : frase("last \(String(n)) weeks")
    }

    @ViewBuilder
    private var evidenciaDaFonte: some View {
        Cartao {
            Text("How this was measured").font(Tokens.Fonte.secao)
            switch fonte {
            case "busca":
                Text("Google search interest")
                    .font(Tokens.Fonte.apoio)
                if let valor = recente?.valorBruto {
                    LinhaInsumo(texto: frase("Latest closed week: \(Leitura.numero(valor, casas: 0)) out of 100 for this monitored search set."))
                }
                let consultas = Array(termo.termosDeBusca.prefix(5))
                LinhaInsumo(texto: frase("Monitored expressions: \(consultas.joined(separator: " · "))."))
            case "varejo":
                Text("Observed panel assortment")
                    .font(Tokens.Fonte.apoio)
                let itens = recente?.nAmostra.map(String.init) ?? "—"
                let total = recente?.meta?.nTotalSortimento.map {
                    Leitura.numero($0, casas: 0)
                } ?? "—"
                LinhaInsumo(texto: frase("\(itens) matching items among \(total) currently observed panel offers."))
                if let valor = recente?.valorBruto {
                    LinhaInsumo(texto: frase("Measured share: \(Leitura.numero(valor, casas: 2))%."))
                }
            default:
                let meta = recente?.meta
                if let veiculos = meta?.veiculosEmTexto {
                    LinhaInsumo(texto: veiculos)
                }
                // O link não parecia link.
                //
                // `Link` envolvendo uma `VStack` não tinge o que está dentro:
                // os textos saíam na cor de leitura, sem nada dizendo que
                // abriam a matéria. O JP pediu o remédio junto do diagnóstico
                // -- *"podem estar melhor expostos, por exemplo usando o tom
                // de azul claro nativo do app"* --, e o azul claro é o acento
                // do mercado. A seta de "sai do app" vai junto, porque cor
                // sozinha não é affordance (§32).
                ForEach(Array((meta?.exemplos ?? []).enumerated()), id: \.offset) { _, exemplo in
                    if let texto = exemplo.url, let url = URL(string: texto) {
                        Link(destination: url) {
                            HStack(alignment: .firstTextBaseline,
                                   spacing: Tokens.Espaco.xs) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exemplo.titulo)
                                        .font(Tokens.Fonte.apoio.weight(.medium))
                                        .foregroundStyle(Tokens.Cor.acentoDo(territorio))
                                        .multilineTextAlignment(.leading)
                                    Text(exemplo.veiculo)
                                        .font(Tokens.Fonte.miudo)
                                        .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(Tokens.Fonte.miudo.weight(.semibold))
                                    .foregroundStyle(Tokens.Cor.acentoDo(territorio))
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(frase("\(exemplo.titulo), \(exemplo.veiculo), opens the article"))
                        .padding(.vertical, Tokens.Espaco.xs)
                    }
                }
                if (meta?.exemplos ?? []).isEmpty {
                    let n = recente?.nAmostra ?? 0
                    LinhaInsumo(texto: n == 0
                        ? frase("No qualifying fashion article matched this attribute in the latest 4-week window.")
                        : (n == 1
                            ? frase("1 qualifying article formed this 4-week reading; the evidence list is being refreshed.")
                            : frase("\(String(n)) qualifying articles formed this 4-week reading; the evidence list is being refreshed.")))
                }
            }
        }
    }
}

/// Um cartão de perna: quem mediu, quanto mudou, e desde quando.
///
/// **A cor diz QUEM, a seta diz PARA ONDE.** É a regra que faz os quatro tons
/// da Bianca não brigarem com os sete selos de faixa que o app já usa -- se um
/// cartão de fonte fosse verde, ele leria como "acima da faixa" antes de ler
/// como "editorial". Ver `Tokens.Cor.corDaPerna`.
///
/// Perna sem tom -- uma que apareça depois e ninguém tenha desenhado -- cai na
/// superfície de sempre em vez de receber uma cor inventada na hora.
struct CartaoDaPerna: View {
    let fonte: String
    let variacao: Double?
    let leitura: String
    let semanas: Int
    let ultima: String?
    @Environment(\.territorio) private var territorio

    private var cores: (fundo: Color, tinta: Color) {
        Tokens.Cor.corDaPerna(fonte)
            ?? (Tokens.Cor.superficieDo(territorio), Tokens.Cor.tintaDo(territorio))
    }

    private var icone: String {
        switch fonte {
        case "busca": return "magnifyingglass"
        case "editorial_br": return "pencil"
        case "editorial_intl": return "globe"
        case "varejo": return "storefront"
        default: return "circle.dashed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .top, spacing: Tokens.Espaco.xs) {
                Image(systemName: icone)
                    .font(Tokens.Fonte.secao)
                    .foregroundStyle(cores.tinta)
                // `reservesSpace` em vez de `lineLimit` puro: "Search" ocupa
                // uma linha e "Brazilian Editorial" duas, e sem reservar a
                // segunda os dois cartões nascem com alturas diferentes antes
                // mesmo de a grade tentar alinhá-los.
                Text(Perna.rotulo(fonte).capitalized)
                    .font(Tokens.Fonte.apoio.weight(.semibold))
                    .foregroundStyle(Tokens.Cor.tintaDo(territorio))
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if let variacao {
                // §32: a direção não é comunicada só por cor. A seta e o sinal
                // do número dizem a mesma coisa, e sobrevivem em preto e branco.
                HStack(spacing: Tokens.Espaco.xs) {
                    Image(systemName: variacao >= 0 ? "arrow.up" : "arrow.down")
                        .font(Tokens.Fonte.numero)
                    Text("\(Leitura.numero(variacao, casas: 0, sinal: true))%")
                        .font(Tokens.Fonte.numero)
                }
                .foregroundStyle(cores.tinta)
            } else {
                // Perna sem janela comparável mostra a manchete no lugar do
                // número, e a manchete é mais alta. Duas linhas reservadas nas
                // duas pontas mantêm o passo do cartão.
                Text(leitura)
                    .font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let ultima {
                // Duas linhas declaradas, não uma que às vezes quebra: com
                // "235 weeks · to 17/08/2026" quebrando e "6 weeks · to
                // 24/08/2026" cabendo, os cartões vizinhos saíam com um passo
                // de diferença.
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(semanas) weeks")
                    Text(frase("to \(Formato.data(ultima))"))
                }
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Espaco.m)
        .background(cores.fundo)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.cartao, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rotuloFalado)
    }

    private var rotuloFalado: String {
        let numero = variacao.map {
            frase("\(Leitura.numero($0, casas: 0, sinal: true)) percent versus its own 12-week average")
        } ?? leitura
        return frase("\(Perna.rotulo(fonte)), \(numero)")
    }
}
