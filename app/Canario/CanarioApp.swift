import SwiftUI

@main
struct CanarioApp: App {
    var body: some Scene {
        // A paleta escura experimental de 19/08 nunca passou por revisão de
        // design e, no teste em aparelho, fez o mesmo build parecer outro app.
        // A 1.1 preserva a aparência clara aprovada em todos os iPhones. Quando
        // houver telas escuras desenhadas e validadas, este bloqueio sai daqui.
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("-CanarioUITestCompare") {
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
            .preferredColorScheme(.light)
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

    struct ItemDoMenu: Identifiable {
        let nome: String
        var id: String { nome }
    }

    /// Argumento de inspeção visual: permite abrir o Closet no simulador sem
    /// adicionar um atalho de produto nem disparar consultas das abas ocultas.
    @State private var aba: Aba = ProcessInfo.processInfo.arguments.contains(
        "-CanarioAbrirCloset") ? .armario : .adicionar
    @State private var buscaAberta = false
    @State private var menuAberto = ProcessInfo.processInfo.arguments.contains(
        "-CanarioMenuAberto")
    @State private var itemDoMenu: ItemDoMenu? = ProcessInfo.processInfo.arguments.contains(
        "-CanarioAbrirPrivacy") ? ItemDoMenu(nome: "Privacy") : nil

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                navegacaoNativa
            } else {
                navegacaoCompativel
            }
        }
        .overlay { sobreposicoes }
        .statusBarHidden(aba == .adicionar)
        .animation(.snappy(duration: 0.35), value: menuAberto)
        .fullScreenCover(isPresented: $buscaAberta) {
            Analisar(aoFechar: { buscaAberta = false })
        }
        .fullScreenCover(item: $itemDoMenu) { item in
            TelaDoMenu(nome: item.nome)
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
                TelaInicialAdicionar()
            }
            Tab(Aba.armario.titulo, systemImage: Aba.armario.simbolo,
                value: .armario) {
                MinhasPecas()
            }
            Tab(Aba.dados.titulo, systemImage: Aba.dados.simbolo,
                value: .dados) {
                Explorar()
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
        case .adicionar: TelaInicialAdicionar()
        case .armario: MinhasPecas()
        case .dados: Explorar()
        case .buscar: Analisar()
        }
    }

    @ViewBuilder
    private var sobreposicoes: some View {
        ZStack {
            if menuAberto {
                MenuLateral(
                    fechar: { menuAberto = false },
                    escolher: { item in
                        menuAberto = false
                        itemDoMenu = ItemDoMenu(nome: item)
                    })
                .transition(.move(edge: .leading))
                .zIndex(10)
            }

            // Um único controle troca apenas o símbolo. Assim ellipsis e X
            // ocupam literalmente a mesma coordenada e compartilham a mesma
            // safe area; duas telas nunca mais podem divergir no recuo.
            if aba == .adicionar {
                VStack {
                    HStack {
                        BotaoCircularDoMenu(
                            simbolo: menuAberto ? "xmark" : "ellipsis",
                            acessibilidade: menuAberto ? "Close menu" : "Open menu",
                            acao: { menuAberto.toggle() })
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .zIndex(11)
            }
        }
    }
}
