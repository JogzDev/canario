import SwiftUI

/// Aba **Explorar** (§27): valor de esforço zero na abertura.
///
/// ## O que mudou em 31/07, e por quê
///
/// O JP abriu a aba e listou quatro problemas. Todos viraram desenho aqui:
///
/// 1. **"É muito feio mostrar coisa do dia anterior."** Era, e a causa não era
///    de tela: `computar_eventos()` existia no banco e não estava no motor, então
///    a tabela de eventos congelou em 30/07 enquanto a coleta seguia rodando.
///    Corrigido no `motor_computar.py`. A tela agora **carimba a data do dado**
///    em vez de deixar o usuário descobrir sozinho.
/// 2. **"Agrupar por marca, senão fica muito poluído."** Vinte cartões soltos
///    viravam uma parede. Agora é uma linha por marca, com o total, e a lista
///    abre no toque.
/// 3. **"Pode ter algo tipo *3ª reposição dos tamanhos PP/P em menos de 2
///    meses."** É o sinal mais forte do painel e estava invisível: a view passou
///    a contar o ordinal por produto.
/// 4. **"Esses textos repetidos não me cativam."** Estavam repetidos porque
///    todo cartão dizia a mesma frase de perna. Agora cada um traz o número com
///    unidade, a regra que produziu o estado e o nome de quem publicou.
struct Explorar: View {
    @State private var todos: [IndiceSemanal] = []
    @State private var rotulos: [String: String] = [:]
    @State private var series: [String: [PontoSerie]] = [:]
    @State private var eventos: [EventoVarejo] = []
    @State private var inicioDaColeta = "2026-07-24"
    @State private var carregando = true
    @State private var erro: String?

