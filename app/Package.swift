// swift-tools-version: 5.9
import PackageDescription

// Pacote só da LÓGICA PURA do app, para os testes rodarem em macOS sem
// depender de simulador — que é o que permite testar a cada commit, inclusive
// no CI, sem precisar de iOS booted.
//
// Os mesmos arquivos são compilados no alvo do app pelo Canario.xcodeproj; aqui
// não há duplicação de código, só um segundo jeito de compilá-los.
//
// SwiftUI fica de fora de propósito: tela se verifica olhando, lógica se
// verifica testando.
let package = Package(
    name: "CanarioLogica",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CanarioLogica",
            path: "Canario",
            sources: ["Rede/Traducao.swift", "Rede/Modelos.swift", "Rede/Supabase.swift",
                      "Rede/CorDaPeca.swift", "Rede/LeitorDeArquivo.swift",
                      "Rede/Importacao.swift", "Rede/Explicacao.swift",
                      "Rede/CurvaDeTamanhos.swift", "Rede/Similares.swift",
                      "Rede/Cluster.swift", "Rede/SemelhancaVisual.swift",
                      "Rede/PecasSalvas.swift",
                      "Design/Formato.swift"]
        ),
        .testTarget(
            name: "CanarioLogicaTests",
            dependencies: ["CanarioLogica"],
            path: "Testes"
        ),
    ]
)
