import SwiftUI

@main
struct CanarioApp: App {
    @StateObject private var conta = GestorDaConta.shared
    @StateObject private var links = CentralDeLinksCompartilhados.shared
    /// O idioma vive na raiz porque troca a CENA inteira, e não uma tela.
    /// Ver `Idioma.swift`: mudar `preferencia` reconstrói o bundle das frases
    /// calculadas e, aqui, troca o `locale` do ambiente — que é o que faz o
    /// SwiftUI reler o catálogo sem o app fechar.
    @StateObject private var idioma = GestorDeIdioma.shared

    var body: some Scene {
        // A paleta escura experimental de 19/08 nunca passou por revisão de
        // design e, no teste em aparelho, fez o mesmo build parecer outro app.
        // A 1.1 preserva a aparência clara aprovada em todos os iPhones. Quando
        // houver telas escuras desenhadas e validadas, este bloqueio sai daqui.
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("-CanarioAmostraDeIcones") {
                    // Folha de referência do desenho, não tela de produto.
                    AmostraDeIcones()
                } else if ProcessInfo.processInfo.arguments.contains("-CanarioUITestCompare") {
                    NavigationStack { Comparar() }
                } else if ProcessInfo.processInfo.arguments.contains("-CanarioUITestSizesStripes") {
                    NavigationStack {
                        CurvaDeTamanhosView(termo: Termo(
                            id: "listra", rotulo: "Listra", dimensao: "estampa",
                            exclusiva: false, sinonimos: nil, semPernaBusca: nil,
                            palavrasPt: nil, palavrasEn: nil))
                    }
                } else {
                    Raiz()
                }
            }
            .environmentObject(conta)
            .environmentObject(links)
            .environmentObject(idioma)
            // Trocar `\.locale` invalida toda a subárvore que o lê, e todo
            // `Text(LocalizedStringKey)` lê. É por isso que NÃO há um `.id()`
            // aqui forçando a cena a renascer: `.id()` funcionaria, e de
            // quebra fecharia os Ajustes no instante em que a pessoa toca em
            // "Português" -- porque o estado da apresentação modal mora na
            // `Raiz`, dentro do que o `.id()` destruiria.
            .environment(\.locale, idioma.locale)
            .onOpenURL {
                conta.receberLink($0)
                links.receber($0)
            }
        }
    }
}

/// Navegação principal aprovada no fluxo de 12/08: Add · Closet · Analytics,
/// com busca separada. Só a aba visível existe na árvore, preservando o ganho
/// de performance da A14 (as consultas das telas ocultas não disparam juntas).
struct Raiz: View {
    /// Os nomes e símbolos das abas vivem em `AbaDoApp`, fora da View, porque
    /// já divergiram entre as duas navegações uma vez.
    typealias Aba = AbaDoApp
    @EnvironmentObject private var links: CentralDeLinksCompartilhados

    /// A `Raiz` PRECISA observar o idioma, e o motivo não é óbvio.
    ///
    /// Trocar `\.locale` no ambiente invalida quem LÊ o ambiente, e todo
    /// `Text(LocalizedStringKey)` lê — por isso o conteúdo das telas troca
    /// sozinho. O rótulo de uma aba não é isso: `Aba.armario.titulo` é uma
    /// `String` já calculada por `frase(_:)` quando o `body` rodou, e o `body`
    /// da `Raiz` não roda de novo só porque um valor de ambiente mudou lá em
    /// cima. `Raiz()` também não tem propriedade nenhuma para o SwiftUI
    /// comparar, então ele conclui que a view é a mesma e pula o `body`.
    ///
    /// Resultado medido no simulador em 05/09: a tela inteira virou para o
    /// inglês e a barra continuou "Estúdio · Closet · Tendências". Observar o
    /// gestor aqui é o que amarra o `body` da raiz à troca — e, com ele, a
    /// barra de compatibilidade e o menu lateral, que são filhos deste `body`.
    @ObservedObject private var idioma = GestorDeIdioma.shared

    struct ItemDoMenu: Identifiable {
        let entrada: EntradaDoMenu
        var id: String { entrada.rawValue }
    }