    /// Um termo por linha, com a mudança MAIS RECENTE dele.
    ///
    /// Sem isto o mesmo termo aparecia várias vezes — "Casaco e jaqueta" saía
    /// duas vezes, nas semanas 13/07 e 06/07. Digest é resumo do que mudou, não
    /// histórico: repetir o termo gasta a atenção do usuário sem informar.
    private var mudaram: [IndiceSemanal] {
        var vistos = Set<String>()
        return todos.filter { vistos.insert($0.termoId).inserted }
    }

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
                curvaDoPainel
                movimento(titulo: "Reposições", tipo: "reposicao",
                          vazio: "Nenhuma reposição confirmada nesta janela. Ela exige ver um tamanho sair e voltar, e depois continuar disponível.")
                movimento(titulo: "Remarcações", tipo: "remarcacao",
                          vazio: "Nenhuma queda de preço de 5% ou mais nesta janela.")
                digest
                pendentes
            }
            .padding(Tokens.Espaco.m)
        }
    }

    // MARK: Movimento das marcas

    /// Uma linha por marca, com o total; a lista de peças abre no toque.
    private func movimento(titulo: String, tipo: String, vazio: String) -> some View {
        let doTipo = eventos.filter { $0.tipo == tipo }
        let porMarca = Dictionary(grouping: doTipo, by: \.marca)
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
        let maisRecente = doTipo.map(\.data).max()

        return VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(titulo).font(Tokens.Fonte.secao)
                Spacer()
                if let maisRecente {
                    // O carimbo que faltava: o usuário vê a data do dado sem
                    // precisar deduzi-la de um cartão.
                    Text(carimbo(maisRecente))
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }
            if porMarca.isEmpty {
                CoberturaInsuficiente(titulo: "Sem registro nesta janela",
                                      explicacao: vazio, oQueTem: nil)
            } else {
                ForEach(porMarca, id: \.key) { marca, lista in
                    NavigationLink {
                        ListaDeEventos(marca: marca, titulo: titulo, eventos: lista,
                                       inicioDaColeta: inicioDaColeta)
                    } label: {
                        LinhaDeMarca(marca: marca, eventos: lista)
                    }
                    .buttonStyle(.plain)
                }
                if tipo == "reposicao" {
                    LinhaInsumo(texto: "A reposição só entra depois de confirmada numa segunda visita: um tamanho que volta por um dia pode ser correção de catálogo, não decisão de compra. Por isso a mais recente costuma ser a de ontem.")
                }
            }
        }
    }

    /// §24 na abertura da aba: é o bloco de maior valor por esforço zero, e o
    /// único que responde a uma pergunta que o comprador já tem na cabeça antes
    /// de abrir o app.
    private var curvaDoPainel: some View {
        NavigationLink {
            CurvaDeTamanhosView(termo: nil)
        } label: {
            Cartao {
                HStack(alignment: .firstTextBaseline) {
                    Text("Curva de tamanhos").font(Tokens.Fonte.secao)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
                Text("Onde a grade do painel está quebrando ao longo da escada de tamanhos.")
                    .font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }
        }
        .buttonStyle(.plain)
    }

    /// A data do dado, sempre explícita.
    ///
    /// A §6 barra as frases de cultivo do tipo "está fresquinho", e com razão:
    /// além de serem linguagem de engajamento, elas somem justamente no dia em
    /// que o usuário mais precisa saber se o número envelheceu. A data resolve
    /// as duas coisas de uma vez.
    private func carimbo(_ data: String) -> String {
        "ocorrência mais recente: \(Formato.data(data))"
    }

    // MARK: O que mudou

    private var digest: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            Text("O que mudou").font(Tokens.Fonte.secao)
            if mudaram.isEmpty {
                CoberturaInsuficiente(
                    titulo: "Nenhum termo mudou de estado",
                    explicacao: "Nas últimas semanas nada se moveu o suficiente para eu chamar de mudança.",
                    oQueTem: "Isso é resultado, não ausência de dado: os limiares existem justamente para uma semana isolada não virar notícia.")
            } else {
                ForEach(mudaram) { i in
                    NavigationLink {
                        if let termo = termoDe(i) { RelatorioDoTermo(termo: termo) }
                    } label: {
                        CartaoDeMudanca(indice: i,
                                        rotulo: rotulos[i.termoId] ?? i.termoId,
                                        series: series[i.termoId] ?? [])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func termoDe(_ i: IndiceSemanal) -> Termo? {
        guard let rotulo = rotulos[i.termoId] else { return nil }
        return Termo(id: i.termoId, rotulo: rotulo, dimensao: "", exclusiva: false,
                     sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    /// Os blocos que a §27 pede e que ainda não têm dado. Declarados, não ocultos.
    private var pendentes: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.m) {
            Text("Ainda sem cobertura").font(Tokens.Fonte.secao)
            CoberturaInsuficiente(
                titulo: "Peças novas por combinação",
                explicacao: "Depende do primeiro avistamento por produto ao longo de várias semanas.",
                oQueTem: "O histórico necessário se acumula sozinho a cada noite de coleta.")
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
                "termos", "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca,palavras_pt,palavras_en")
            // UMA CONSULTA POR TIPO, de propósito.
            //
            // Com uma só, ordenada por data, o bloco de reposições aparecia
            // vazio mesmo havendo 217 no banco: em 31/07 houve 681 remarcações,
            // e as primeiras 400 linhas da página eram todas remarcação. A
            // reposição de ontem nunca entrava no resultado — e reposição é o
            // sinal mais forte do painel (§23), justamente o que não pode sumir.
            async let rep: [EventoVarejo] = Supabase.shared.buscar(
                "eventos_da_semana", "select=*&tipo=eq.reposicao&order=data.desc&limit=200")
            async let rem: [EventoVarejo] = Supabase.shared.buscar(
                "eventos_da_semana", "select=*&tipo=eq.remarcacao&order=data.desc&limit=200")

            todos = try await i
            rotulos = Dictionary(uniqueKeysWithValues: try await t.map { ($0.id, $0.rotulo) })
            eventos = try await rep + (try await rem)

            // As séries das MESMAS semanas dos índices exibidos: é delas que
            // saem a unidade, a contagem e o nome dos veículos.
            let alvos = mudaram
            if !alvos.isEmpty {
                let ids = Set(alvos.map(\.termoId)).joined(separator: ",")
                // Só as semanas que a tela vai mostrar, e não tudo desde a mais
                // antiga. Com `gte` e um teto de linhas, os termos do fim da
                // página vinham sem série nenhuma — e o cartão da Saia dizia
                // "vários desvios" em vez do número, porque não tinha a linha do
                // editorial para ler. É o mesmo erro de paginação dos eventos,
                // no mesmo dia, em outro lugar.
                let semanas = Set(alvos.map(\.semana)).joined(separator: ",")
                let pontos: [PontoSerie] = try await Supabase.shared.buscar(
                    "series_semanais",
                    "select=*&termo_id=in.(\(ids))&semana=in.(\(semanas))&limit=2000")
                var mapa: [String: [PontoSerie]] = [:]
                for p in pontos {
                    guard let alvo = alvos.first(where: { $0.termoId == p.termoId }),
                          alvo.semana == p.semana else { continue }
                    mapa[p.termoId, default: []].append(p)
                }
                series = mapa
            }
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}

// MARK: - Linha de marca

/// "Maria Filó · 12 peças com queda de preço". O número na frente, porque é ele
/// que faz o comprador decidir se abre.
struct LinhaDeMarca: View {
    let marca: String
    let eventos: [EventoVarejo]

    var body: some View {
        Cartao {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    Text(marca).font(Tokens.Fonte.corpo)
                    LinhaInsumo(texto: resumo)
                }
                Spacer()
                Text("\(eventos.count)")
                    .font(Tokens.Fonte.numero)
                Image(systemName: "chevron.right")
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(marca), \(eventos.count) peças. \(resumo)")
    }

    private var resumo: String {
        let repetidas = eventos.filter { ($0.ordinal ?? 1) > 1 }.count
        var partes: [String] = []
        if let d = eventos.map(\.data).max() { partes.append("mais recente em \(Formato.data(d))") }
        if repetidas > 0 { partes.append("\(repetidas) já tinham acontecido antes") }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Lista de peças de uma marca

struct ListaDeEventos: View {
    let marca: String
    let titulo: String
    let eventos: [EventoVarejo]
    let inicioDaColeta: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                ForEach(eventos) { e in
                    Cartao {
                        HStack(alignment: .firstTextBaseline) {
                            Label(e.marca, systemImage: e.icone)
                                .font(Tokens.Fonte.apoio.weight(.semibold))
                            Spacer()
                            Text(Formato.data(e.data)).font(Tokens.Fonte.miudo)
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                        }
                        Text(e.peca ?? "—").font(Tokens.Fonte.corpo)
                        Text(e.resumo).font(Tokens.Fonte.apoio)
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                        // A repetição em destaque: é ela que separa um evento
                        // isolado de um padrão de reposição.
                        if let r = e.repeticao(desde: inicioDaColeta) {
                            Text(r)
                                .font(Tokens.Fonte.miudo.weight(.semibold))
                                .foregroundStyle((e.ordinal ?? 1) > 1 ? Tokens.Cor.alta : Tokens.Cor.tintaFraca)
                        }
                        // Regra 3: todo número carrega o caminho até a origem.
                        if let url = e.urlDaPeca, let link = URL(string: url) {
                            Link("ver no site da marca", destination: link)
                                .font(Tokens.Fonte.miudo)
                        }
                    }
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .navigationTitle("\(titulo) · \(marca)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Cartão do digest

/// Um termo que mudou de estado, com o número **acompanhado da unidade**, a
/// regra que produziu o estado e quem publicou.
struct CartaoDeMudanca: View {
    let indice: IndiceSemanal
    let rotulo: String
    let series: [PontoSerie]

    var body: some View {
        Cartao {
            HStack(alignment: .firstTextBaseline) {
                Text(rotulo).font(Tokens.Fonte.corpo)
                Spacer()
                SeloEstado(estado: indice.estado, motivo: nil)
            }

            // O número com a unidade colada. Antes saía "+1.15" sozinho.
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Espaco.xs) {
                Text(Explicacao.numeroComUnidade(indice.indice))
                    .font(Tokens.Fonte.numero)
                if let v = indice.indice {
                    Text("· \(Leitura.emPalavras(v))")
                        .font(Tokens.Fonte.apoio)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }
            LinhaInsumo(texto: Explicacao.unidadeDoIndice + ".")

            // Por que este estado, e não outro.
            Text(Explicacao.porQue(estado: indice.estado, indice: indice, series: series))
                .font(Tokens.Fonte.apoio)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // De onde veio, com nome de veículo.
            ForEach(Explicacao.origens(series), id: \.self) { LinhaInsumo(texto: $0) }
            LinhaInsumo(texto: "Semana de \(Formato.data(indice.semana)).")

            let manchetes = Explicacao.manchetes(series)
            if !manchetes.isEmpty {
                Text("O que o robô leu").font(Tokens.Fonte.miudo.weight(.semibold))
                ForEach(manchetes, id: \.titulo) { m in
                    if let u = m.url, let link = URL(string: u) {
                        Link(destination: link) {
                            Text("\(m.veiculo): \(m.titulo)")
                                .font(Tokens.Fonte.miudo)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        LinhaInsumo(texto: "\(m.veiculo): \(m.titulo)")
                    }
                }
            }
        }
    }
}
