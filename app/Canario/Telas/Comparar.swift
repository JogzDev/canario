import SwiftUI

/// Aba **Comparar** (§27).
///
/// ## Por que ela foi refeita em 31/07
///
/// O JP: "a seção que mais tem me intrigado até agora é a de comparar, pra que
/// exatamente ela serve? Acho que ela ficou meio aquém do resto do projeto."
///
/// Ele estava certo, e o defeito era de concepção, não de acabamento. A versão
/// anterior ordenava os termos escolhidos por um único número — o índice — e
/// chamava aquilo de ranking. Isso não ajuda ninguém a decidir nada: quem está
/// escolhendo entre floral e xadrez para o verão já sabe qual dos dois a
/// imprensa citou mais. **A pergunta que falta é outra:** o painel já está
/// cheio disso, ou ainda não?
///
/// Então a aba passa a comparar em dois eixos que vêm de pernas diferentes:
///
/// * **Presença no varejo** — quanto do sortimento do painel já tem o atributo,
///   em % e em número de peças. É descritivo e não leva z-score (decisão B1).
/// * **Movimento editorial** — para onde a imprensa está indo, com o índice e
///   o estado da §22.
///
/// O que interessa é a **distância entre os dois**. Um atributo que a imprensa
/// citou muito e que o painel quase não tem é uma coisa; um que está em toda
/// vitrine e sumiu do editorial é outra bem diferente. Nenhuma das duas é
/// recomendação: a tela mostra a distância e para aí, porque quem decide compra
/// tem custo, prazo de produção e histórico próprio que o app não conhece
/// (regra 1).
struct Comparar: View {
    @State private var termos: [Termo] = []
    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var varejo: [String: PontoSerie] = [:]
    @State private var coberturas: [String: Cobertura] = [:]
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
            .navigationTitle("Compare")
        }
        .task { await carregar() }
    }

    private var conteudo: some View {
        List {
            Section {
                Text("What this compares").font(Tokens.Fonte.secao)
                Text("Choose 2 to \(maximo) attributes that compete for the same space in a collection. The screen aligns panel presence with external interest signals in the same week.")
                    .font(Tokens.Fonte.apoio)
                Text("This compares already collected market data. It is not a sales forecast and does not include your costs, timing or history.")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }

            if escolhidos.count >= 2 {
                Section("Side by side") {
                    ForEach(comparados) { termo in
                        LinhaComparada(termo: termo,
                                       indice: indices[termo.id],
                                       varejo: varejo[termo.id],
                                       cobertura: coberturas[termo.id])
                    }
                }
                if let leitura = leituraDaDistancia {
                    Section("Where they diverge") {
                        Text(leitura).font(Tokens.Fonte.apoio)
                    }
                }
            } else {
                Section {
                    Text("Choose at least 2 attributes below.")
                        .font(Tokens.Fonte.apoio)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }

            ForEach(dimensoesComparaveis, id: \.self) { dimensao in
                Section(Traducao.rotuloDaDimensao(dimensao)) {
                    ForEach(termosComparaveis.filter {
                        $0.dimensao == dimensao
                    }) { termo in
                        Button {
                            alternar(termo.id)
                        } label: {
                            HStack {
                                Image(systemName: escolhidos.contains(termo.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(escolhidos.contains(termo.id)
                                                     ? Tokens.Cor.tinta : Tokens.Cor.semDado)
                                Text(Traducao.rotuloExibido(termo))
                                    .foregroundStyle(Tokens.Cor.tinta)
                                Spacer()
                                if indices[termo.id]?.indice == nil {
                                    Text("Panel data")
                                        .font(Tokens.Fonte.miudo)
                                        .foregroundStyle(Tokens.Cor.acao)
                                }
                            }
                        }
                        .disabled(!escolhidos.contains(termo.id)
                                  && escolhidos.count >= maximo)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Toda medição real de varejo entra no catálogo. O índice composto mantém
    /// seu portão rigoroso, mas sua ausência não apaga dados que existem.
    private var termosComparaveis: [Termo] {
        termos.filter { Elegibilidade.varejoComparavel(varejo[$0.id]) }
            .sorted { Traducao.rotuloExibido($0) < Traducao.rotuloExibido($1) }
    }

    private var dimensoesComparaveis: [String] {
        let ordem = ["categoria", "cor", "estampa", "tecido", "comprimento",
                     "silhueta", "cintura", "estetica"]
        let presentes = Set(termosComparaveis.map(\.dimensao))
        return ordem.filter(presentes.contains)
            + presentes.filter { !ordem.contains($0) }.sorted()
    }

    /// Ordena pela presença no varejo, que é o eixo com dado para todos. O
    /// índice editorial falta em parte dos termos, e ordenar por um campo vazio
    /// jogaria termos para o fim como se fossem os piores.
    private var comparados: [Termo] {
        termosComparaveis.filter { escolhidos.contains($0.id) }
            .sorted { (varejo[$0.id]?.valorBruto ?? -1) > (varejo[$1.id]?.valorBruto ?? -1) }
    }

    /// A frase que dá sentido à tabela: onde os dois eixos discordam.
    private var leituraDaDistancia: String? {
        let comOsDois = comparados.compactMap { t -> (Termo, Double, Double)? in
            let ponto = varejo[t.id]
            let indiceSemanal = indices[t.id]
            guard Elegibilidade.comparacao(
                    indice: indiceSemanal, varejo: ponto,
                    cobertura: coberturas[t.id]),
                  let share = ponto?.valorBruto,
                  let indice = indiceSemanal?.indice else { return nil }
            return (t, share, indice)
        }
        guard comOsDois.count >= 2 else { return nil }
        guard let maisEditorial = comOsDois.max(by: { $0.2 < $1.2 }),
              let maisVarejo = comOsDois.max(by: { $0.1 < $1.1 }) else { return nil }

        let pctE = Leitura.numero(maisEditorial.1, casas: 1)
        let pctV = Leitura.numero(maisVarejo.1, casas: 1)

        if maisEditorial.0.id == maisVarejo.0.id {
            return "\(Traducao.rotuloExibido(maisEditorial.0)) leads both axes: it moved most across external signals and is the most present in the panel (\(pctE)% of the assortment). When both move together, it reads as an established attribute rather than a new movement."
        }
        return "\(Traducao.rotuloExibido(maisEditorial.0)) moved most across external signals this week and occupies \(pctE)% of the panel assortment. \(Traducao.rotuloExibido(maisVarejo.0)) is most present in stores at \(pctV)%. The screen shows this gap between external attention and what brands already carry; what to do with it depends on your costs and timing."
    }

    private func alternar(_ id: String) {
        if escolhidos.contains(id) { escolhidos.remove(id) }
        else if escolhidos.count < maximo { escolhidos.insert(id) }
    }

    private func carregar() async {
        carregando = true
        erro = nil
        do {
            async let t = CatalogoDeTermos.shared.carregar()
            async let i = CatalogoDeIndices.shared.carregar()
            async let v: [PontoSerie] = Supabase.shared.buscar(
                "series_do_app", "select=*&segmento=eq.\(Recorte.segmento)&fonte=eq.varejo&order=semana.desc&limit=400")
            async let c: [Cobertura] = Supabase.shared.buscar(
                "cobertura_por_celula", "select=*&segmento=eq.\(Recorte.segmento)&order=semana.desc&limit=400")

            termos = try await t
            let dadosI = try await i
            let dadosV = try await v
            let dadosC = try await c
            guard let semana = Elegibilidade.semanaDeComparacao(
                    indices: dadosI, varejo: dadosV, coberturas: dadosC) else {
                indices = [:]
                varejo = [:]
                coberturas = [:]
                carregando = false
                return
            }

            var mapaI: [String: IndiceSemanal] = [:]
            for x in dadosI where x.semana == semana {
                let cobertura = dadosC.first {
                    $0.termoId == x.termoId && $0.semana == semana
                        && $0.segmento == Recorte.segmento
                }
                if Elegibilidade.indice(x, cobertura: cobertura), x.indice != nil {
                    mapaI[x.termoId] = x
                }
            }
            indices = mapaI

            var mapaV: [String: PontoSerie] = [:]
            for x in dadosV where x.semana == semana { mapaV[x.termoId] = x }
            varejo = mapaV

            // §8: todos os termos usam o mesmo recorte semanal. Ausência não
            // libera leitura; ela fica explícita na linha do atributo.
            var mapaC: [String: Cobertura] = [:]
            for x in dadosC where x.semana == semana { mapaC[x.termoId] = x }
            coberturas = mapaC
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}

/// Uma linha da comparação: os dois eixos, com unidade em cada um.
struct LinhaComparada: View {
    let termo: Termo
    let indice: IndiceSemanal?
    let varejo: PontoSerie?
    let cobertura: Cobertura?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack {
                Text(Traducao.rotuloExibido(termo)).font(Tokens.Fonte.corpo)
                Spacer()
                if indice?.indice != nil {
                    SeloEstado(estado: indice?.estado, leitura: indice?.indice)
                } else {
                    Label("Panel data", systemImage: "building.2")
                        .font(Tokens.Fonte.miudo.weight(.semibold))
                        .foregroundStyle(Tokens.Cor.acao)
                }
            }

            HStack(alignment: .top, spacing: Tokens.Espaco.g) {
                eixo(titulo: "In the panel",
                     valor: varejo?.valorBruto.map {
                         Leitura.numero($0, casas: 1) + "%"
                     } ?? "—",
                     detalhe: varejo?.nAmostra.map { "\($0) items" } ?? "—")
                eixo(titulo: "External signal",
                     valor: Explicacao.numeroComUnidade(indice?.indice),
                     detalhe: indice?.indice == nil ? "—" : "statistical scale")
            }
            LinhaInsumo(texto: "Panel: \(Explicacao.unidade(daFonte: "varejo")).")
            if let pernas = indice?.pernasAtivas, !pernas.isEmpty {
                LinhaInsumo(texto: "External signal \(Perna.frase(pernas)).")
            }
            if indice?.indice == nil {
                LinhaInsumo(texto: cobertura.map {
                    "The panel measurement exists. The combined external signal is withheld: \($0.oQueFalta)."
                } ?? "The panel measurement exists. No qualified combined external signal is available for this week.")
            }
            if let semana = varejo?.semana ?? indice?.semana {
                LinhaInsumo(texto: "Week of \(Formato.data(semana)).")
            }
        }
        .padding(.vertical, Tokens.Espaco.xs)
    }

    private func eixo(titulo: String, valor: String, detalhe: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo)
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            Text(valor).font(Tokens.Fonte.numero)
            Text(detalhe)
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