    /// Argumento de inspeção visual: permite abrir o Closet no simulador sem
    /// adicionar um atalho de produto nem disparar consultas das abas ocultas.
    @State private var aba: Aba = {
        if ProcessInfo.processInfo.arguments.contains("-CanarioAbrirCloset") {
            return .armario
        }
        if ProcessInfo.processInfo.arguments.contains("-CanarioAbrirTrends") {
            return .dados
        }
        return .adicionar
    }()
    /// A busca abre direto em teste de interface. Ela é `fullScreenCover` da
    /// raiz e depende de um toque na barra; sem este atalho, um teste do
    /// bloco editorial gastaria metade do tempo chegando até a tela.
    @State private var buscaAberta = ProcessInfo.processInfo.arguments.contains(
        "-CanarioAbrirBusca")
    @State private var menuAberto = ProcessInfo.processInfo.arguments.contains(
        "-CanarioMenuAberto")
    @State private var itemDoMenu: ItemDoMenu? = {
        if ProcessInfo.processInfo.arguments.contains("-CanarioAbrirPrivacy") {
            return ItemDoMenu(entrada: .privacidade)
        }
        if ProcessInfo.processInfo.arguments.contains("-CanarioAbrirAccount") {
            return ItemDoMenu(entrada: .conta)
        }
        return nil
    }()

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                navegacaoNativa
            } else {
                navegacaoCompativel
            }
        }
        .overlay { sobreposicoes }
        // O esquema do sistema acompanha o território da aba visível.
        //
        // Ele mora AQUI, e não no modificador `.territorio`, porque
        // `preferredColorScheme` se propaga até a cena: o da raiz ganha do de
        // dentro, e um `.dark` aplicado lá embaixo não conseguia clarear a
        // hora no topo sobre o fundo #0A0B1A.
        //
        // É isto que veste o que token nenhum alcança -- barra de status,
        // indicador de rolagem, `Picker` segmentado -- e é o que faz o app
        // continuar claro no resto, que é a decisão de produto de sempre.
        .preferredColorScheme(aba == .dados ? .dark : .light)
        // O menu não pode ultrapassar a borda e voltar. `.snappy` tem mola:
        // na gravação a 60 fps, a aresta chegou a 849 px e recuou para 845 px,
        // revelando por alguns quadros uma faixa do céu atrás do painel. O
        // `easeOut` preserva o deslizamento e termina exatamente em zero.
        .animation(.easeOut(duration: 0.24), value: menuAberto)
        .fullScreenCover(isPresented: $buscaAberta) {
            Analisar(aoFechar: { buscaAberta = false })
        }
        .fullScreenCover(item: $itemDoMenu) { item in
            TelaDoMenu(entrada: item.entrada)
        }
        .sheet(item: $links.recebida) { peca in
            ReceberPecaCompartilhada(peca: peca)
                .presentationDetents([.medium])
        }
    }

    /// iOS 26 usa o mesmo container do Apple Music. Além do Liquid Glass
    /// automático, a barra encolhe ao rolar e Search recebe o papel semântico
    /// próprio do sistema. Uma barra desenhada à mão nunca reproduz esse gesto.
    @available(iOS 26.0, *)
    private var navegacaoNativa: some View {
        TabView(selection: $aba) {
            Tab(Aba.adicionar.titulo, systemImage: Aba.adicionar.simbolo,
                value: .adicionar) {
                TelaInicialAdicionar(menuAberto: menuAberto,
                                     alternarMenu: { menuAberto.toggle() })
            }
            Tab(Aba.armario.titulo, systemImage: Aba.armario.simbolo,
                value: .armario) {
                MinhasPecas(menuAberto: menuAberto,
                            alternarMenu: { menuAberto.toggle() })
            }
            Tab(Aba.dados.titulo, systemImage: Aba.dados.simbolo,
                value: .dados) {
                Explorar(menuAberto: menuAberto,
                         alternarMenu: { menuAberto.toggle() })
            }
            Tab(Aba.buscar.titulo, systemImage: Aba.buscar.simbolo,
                value: .buscar, role: .search) {
                Analisar()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Tokens.Cor.acao)
    }

    /// iOS 17–25 preserva a navegação compatível. O espaço inferior pertence
    /// somente a esta barra flutuante; a TabView nativa já calcula sua safe area.
    private var navegacaoCompativel: some View {
        // A barra entra como `safeAreaInset`, e não numa `ZStack` com altura
        // reservada na unha. Os 82 pt cravados que existiam aqui não batiam com
        // a altura real -- que muda com Dynamic Type e com o indicador de home
        // de cada aparelho -- e o fim das telas de tendência e de tamanhos
        // ficava escondido atrás dela. Agora o SwiftUI mede a barra e reserva
        // exatamente o que ela ocupa.
        conteudoDaAba
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BarraPrincipal(aba: $aba) { buscaAberta = true }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
    }

    @ViewBuilder
    private var conteudoDaAba: some View {
        switch aba {
        case .adicionar:
            TelaInicialAdicionar(menuAberto: menuAberto,
                                 alternarMenu: { menuAberto.toggle() })
        case .armario:
            MinhasPecas(menuAberto: menuAberto,
                        alternarMenu: { menuAberto.toggle() })
        case .dados:
            Explorar(menuAberto: menuAberto,
                     alternarMenu: { menuAberto.toggle() })
        case .buscar: Analisar()
        }
    }

    @ViewBuilder
    private var sobreposicoes: some View {
        ZStack {
            if menuAberto {
                MenuLateral(
                    fechar: { menuAberto = false },
                    escolher: { entrada in
                        menuAberto = false
                        itemDoMenu = ItemDoMenu(entrada: entrada)
                    })
                // Só o VALOR do ambiente, não o modificador `.territorio`:
                // ele também pinta um fundo de tela cheia, e aqui isso
                // cobriria a aba que o menu deixa à mostra de propósito.
                .environment(\.territorio, aba == .dados ? .mercado : .armario)
                .transition(.move(edge: .leading))
                .zIndex(10)
            }

        }
    }
}
