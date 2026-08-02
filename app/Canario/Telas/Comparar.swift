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
            .navigationTitle("Comparar")
        }
        .task { await carregar() }
    }

    private var conteudo: some View {
        List {
            Section {
                Text("Para que serve").font(Tokens.Fonte.secao)
                Text("Escolha de 2 a \(maximo) atributos que disputam o mesmo espaço na coleção. Mostro quanto do painel já tem cada um e o que a imprensa fez com eles na mesma semana.")
                    .font(Tokens.Fonte.apoio)
                Text("A comparação é entre os atributos que você escolheu, sobre dados já coletados. Não é previsão de venda, e não considera seu custo, seu prazo nem seu histórico.")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }

            if escolhidos.count >= 2 {
                Section("Lado a lado") {
                    ForEach(comparados) { termo in
                        LinhaComparada(termo: termo,
                                       indice: indices[termo.id],
                                       varejo: varejo[termo.id],
                                       cobertura: coberturas[termo.id])
                    }
                }
                if let leitura = leituraDaDistancia {
                    Section("Onde eles se separam") {
                        Text(leitura).font(Tokens.Fonte.apoio)
                    }
                }
            } else {
                Section {
                    Text("Escolha pelo menos 2 atributos abaixo.")
                        .font(Tokens.Fonte.apoio)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }

            Section(escolhidos.count >= 2 ? "Trocar seleção" : "Atributos") {
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

    /// Ordena pela presença no varejo, que é o eixo com dado para todos. O
    /// índice editorial falta em parte dos termos, e ordenar por um campo vazio
    /// jogaria termos para o fim como se fossem os piores.
    private var comparados: [Termo] {
        termos.filter { escolhidos.contains($0.id) }
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
        guard comOsDois.count >= 2 else {
            return "Ainda não dá para ler a distância: nem todos os escolhidos têm as duas pernas nesta semana."
        }
        guard let maisEditorial = comOsDois.max(by: { $0.2 < $1.2 }),
              let maisVarejo = comOsDois.max(by: { $0.1 < $1.1 }) else { return nil }

        let pctE = Leitura.numero(maisEditorial.1, casas: 1)
        let pctV = Leitura.numero(maisVarejo.1, casas: 1)

        if maisEditorial.0.id == maisVarejo.0.id {
            return "\(maisEditorial.0.rotulo) lidera nos dois eixos: é o mais citado pela imprensa e o mais presente no painel (\(pctE)% do sortimento). Quando os dois andam juntos, a leitura é de atributo já estabelecido, não de movimento novo."
        }
        return "\(maisEditorial.0.rotulo) é o que a imprensa mais moveu nesta semana, e ocupa \(pctE)% do sortimento do painel. \(maisVarejo.0.rotulo) é o mais presente nas vitrines, com \(pctV)%. Essa distância entre o que a imprensa cita e o que as marcas já penduraram é o que esta tela existe para mostrar — o que fazer com ela depende do seu custo e do seu prazo, que eu não conheço."
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
                "termos", "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca,palavras_pt,palavras_en&order=dimensao,id")
            async let i: [IndiceSemanal] = Supabase.shared.buscar(
                "indices_semanais", "select=*&segmento=eq.\(Recorte.segmento)&order=semana.desc&limit=400")
            async let v: [PontoSerie] = Supabase.shared.buscar(
                "series_semanais", "select=*&segmento=eq.\(Recorte.segmento)&fonte=eq.varejo&order=semana.desc&limit=400")
            async let c: [Cobertura] = Supabase.shared.buscar(
                "cobertura_por_celula", "select=*&segmento=eq.\(Recorte.segmento)&order=semana.desc&limit=400")

            let dadosI = try await i
            let dadosV = try await v
            let dadosC = try await c
            guard let semana = Elegibilidade.semanaComum(
                    indices: dadosI, varejo: dadosV, coberturas: dadosC) else {
                indices = [:]
                varejo = [:]
                coberturas = [:]
                carregando = false
                return
            }

            var mapaI: [String: IndiceSemanal] = [:]
            for x in dadosI where x.semana == semana { mapaI[x.termoId] = x }
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
        let podeMostrar = Elegibilidade.comparacao(
            indice: indice, varejo: varejo, cobertura: cobertura)
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack {
                Text(termo.rotulo).font(Tokens.Fonte.corpo)
                Spacer()
                SeloEstado(estado: podeMostrar ? indice?.estado : nil,
                           motivo: podeMostrar
                               ? "Menos de duas pernas nesta semana."
                               : "Sem cobertura suficiente da mesma semana.")
            }

            if cobertura == nil {
                LinhaInsumo(texto: "Não há medição de cobertura para este atributo nesta semana.")
            } else if !podeMostrar {
                // §8: sem cobertura, nem índice nem share.
                LinhaInsumo(texto: "Cobertura insuficiente ou fora do mesmo recorte: \(cobertura?.oQueFalta ?? "sem medição").")
            } else {
                HStack(alignment: .top, spacing: Tokens.Espaco.g) {
                    eixo(titulo: "No painel",
                         valor: varejo?.valorBruto.map {
                             Leitura.numero($0, casas: 1) + "%"
                         } ?? "—",
                         detalhe: varejo?.nAmostra.map { "\($0) peças" } ?? "sem dado")
                    eixo(titulo: "No editorial",
                         valor: Explicacao.numeroComUnidade(indice?.indice),
                         detalhe: indice?.indice.map { Leitura.emPalavras($0) } ?? "sem índice")
                }
                LinhaInsumo(texto: "No painel: \(Explicacao.unidade(daFonte: "varejo")). No editorial: \(Explicacao.unidadeDoIndice).")
            }
            if let semana = varejo?.semana ?? indice?.semana {
                LinhaInsumo(texto: "Semana de \(Formato.data(semana)).")
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
