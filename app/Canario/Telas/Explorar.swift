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
    var menuAberto = false
    var alternarMenu: (() -> Void)?
    @State private var todos: [IndiceSemanal] = []
    @State private var termos: [Termo] = []
    @State private var series: [String: [PontoSerie]] = [:]
    @State private var pulsoBusca: [PontoSerie] = []
    @State private var pulsoEditorial: [PontoSerie] = []
    @State private var eventos: [EventoVarejo] = []
    @State private var inicioDaColeta = "2026-07-24"
    @State private var carregando = true
    @State private var carregandoPulso = true
    @State private var carregandoEditorial = true
    @State private var carregandoEventos = true
    /// Qual metade do cartão de Supply moves está à vista. Reposição primeiro
    /// porque é a que responde "a marca voltou a ter", que é a pergunta mais
    /// comum de quem está comprando.
    @State private var movimentoVisivel = "reposicao"
    /// Constante, e não `@Environment`.
    ///
    /// `.territorio(.mercado)` é aplicado ao conteúdo DESTA view, e ambiente
    /// que a própria view escreve não volta para ela: a propriedade lia o
    /// valor do PAI, que é o padrão `.armario`. O efeito era discreto e
    /// errado -- chevrons e carimbos desta tela saíam com a paleta do armário
    /// enquanto tudo que os rodeia (cartão, selo, barra) lia `.mercado` do
    /// ambiente e se pintava de mercado.
    ///
    /// A aba inteira é mercado, sem condição nenhuma. Declarar isso aqui é
    /// mais honesto do que ler de volta um ambiente que ela mesma escreveu.
    private let territorio: Territorio = .mercado

    /// Quantas linhas cada seção mostra na Trends.
    ///
    /// A tela virou painel de bordo em 27/08: cada seção responde a pergunta
    /// dela com as primeiras linhas e leva o resto para tela própria. Três é o
    /// que cabe sem empurrar a seção seguinte para fora da vista -- e "o que
    /// mudou esta semana" quase sempre tem resposta nas três primeiras. Quem
    /// quiser tudo tem o chevron.
    private static let noPainel = 3
    @State private var erro: String?
    @State private var avisoDeCache: String?
    @State private var avisosParciais: [String] = []

    private let diasMaximosDoDigest = 42

    // Estes dois eram propriedades COMPUTADAS e eram lidos de dentro de
    // closures de `filter` e de laços de cartões: cada leitura percorria a
    // taxonomia inteira. Guardados, custam uma passada por carregamento.
    // Mesmo defeito que travava o Closet; ver `ArmarioVisivel.swift`.
    @State private var rotulos: [String: String] = [:]
    @State private var termosPorId: [String: Termo] = [:]

    private func indexarTermos() {
        rotulos = Dictionary(uniqueKeysWithValues:
            termos.map { ($0.id, Traducao.rotuloExibido($0)) })
        termosPorId = Dictionary(uniqueKeysWithValues: termos.map { ($0.id, $0) })
    }

    /// Um termo por linha, com a mudança MAIS RECENTE dele.
    ///
    /// Sem isto o mesmo termo aparecia várias vezes — "Casaco e jaqueta" saía
    /// duas vezes, nas semanas 13/07 e 06/07. Digest é resumo do que mudou, não
    /// histórico: repetir o termo gasta a atenção do usuário sem informar.
    ///
    /// **Os subtítulos saíram em 28/08, e a ordem tomou o lugar deles.** A
    /// lista vinha partida em quatro blocos com cabeçalho -- "TRENDING UP",
    /// "EDITORIAL HIGHLIGHTS", "NO CONFIRMED MOVEMENT", "TRENDING DOWN" --, e
    /// o terceiro nunca achou nome que não brigasse com o selo do cartão logo
    /// abaixo. O JP cortou o nó: *"acho melhor tirar esses mini titulos e
    /// jogar tudo num bloco só, ordenando pelo que subiu, o que ta estavel e o
    /// que desceu"*.
    ///
    /// É uma lista só, e ela desce como um gradiente: alta, pico, estável,
    /// queda; e, dentro de cada um, o índice maior primeiro. Quem está no topo
    /// subiu mais, quem está no fim caiu mais, e ninguém precisa ler um rótulo
    /// para saber disso. O que cada cartão é continua escrito nele -- o selo
    /// dá a faixa da semana e a frase diz se aquilo virou movimento.
    ///
    /// De quebra, o teto do painel volta a valer: com quatro grupos, `prefix`
    /// cortava CADA um em três e a seção chegava a doze cartões.
    private var mudaram: [IndiceSemanal] {
        var vistos = Set<String>()
        return todos
            .filter { Formato.diasDesde($0.semana) <= diasMaximosDoDigest }
            .filter { vistos.insert($0.termoId).inserted }
            .sorted {
                let esquerda = prioridade($0), direita = prioridade($1)
                if esquerda != direita { return esquerda < direita }
                let zEsquerda = $0.indice, zDireita = $1.indice
                if zEsquerda != zDireita {
                    return (zEsquerda ?? -.greatestFiniteMagnitude)
                         > (zDireita ?? -.greatestFiniteMagnitude)
                }
                return $0.semana > $1.semana
            }
    }

    /// A categoria filtra o mercado (§11); sozinha não é uma tendência. O
    /// radar destaca os atributos atuais e deixa categoria para a busca.
    private var buscaDaSemana: [PontoSerie] {
        guard let semana = pulsoBusca.map(\.semana).max() else { return [] }
        return pulsoBusca.filter {
            $0.semana == semana && $0.z != nil
                && termosPorId[$0.termoId]?.dimensao != "categoria"
        }
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
            // Território de mercado: esta tela e tudo que ela abre são
            // escuros por decisão de produto, não por tema do sistema. Os
            // componentes compartilhados leem isto do ambiente e se adaptam
            // sozinhos -- cartão, linha de apoio e selo de estado.
            .territorio(.mercado)
            // SEM `.toolbarBackground(.visible, for: .navigationBar)`.
            //
            // ELE ERA O SUMIÇO DO "WEEKLY TRENDS". O JP relatou o defeito em
            // 27/08 -- *"o 'Weekly Trends' tá sumindo do Topo"* --, eu não
            // consegui reproduzir e ficou de resolver no aparelho. A gravação
            // de 30/08 mostrou, e reproduz no simulador com um gesto: role a
            // aba para baixo e volte ao topo. O título grande não volta.
            //
            // O espaço dele CONTINUA reservado -- o cartão do Comparar fica
            // na mesma altura com e sem título --, então não era layout: o
            // fundo opaco forçado da barra passava por cima do título grande
            // depois do primeiro ciclo de colapso. Sem `.visible`, o iOS
            // mostra o fundo quando a barra está colapsada e o esconde no
            // topo, que é onde o título grande vive.
            //
            // A cor continua declarada: quando a barra aparece, ela é
            // `noturno`, e não o material translúcido do sistema.
            .toolbarBackground(Tokens.Cor.noturno, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle("Weekly Trends")
            // Uma reindexação por chegada de taxonomia, venha ela da rede
            // (`carregar`) ou do snapshot em disco. Ficar preso a um dos dois
            // caminhos deixaria a tela sem rótulo no outro.
            .onChange(of: termos) { _, _ in indexarTermos() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let alternarMenu {
                        // A cor sai declarada porque, sem o fundo forçado, a
                        // do botão passava a depender da rolagem: azul de
                        // sistema no topo, branca com a barra colapsada.
                        BotaoDoMenu(menuAberto: menuAberto, acao: alternarMenu)
                            .tint(Tokens.Cor.tintaDo(territorio))
                    }
                }
            }
        }
        .task { await carregar() }
    }

    private var conteudo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if let avisoDeCache {
                    Label(avisoDeCache, systemImage: "wifi.slash")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
                if !avisosParciais.isEmpty {
                    ForEach(avisosParciais, id: \.self) { aviso in
                        Label(aviso, systemImage: "exclamationmark.circle")
                            .font(Tokens.Fonte.miudo)
                            .foregroundStyle(Tokens.Cor.tintaFraca)
                    }
                }
                // A curva de tamanhos saiu daqui em 29/08. Ela continua
                // inteira onde tem dono -- no relatório do termo e na tela
                // cheia --, e o JP explicou a troca pelo que ela custava:
                // *"poderia continuar só na página dos produtos individuais
                // como já tá e sair dessa tela, devolvendo protagonismo pro
                // compare"*. A escada é do painel inteiro; ela não responde
                // "o que mudou esta semana", que é a pergunta da aba.
                //
                // Comparar volta ao topo com isso, e vale registrar a tensão:
                // a §24 pede valor de esforço zero na abertura, e Comparar é
                // ferramenta -- ela pede que a pessoa escolha atributos antes
                // de devolver qualquer coisa. Quem responde de graça continua
                // logo abaixo, na ordem de sempre. Descer o atalho de volta
                // para o fim é mover uma linha.
                atalhoDeComparacao
                movimentos
                digest
                radarDeBusca
                radarEditorial
            }
            .padding(Tokens.Espaco.m)
            .padding(.bottom, 20)
        }
    }

    /// Comparar é uma ferramenta de leitura de tendências, não uma forma de
    /// encontrar uma peça. Mantê-la nesta aba evita competir com a Search da
    /// barra principal e dá contexto antes de escolher os atributos.
    ///
    /// **As cores eram do armário numa tela de mercado.** Ícone em
    /// `Tokens.Cor.acao`, título em `tinta`, seta em `tintaFraca` -- três
    /// tokens que resolvem pelo tema do sistema, num cartão que hoje abre o
    /// painel escuro. Passa a ler o território como o resto da aba.
    private var atalhoDeComparacao: some View {
        NavigationLink {
            // O Comparar declara o próprio território desde 30/08, com as
            // duas coisas que a `List` exige: esconder o fundo agrupado do
            // sistema E pintar o do território. Por muito tempo aqui havia um
            // aviso dizendo que não dava; dava, faltava a primeira metade.
            Comparar()
        } label: {
            Cartao {
                HStack(spacing: Tokens.Espaco.m) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Tokens.Cor.acentoDo(territorio))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Compare attributes")
                            .font(Tokens.Fonte.secao)
                            .foregroundStyle(Tokens.Cor.tintaDo(territorio))
                        Text("Put market readings side by side.")
                            .font(Tokens.Fonte.apoio)
                            .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Tokens.Fonte.miudo.weight(.semibold))
                        .foregroundStyle(Tokens.Cor.acentoDo(territorio))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Movimento das marcas

    /// Uma linha por marca, com o total; a lista de peças abre no toque.
    /// Reposições e remarcações num cartão só, com segmento.
    ///
    /// Elas eram duas seções longas, empilhadas, com a mesma forma e a mesma
    /// altura -- e a pessoa rolava a segunda inteira sem perceber que já tinha
    /// lido aquela estrutura. Juntar corta metade da rolagem sem tirar nada:
    /// as duas continuam completas, uma de cada vez. Ideia da Bianca, e o JP
    /// assinou embaixo.
    private func rotuloDoMovimento(_ tipo: String) -> String {
        tipo == "reposicao" ? "Restocks" : "Markdowns"
    }

    private var movimentos: some View {
        movimentos(limite: Self.noPainel, mostraCabecalho: true)
    }

    private var movimentosCompletos: some View {
        ScrollView {
            // O assunto já está na barra de navegação. Repetir "Supply
            // moves" imediatamente abaixo dela criava dois títulos para a
            // mesma tela e empurrava o primeiro dado para baixo.
            movimentos(limite: nil, mostraCabecalho: false)
                .padding(Tokens.Espaco.m)
        }
        .territorio(.mercado)
        .navigationTitle("Supply moves")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func movimentos(limite: Int?, mostraCabecalho: Bool) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            if mostraCabecalho {
                cabecalhoDeSecao(
                    "Supply moves", carimbo: nil,
                    porta: { AnyView(movimentosCompletos) })
            }
            Picker("Supply moves", selection: $movimentoVisivel) {
                Text("Restocks").tag("reposicao")
                Text("Markdowns").tag("remarcacao")
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Which supply move to show")

            if movimentoVisivel == "reposicao" {
                movimento(titulo: nil, tipo: "reposicao", limite: limite,
                          vazio: "No restock was confirmed in this window. Confirmation requires seeing a size disappear, return and remain available.")
            } else {
                movimento(titulo: nil, tipo: "remarcacao", limite: limite,
                          vazio: "No price reduction of 5% or more was confirmed in this window.")
            }
        }
    }

    private func movimento(titulo: String?, tipo: String, limite: Int?, vazio: String) -> some View {
        let doTipo = eventos.filter { $0.tipo == tipo }
        let porMarca = Dictionary(grouping: doTipo, by: \.marca)
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
        let maisRecente = doTipo.map(\.data).max()

        return VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            HStack(alignment: .firstTextBaseline) {
                if let titulo { Text(titulo).font(Tokens.Fonte.secao) }
                Spacer()
                if let maisRecente {
                    // O carimbo que faltava: o usuário vê a data do dado sem
                    // precisar deduzi-la de um cartão.
                    Text(carimbo(maisRecente))
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(Tokens.Cor.tintaFraca)
                }
            }
            if carregandoEventos && porMarca.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if porMarca.isEmpty {
                CoberturaInsuficiente(titulo: "No record in this window",
                                      explicacao: vazio, oQueTem: nil)
            } else {
                ForEach(limite.map { Array(porMarca.prefix($0)) } ?? porMarca,
                        id: \.key) { marca, lista in
                    NavigationLink {
                        // O título saiu do cabeçalho quando as duas seções
                        // viraram um cartão com segmento, mas a tela de
                        // destino ainda precisa dizer de qual movimento ela
                        // é -- lá não há segmento nenhum à vista.
                        ListaDeEventos(marca: marca,
                                       titulo: titulo ?? rotuloDoMovimento(tipo),
                                       eventos: lista,
                                       inicioDaColeta: inicioDaColeta)
                    } label: {
                        LinhaDeMarca(marca: marca, eventos: lista)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// O cabeçalho de uma seção do painel: título, carimbo e a porta.
    ///
    /// A porta é `nil` quando não há para onde ir — na própria tela cheia da
    /// seção, ou quando ela está vazia. Chevron que não leva a lugar nenhum é
    /// pior que chevron nenhum: promete conteúdo e entrega uma volta.
    @ViewBuilder
    private func cabecalhoDeSecao(_ titulo: String, carimbo: String?,
                                  porta: (() -> AnyView)?) -> some View {
        let miolo = HStack(alignment: .firstTextBaseline) {
            Text(titulo).font(Tokens.Fonte.secao)
            Spacer()
            if let carimbo {
                Text(carimbo)
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
            }
            if porta != nil {
                Image(systemName: "chevron.right")
                    .font(Tokens.Fonte.miudo.weight(.semibold))
                    .foregroundStyle(Tokens.Cor.acentoDo(territorio))
            }
        }
        .contentShape(Rectangle())

        if let porta {
            NavigationLink { porta() } label: { miolo }
                .buttonStyle(.plain)
                .accessibilityLabel("\(titulo), see all")
        } else {
            miolo
        }
    }

    /// A data do dado, sempre explícita.
    ///
    /// A §6 barra as frases de cultivo do tipo "está fresquinho", e com razão:
    /// além de serem linguagem de engajamento, elas somem justamente no dia em
    /// que o usuário mais precisa saber se o número envelheceu. A data resolve
    /// as duas coisas de uma vez.
    private func carimbo(_ data: String) -> String {
        "most recent event: \(Formato.data(data))"
    }

    // MARK: Radares atuais

    /// Google é uma fonte, não um veredito. Mostrá-lo separadamente resolve o
    /// atraso aparente sem enfraquecer a regra que exige duas fontes para
    /// chamar algo de tendência confirmada.
    private var radarDeBusca: some View { radarDeBusca(limite: Self.noPainel) }

    /// A lista inteira, em tela própria.
    ///
    /// Ela era a seção do painel sem o limite, e trazia dois defeitos junto:
    /// repetia "Search interest now" logo abaixo do título da barra, e a
    /// primeira linha de cada grupo ainda pagava o preço do cabeçalho de
    /// seção, com carimbo e chevron que aqui não levam a lugar nenhum.
    ///
    /// Aqui ela é a tela: o assunto está na barra, a régua vem uma vez no
    /// topo, e o resto é lista.
    private var radarDeBuscaCompleto: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                Text(Self.reguaDaBusca)
                    .font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                if let semana = buscaDaSemana.map(\.semana).max() {
                    LinhaInsumo(texto: "Latest closed Google week: \(Formato.data(semana)).")
                }
                listaDaBusca(limite: nil)
            }
            .padding(Tokens.Espaco.m)
            .padding(.bottom, 20)
        }
        .territorio(.mercado)
        .navigationTitle("Search interest now")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let reguaDaBusca = "What people in Brazil searched for on Google, "
        + "compared with each term's previous 12 weeks."

    private func radarDeBusca(limite: Int?) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            cabecalhoDeSecao(
                "Search interest now",
                carimbo: buscaDaSemana.map(\.semana).max().map(Formato.data),
                porta: limite == nil || buscaDaSemana.isEmpty
                       ? nil : { AnyView(radarDeBuscaCompleto) })
            Text(Self.reguaDaBusca)
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))

            listaDaBusca(limite: limite)
        }
    }

    /// Os grupos e as linhas, com o teto do painel contado na LISTA INTEIRA.
    ///
    /// O `prefix` ficava dentro de cada grupo, então "três" virava três por
    /// grupo -- até doze linhas no painel. É o mesmo defeito que o "What
    /// changed?" tinha antes de virar bloco único; aqui os grupos ficam,
    /// porque o JP os manteve, mas o teto passa a valer para o todo.
    @ViewBuilder
    private func listaDaBusca(limite: Int?) -> some View {
        if carregandoPulso && buscaDaSemana.isEmpty {
            ProgressView().frame(maxWidth: .infinity, alignment: .center)
        } else if buscaDaSemana.isEmpty {
            LinhaInsumo(texto: "No current Google search reading is available.")
        } else {
            ForEach(gruposVisiveis(limite: limite), id: \.titulo) { grupo in
                    if !grupo.pontos.isEmpty {
                        Text(grupo.titulo.uppercased())
                            .font(Tokens.Fonte.miudo.weight(.semibold))
                            .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
                            .padding(.top, Tokens.Espaco.xs)
                        ForEach(grupo.pontos) { ponto in
                            if let termo = termosPorId[ponto.termoId] {
                                NavigationLink { RelatorioDoTermo(termo: termo) } label: {
                                    Cartao {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(Traducao.rotuloExibido(termo)).font(Tokens.Fonte.corpo)
                                            Spacer()
                                            // SEM O NÚMERO AQUI, e a tentativa
                                            // valeu o registro: eu o acrescentei
                                            // achando que duas linhas com o
                                            // mesmo selo pareceriam empatadas.
                                            // Ele custa ~55 pt e o selo mais
                                            // longo -- "Far Above the usual
                                            // range" -- passou a quebrar em
                                            // duas linhas nos termos de nome
                                            // maior, deixando as linhas com
                                            // alturas diferentes: o mesmo
                                            // desalinhamento que o JP tinha
                                            // acabado de apontar nos cartões
                                            // de fonte. E a lista já desce
                                            // ordenada pelo índice, então a
                                            // posição diz o que o número
                                            // diria. Quem quiser o valor
                                            // toca e abre o relatório.
                                            //
                                            // O mesmo selo do "What
                                            // changed?", em vez de uma frase
                                            // solta em azul. Duas listas com
                                            // a mesma pergunta e dois jeitos
                                            // de responder obrigam a pessoa a
                                            // aprender o app duas vezes.
                                            SeloEstado(estado: nil, leitura: ponto.z)
                                            Image(systemName: "chevron.right")
                                                .font(Tokens.Fonte.miudo)
                                                .foregroundStyle(Tokens.Cor.acentoDo(territorio))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
            }
        }
    }

    /// Os grupos cortados pelo teto do painel, contando a lista inteira.
    ///
    /// Grupo que ficou sem nenhuma linha some junto com o próprio cabeçalho:
    /// título de grupo vazio é a mesma promessa quebrada do chevron que não
    /// leva a lugar nenhum.
    private func gruposVisiveis(limite: Int?) -> [(titulo: String, pontos: [PontoSerie])] {
        guard let limite else { return gruposDaBusca }
        var restante = limite
        var saida: [(titulo: String, pontos: [PontoSerie])] = []
        for grupo in gruposDaBusca where restante > 0 && !grupo.pontos.isEmpty {
            let fatia = Array(grupo.pontos.prefix(restante))
            restante -= fatia.count
            saida.append((grupo.titulo, fatia))
        }
        return saida
    }

    private var gruposDaBusca: [(titulo: String, pontos: [PontoSerie])] {
        let ordenados = buscaDaSemana.sorted { ($0.z ?? 0) > ($1.z ?? 0) }
        return [
            ("High", ordenados.filter { ($0.z ?? 0) >= 1 }),
            ("Building", ordenados.filter { (0.35..<1).contains($0.z ?? 0) }),
            ("Steady", ordenados.filter { abs($0.z ?? 0) < 0.35 }),
            // "Cooling" saiu em 28/08: era a única das quatro que descrevia
            // um MOVIMENTO -- esfriando -- numa lista que mede POSIÇÃO. O JP
            // resolveu pelo par que já estava ali: *"se tem high pode ter
            // low"*.
            //
            // O `.reversed()` daqui punha "Far below" ACIMA de "Under the
            // usual range", e o JP leu o que a ordem estava dizendo: *"quanto
            // mais em queda, mais em baixo deveria ficar"*. Sem ele, a seção
            // inteira -- High, Building, Steady, Low -- desce como um
            // gradiente só, do índice maior para o menor.
            ("Low", ordenados.filter { ($0.z ?? 0) <= -0.35 }),
        ].map { ($0.0, Array($0.1)) }
    }

    private var manchetesAtuais: [PontoSerie.Meta.Exemplo] {
        guard let semana = pulsoEditorial.map(\.semana).max() else { return [] }
        var vistos = Set<String>()
        return pulsoEditorial
            .filter { $0.semana == semana }
            .flatMap { $0.meta?.exemplos ?? [] }
            .filter { Explicacao.mancheteDeclaraModa($0.titulo) }
            .filter { vistos.insert(($0.url ?? $0.titulo).lowercased()).inserted }
            .prefix(8).map { $0 }
    }

    private var radarEditorial: some View {
        radarEditorial(limite: Self.noPainel, mostraCabecalho: true)
    }

    private var radarEditorialCompleto: some View {
        ScrollView {
            // A barra já nomeia a tela. Aqui entram direto a data, a régua e
            // as matérias, sem repetir "This week in fashion" duas vezes.
            radarEditorial(limite: nil, mostraCabecalho: false)
                .padding(Tokens.Espaco.m)
        }
        .territorio(.mercado)
        .navigationTitle("This week in fashion")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func radarEditorial(limite: Int?, mostraCabecalho: Bool) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            if mostraCabecalho {
                cabecalhoDeSecao(
                    "This week in fashion",
                    carimbo: pulsoEditorial.map(\.semana).max().map(Formato.data),
                    porta: manchetesAtuais.isEmpty
                           ? nil : { AnyView(radarEditorialCompleto) })
            } else if let semana = pulsoEditorial.map(\.semana).max() {
                LinhaInsumo(texto: "Latest publication week: \(Formato.data(semana)).")
            }
            Text("Current, fashion-specific headlines from the monitored publications. They provide context; one article alone does not establish a trend.")
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))

            if carregandoEditorial && manchetesAtuais.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if manchetesAtuais.isEmpty {
                LinhaInsumo(texto: "No current headline passed the fashion-context check.")
            } else {
                ForEach(manchetesAtuais.prefix(limite ?? manchetesAtuais.count),
                        id: \.titulo) { manchete in
                    if let bruto = manchete.url, let url = URL(string: bruto) {
                        Link(destination: url) { linhaEditorial(manchete) }
                            .buttonStyle(.plain)
                    } else {
                        linhaEditorial(manchete)
                    }
                }
            }
        }
    }

    private func linhaEditorial(_ manchete: PontoSerie.Meta.Exemplo) -> some View {
        Cartao {
            Text(manchete.titulo)
                .font(Tokens.Fonte.apoio.weight(.semibold))
                .foregroundStyle(Tokens.Cor.tinta)
            HStack {
                Text(manchete.veiculo).font(Tokens.Fonte.miudo)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(Tokens.Fonte.miudo)
            }
            .foregroundStyle(Tokens.Cor.acao)
        }
    }

    // MARK: Tendência confirmada

    private var digest: some View {
        digest(limite: Self.noPainel, mostraCabecalho: true)
    }

    /// A seção inteira, em tela própria.
    private var digestCompleto: some View {
        ScrollView {
            // A barra já traz "What changed?". A tela começa pela data que
            // explica o recorte, não por uma segunda cópia do título.
            digest(limite: nil, mostraCabecalho: false)
                .padding(Tokens.Espaco.m)
        }
        .territorio(.mercado)
        .navigationTitle("What changed?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func digest(limite: Int?, mostraCabecalho: Bool) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            // "Confirmed movements" era o nome do dado; "What changed?" é a
            // pergunta que a pessoa tem. Pedido do Davi, o JP assinou embaixo.
            if mostraCabecalho {
                cabecalhoDeSecao(
                    "What changed?", carimbo: nil,
                    porta: mudaram.isEmpty ? nil : { AnyView(digestCompleto) })
            }
            if let semana = mudaram.map(\.semana).max() {
                // Esta data não é a data da coleta inteira: é a última semana
                // em que as duas pernas necessárias puderam ser comparadas.
                // "updated" fazia a tela parecer congelada em 10/08 mesmo
                // com reposições de 25/08 e editorial de 24/08 na mesma aba.
                LinhaInsumo(texto: "Latest week when two sources overlapped: \(Formato.data(semana)).")
            }
            if mudaram.isEmpty {
                LinhaInsumo(texto: "No movement has been confirmed by two independent sources in the last \(diasMaximosDoDigest) days.")
            } else {
                ForEach(limite.map { Array(mudaram.prefix($0)) } ?? mudaram) { i in
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

    private func prioridade(_ indice: IndiceSemanal) -> Int {
        let ordem = ["em alta": 0, "pico": 1, "estavel": 2, "em queda": 3]
        return ordem[indice.estado ?? ""] ?? 4
    }

    private func termoDe(_ i: IndiceSemanal) -> Termo? {
        guard let rotulo = rotulos[i.termoId] else { return nil }
        return Termo(id: i.termoId, rotulo: rotulo, dimensao: "", exclusiva: false,
                     sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    @MainActor
    private func carregar() async {
        erro = nil
        avisoDeCache = nil
        avisosParciais = []
        var mostrouCache = false
        if let salvo = await CacheDoExplorar.shared.carregar() {
            aplicar(salvo)
            carregando = false
            mostrouCache = true
            // Trocar de aba e voltar não refaz cinco consultas. Os carimbos
            // continuam mostrando a idade real do dado; isto só evita trabalho
            // duplicado dentro dos quinze minutos seguintes à sincronização.
            if Date().timeIntervalSince(salvo.salvoEm) < 15 * 60 { return }
        } else {
            carregando = true
            carregandoPulso = true
            carregandoEditorial = true
            carregandoEventos = true
        }

        do {
            async let i = CatalogoDeIndices.shared.carregar()
            async let t = CatalogoDeTermos.shared.carregar()

            todos = try await i.filter { $0.estado != nil }
            termos = try await t
            carregando = false
        } catch {
            let mensagem = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            if mostrouCache {
                avisoDeCache = "Offline · showing the last sync"
                erro = nil
            } else {
                erro = mensagem
            }
            carregando = false
            return
        }

        // A primeira tela útil já está visível. Radar, manchetes, explicações
        // e eventos renovam em paralelo, cada um com seu próprio estado. Uma
        // recusa do CDN ou um RPC lento não volta a cobrir tudo com spinner.
        async let busca: Void = carregarPulsoDeBusca()
        async let editorial: Void = carregarPulsoEditorial()
        async let detalhes: Void = carregarDetalhesConfirmados()
        async let movimentos: Void = carregarEventos()
        _ = await (busca, editorial, detalhes, movimentos)

        await CacheDoExplorar.shared.salvar(SnapshotDoExplorar(
            todos: todos, termos: termos, series: series,
            pulsoBusca: pulsoBusca, pulsoEditorial: pulsoEditorial,
            eventos: eventos, salvoEm: Date()))
    }

    @MainActor
    private func carregarPulsoDeBusca() async {
        carregandoPulso = true
        defer { carregandoPulso = false }
        do {
            let corte = Self.dataISO(diasAtras: 21)
            let novos: [PontoSerie] = try await Supabase.shared.buscar(
                "series_do_app",
                "select=*&segmento=eq.\(Recorte.segmento)&fonte=eq.busca"
                + "&semana=gte.\(corte)&order=semana.desc&limit=250")
            pulsoBusca = novos
        } catch {
            avisar("Search interest could not refresh; the rest of the page is available.")
        }
    }

    @MainActor
    private func carregarPulsoEditorial() async {
        carregandoEditorial = true
        defer { carregandoEditorial = false }
        do {
            let corte = Self.dataISO(diasAtras: 14)
            let novos: [PontoSerie] = try await Supabase.shared.buscar(
                "series_do_app",
                "select=*&segmento=eq.\(Recorte.segmento)"
                + "&fonte=in.(editorial_br,editorial_intl)&semana=gte.\(corte)"
                + "&order=semana.desc&limit=250")
            pulsoEditorial = novos
        } catch {
            avisar("Fashion headlines could not refresh; the rest of the page is available.")
        }
    }

    @MainActor
    private func carregarDetalhesConfirmados() async {
        let alvos = mudaram
        guard !alvos.isEmpty else { series = [:]; return }
        do {
            let ids = Set(alvos.map(\.termoId)).joined(separator: ",")
            let semanas = Set(alvos.map(\.semana)).joined(separator: ",")
            let pontos: [PontoSerie] = try await Supabase.shared.buscar(
                "series_do_app",
                "select=*&termo_id=in.(\(ids))&semana=in.(\(semanas))&limit=1000")
            let semanaDoAlvo = Dictionary(
                alvos.map { ($0.termoId, $0.semana) },
                uniquingKeysWith: { primeiro, _ in primeiro })
            var mapa: [String: [PontoSerie]] = [:]
            for p in pontos where semanaDoAlvo[p.termoId] == p.semana {
                mapa[p.termoId, default: []].append(p)
            }
            series = mapa
        } catch {
            avisar("Confirmed-movement details could not refresh.")
        }
    }

    @MainActor
    private func carregarEventos() async {
        carregandoEventos = true
        defer { carregandoEventos = false }
        do {
            async let rep: [EventoVarejo] = Supabase.shared.chamar(
                "eventos_recentes", ["tipo_evento": "reposicao", "limite": 120])
            async let rem: [EventoVarejo] = Supabase.shared.chamar(
                "eventos_recentes", ["tipo_evento": "remarcacao", "limite": 120])
            eventos = try await rep + (try await rem)
        } catch {
            avisar("Store movements could not refresh.")
        }
    }

    @MainActor
    private func avisar(_ texto: String) {
        if !avisosParciais.contains(texto) { avisosParciais.append(texto) }
    }

    @MainActor
    private func aplicar(_ salvo: SnapshotDoExplorar) {
        todos = salvo.todos
        termos = salvo.termos
        series = salvo.series
        pulsoBusca = salvo.pulsoBusca
        pulsoEditorial = salvo.pulsoEditorial
        eventos = salvo.eventos
        carregandoPulso = false
        carregandoEditorial = false
        carregandoEventos = false
    }

    private static func dataISO(diasAtras: Int) -> String {
        let data = Calendar(identifier: .iso8601).date(
            byAdding: .day, value: -diasAtras, to: Date()) ?? Date()
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: data)
    }
}

// MARK: - Cache instantâneo da aba

struct SnapshotDoExplorar: Codable {
    let todos: [IndiceSemanal]
    let termos: [Termo]
    let series: [String: [PontoSerie]]
    let pulsoBusca: [PontoSerie]
    let pulsoEditorial: [PontoSerie]
    let eventos: [EventoVarejo]
    let salvoEm: Date
}

actor CacheDoExplorar {
    static let shared = CacheDoExplorar()
    private var memoria: SnapshotDoExplorar?

    private var arquivo: URL {
        FileManager.default.urls(for: .cachesDirectory,
                                 in: .userDomainMask)[0]
            // v3 desde 29/08. O nome ficou: um arquivo v3 gravado com o
            // campo `curva`, que existiu por algumas horas, decodifica sem ele
            // (chave desconhecida é ignorada), e voltar para `v2` só faria
            // ressuscitar um cache mais velho ainda parado em disco.
            .appendingPathComponent("canario-explorar-v3.json")
    }

    func carregar() -> SnapshotDoExplorar? {
        if let memoria { return memoria }
        guard let dados = try? Data(contentsOf: arquivo),
              let salvo = try? JSONDecoder().decode(
                SnapshotDoExplorar.self, from: dados) else { return nil }
        memoria = salvo
        return salvo
    }

    func salvar(_ snapshot: SnapshotDoExplorar) {
        memoria = snapshot
        guard let dados = try? JSONEncoder().encode(snapshot) else { return }
        try? dados.write(to: arquivo, options: .atomic)
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
            HStack(alignment: .center, spacing: Tokens.Espaco.s) {
                HStack(spacing: -10) {
                    ForEach(Array(eventos.compactMap(\.imagem).prefix(3).enumerated()),
                            id: \.offset) { _, endereco in
                        ZStack {
                            Circle().fill(Tokens.Cor.superficie)
                            Image(systemName: "tshirt")
                                .font(.caption)
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                            ImagemRemota(endereco: URL(string: endereco), modo: .fit)
                                .clipShape(Circle())
                        }
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(Tokens.Cor.fundo, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    Text(NomeDeMarca.exibido(marca)).font(Tokens.Fonte.corpo)
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
        .accessibilityLabel("\(NomeDeMarca.exibido(marca)), \(eventos.count) items. \(resumo)")
    }

    private var resumo: String {
        let repetidas = eventos.filter { ($0.ordinal ?? 1) > 1 }.count
        var partes: [String] = []
        // Estava em português numa interface inteiramente em inglês, e só
        // apareceu quando o fundo escuro parou de esconder o texto de apoio.
        if let d = eventos.map(\.data).max() { partes.append("most recent on \(Formato.data(d))") }
        if repetidas > 0 { partes.append("\(repetidas) had happened before") }
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
                        HStack(alignment: .top, spacing: Tokens.Espaco.m) {
                            ZStack {
                                Tokens.Cor.fundo.opacity(0.55)
                                Image(systemName: "tshirt")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(Tokens.Cor.tintaFraca)
                                ImagemRemota(endereco: e.imagem.flatMap(URL.init(string:)),
                                             modo: .fit)
                            }
                            .frame(width: 82, height: 108)
                            .clipShape(RoundedRectangle(
                                cornerRadius: Tokens.Raio.etiqueta,
                                style: .continuous))
                            VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                                HStack(alignment: .firstTextBaseline) {
                                    Label(NomeDeMarca.exibido(e.marca), systemImage: e.icone)
                                        .font(Tokens.Fonte.apoio.weight(.semibold))
                                    Spacer()
                                    Text(Formato.data(e.data)).font(Tokens.Fonte.miudo)
                                        .foregroundStyle(Tokens.Cor.tintaFraca)
                                }
                                Text(e.peca ?? "—").font(Tokens.Fonte.corpo)
                                Text(e.resumo).font(Tokens.Fonte.apoio)
                                    .foregroundStyle(Tokens.Cor.tintaFraca)
                            }
                        }
                        // A repetição em destaque: é ela que separa um evento
                        // isolado de um padrão de reposição.
                        if let r = e.repeticao(desde: inicioDaColeta) {
                            Text(r)
                                .font(Tokens.Fonte.miudo.weight(.semibold))
                                .foregroundStyle((e.ordinal ?? 1) > 1 ? Tokens.Cor.alta : Tokens.Cor.tintaFraca)
                        }
                        // Regra 3: todo número carrega o caminho até a origem.
                        if let url = e.urlDaPeca, let link = URL(string: url) {
                            Link("View on the brand's website", destination: link)
                                .font(Tokens.Fonte.miudo)
                        }
                    }
                }
            }
            .padding(Tokens.Espaco.m)
        }
        // NavigationLink não é uma fronteira de design confiável: esta tela
        // herdava o esquema escuro da aba, mas não o fundo nem os cartões do
        // território. O resultado era preto puro (`systemBackground`) atrás
        // de cinza genérico nas listas Restocks/Markdowns. É uma tela de
        // mercado e precisa declarar isso por conta própria.
        .territorio(.mercado)
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
    @Environment(\.territorio) private var territorio

    var body: some View {
        Cartao {
            HStack(alignment: .firstTextBaseline) {
                Text(rotulo).font(Tokens.Fonte.corpo)
                Spacer()
                SeloEstado(estado: indice.estado, leitura: indice.indice)
            }

            // O selo já diz a faixa em palavras. A linha grande logo abaixo
            // dizia exatamente a mesma coisa -- "Under the usual range" no
            // selo e "under the usual range" no texto --, e repetição é o
            // tipo de ruído que faz a pessoa parar de ler o cartão inteiro.
            //
            // Por que este estado, e não outro: essa frase FICA. É ela que
            // diferencia "duas semanas seguidas com duas fontes concordando"
            // de "uma semana fraca", e é a única linha do cartão que a pessoa
            // não consegue deduzir sozinha.
            Text(Explicacao.porQue(estado: indice.estado, indice: indice, series: series))
                .font(Tokens.Fonte.apoio)
                .fixedSize(horizontal: false, vertical: true)

            // A trilha de auditoria desce e recolhe, como no painel da peça e
            // na tela de atributos. A regra 3 exige que ela EXISTA e possa ser
            // aberta; não exige que ela ocupe três quartos do cartão de quem
            // veio só saber o que mudou esta semana.
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                    LinhaInsumo(texto: "Compared with this attribute's usual behavior over the previous 12 weeks.")
                    ForEach(Explicacao.origens(series), id: \.self) { LinhaInsumo(texto: $0) }
                    LinhaInsumo(texto: "Reading updated: \(Formato.data(indice.semana)).")

                    let manchetes = Explicacao.manchetes(series)
                    if !manchetes.isEmpty {
                        Text("Related articles")
                            .font(Tokens.Fonte.miudo.weight(.semibold))
                            .padding(.top, Tokens.Espaco.xs)
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
                .padding(.top, Tokens.Espaco.xs)
            } label: {
                Text("Where this reading comes from")
                    .font(Tokens.Fonte.miudo.weight(.medium))
            }
            .tint(Tokens.Cor.tintaFracaDo(territorio))
        }
    }
}

enum NomeDeMarca {
    static func exibido(_ nome: String) -> String {
        nome == "Maria Filo" ? "Maria Filó" : nome
    }
}
