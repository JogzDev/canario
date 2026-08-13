import SwiftUI

@main
struct CanarioApp: App {
    var body: some Scene {
        WindowGroup { Raiz() }
    }
}

/// Navegação principal aprovada no fluxo de 12/08: Add · Closet · Analytics,
/// com busca separada. Só a aba visível existe na árvore, preservando o ganho
/// de performance da A14 (as consultas das telas ocultas não disparam juntas).
struct Raiz: View {
    enum Aba: String {
        case adicionar, armario, dados, buscar
    }

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
            Tab("Add", systemImage: "hanger", value: .adicionar) {
                TelaInicialAdicionar()
            }
            Tab("Closet", systemImage: "tshirt.fill", value: .armario) {
                MinhasPecas()
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: .dados) {
                Explorar()
            }
            Tab("Search", systemImage: "magnifyingglass", value: .buscar, role: .search) {
                Analisar()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Tokens.Cor.acao)
    }

    /// iOS 17–25 preserva a navegação compatível. O espaço inferior pertence
    /// somente a esta barra flutuante; a TabView nativa já calcula sua safe area.
    private var navegacaoCompativel: some View {
        ZStack(alignment: .bottom) {
            conteudoDaAba
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 82)
                }

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
