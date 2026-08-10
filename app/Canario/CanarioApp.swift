import SwiftUI

@main
struct CanarioApp: App {
    var body: some Scene {
        WindowGroup {
            Raiz()
        }
    }
}

/// As abas da §27, emendadas pela A10.
///
/// **O que mudou e por quê.** Os nomes antigos — Analisar, Explorar, Comparar —
/// eram os *verbos que o app executa*, e não as coisas que o usuário tem. A
/// revisão de 03/08 abriu por aí, e o custo apareceu duas linhas depois: *"a
/// tab Comparar tá bem confusa"*. A §27 já dizia que Comparar *"pressupõe peças
/// já analisadas"*, e o app esquecia todas ao trocar de aba — faltava o insumo,
/// não o desenho.
///
/// A ordem segue a do trabalho: **Adicionar** é a entrada, **Armário** guarda o
/// que saiu dela, **Dados** é o mercado (valor de esforço zero na abertura), e
/// **Comparar** fecha.
///
/// **Sobre o nome "Armário" (A11, decisão do JP em 07/08).** Eu tinha chamado
/// de "Minhas peças" para não prometer o que a §34 exclui — closet e
/// monitoramento contínuo por peça. O JP revogou o nome e disse que a função
/// vem depois, com o design da Bianca.
///
/// O nome mudou; a garantia não. `PecaSalva` continua guardando **só o que o
/// usuário digitou** e nenhum número calculado, e `PecasSalvasTests` falha se
/// alguém acrescentar um. Se a função que vier envolver acompanhar a peça ao
/// longo do tempo, a §34 precisa de revogação com consequência de método, e não
/// só de rótulo: a peça do cliente não está no painel e não temos como medi-la.
///
/// `Comparar` ainda é aba própria e a A10 a coloca *dentro* do Armário — ela
/// ainda seleciona termos soltos, que é a origem do *"camisa e branco tá na
/// mesma lista mas são categorias diferentes"* da revisão de 03/08. A dobra vem
/// quando a seleção passar a ser por peça guardada; até lá, tirar a aba seria
/// remover função sem entregar a substituta.
struct Raiz: View {
    /// Qual aba está aberta. Existe para o `TabView` não montar as quatro de
    /// uma vez: sem seleção explícita o SwiftUI podia construir as outras
    /// junto, e cada uma dispara a própria carga -- o Explorar sozinho abre
    /// quatro requisições. Na abertura fria isso viravam mais de dez chamadas
    /// simultâneas contra um projeto free, e o resultado foi o que o JP viu:
    /// tela preta por segundos e `Operation timed out` no Xcode.
    @State private var aba = 0

    var body: some View {
        TabView(selection: $aba) {
            Analisar()
                .tabItem { Label("Adicionar", systemImage: "plus.magnifyingglass") }
                .tag(0)
            MinhasPecas()
                .tabItem { Label("Armário", systemImage: "square.stack.3d.up") }
                .tag(1)
            Explorar()
                .tabItem { Label("Dados", systemImage: "chart.bar.doc.horizontal") }
                .tag(2)
            Comparar()
                .tabItem { Label("Comparar", systemImage: "arrow.left.arrow.right") }
                .tag(3)
        }
    }
}
