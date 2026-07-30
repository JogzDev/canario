import SwiftUI

@main
struct CanarioApp: App {
    var body: some Scene {
        WindowGroup {
            Raiz()
        }
    }
}

/// As três abas da §27. A ordem é a do documento: Analisar primeiro, porque é
/// a entrada de trabalho; Explorar no meio, porque é valor de esforço zero;
/// Comparar por último, porque pressupõe peças já analisadas.
struct Raiz: View {
    var body: some View {
        TabView {
            Analisar()
                .tabItem { Label("Analisar", systemImage: "magnifyingglass") }
            Explorar()
                .tabItem { Label("Explorar", systemImage: "square.grid.2x2") }
            Comparar()
                .tabItem { Label("Comparar", systemImage: "arrow.left.arrow.right") }
        }
    }
}
