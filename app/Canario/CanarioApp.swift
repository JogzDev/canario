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
        case adicionar, armario, dados
    }

    struct ItemDoMenu: Identifiable {
        let nome: String
        var id: String { nome }
    }

    @State private var aba: Aba = .adicionar
    @State private var buscaAberta = false
    @State private var menuAberto = ProcessInfo.processInfo.arguments.contains(
        "-CanarioMenuAberto")
    @State private var itemDoMenu: ItemDoMenu?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch aba {
                case .adicionar:
                    TelaInicialAdicionar { menuAberto = true }
                case .armario:
                    MinhasPecas()
                case .dados:
                    Explorar()
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 82)
            }

            BarraPrincipal(aba: $aba) { buscaAberta = true }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

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
        }
        .animation(.snappy(duration: 0.35), value: menuAberto)
        .fullScreenCover(isPresented: $buscaAberta) {
            Analisar(aoFechar: { buscaAberta = false })
        }
        .alert(item: $itemDoMenu) { item in
            Alert(
                title: Text(item.nome),
                message: Text("This section is part of the approved navigation and will be connected in the next product pass."),
                dismissButton: .default(Text("OK")))
        }
    }
}
