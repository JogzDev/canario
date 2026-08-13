import SwiftUI
import UIKit

/// Primeira tela do app, construída a partir do fluxo da Bianca e dos ativos do
/// Fadul. O Dynamic Island é o elemento real do iPhone: o app desenha somente
/// o feixe abaixo dele, nunca uma pílula preta falsa.
struct TelaInicialAdicionar: View {
    let abrirMenu: () -> Void

    @State private var termos: [Termo] = []
    @State private var buscandoTermos = false
    @State private var erro: String?
    @State private var importando = false
    @State private var miniaturas: [Data] = []

    var body: some View {
        ZStack {
            Tokens.Cor.ceu.ignoresSafeArea()

            Image("Spotlight")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 545, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)

            miniaturasRecentes

            VStack(spacing: 12) {
                Spacer().frame(height: 188)
                Text("Add your clothes")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Tokens.Cor.azulMarca)

                Button { abrirImportacao() } label: {
                    ZStack {
                        Vidro(raio: 28)
                        Image("AddMannequin")
                            .resizable()
                            .scaledToFit()
                            .padding(.vertical, 14)
                    }
                    .frame(width: 232, height: 262)
                }
                .buttonStyle(.plain)
                .disabled(buscandoTermos)
                .accessibilityLabel("Add a clothing item")

                if buscandoTermos {
                    ProgressView().tint(Tokens.Cor.azulMarca)
                } else {
                    Text("Tap to add")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Tokens.Cor.azulMarca.opacity(0.78))
                }

                if let erro {
                    Button("Try again") { abrirImportacao() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Tokens.Cor.azulMarca)
                        .accessibilityHint(erro)
                }
                Spacer(minLength: 100)
            }

            VStack {
                HStack {
                    Button(action: abrirMenu) {
                        ZStack {
                            Vidro(forma: Circle())
                            Image(systemName: "ellipsis")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Tokens.Cor.noite)
                        }
                        .frame(width: 62, height: 62)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open menu")
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .sheet(isPresented: $importando, onDismiss: carregarMiniaturas) {
            ImportarPeca(termos: termos)
        }
        // O Figma é uma experiência de entrada imersiva; o Dynamic Island
        // permanece físico, mas relógio/sinal não competem com menu e feixe.
        .statusBarHidden(true)
        .task {
            carregarMiniaturas()
            await carregarTermos()
        }
    }

    /// Fotos reais das duas peças mais recentes. Sem peça salva, não desenha
    /// placeholder: o PDF mostrava apenas uma simulação do comportamento.
    @ViewBuilder
    private var miniaturasRecentes: some View {
        GeometryReader { geo in
            if let esquerda = miniaturas.first,
               let imagem = UIImage(data: esquerda) {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 132, height: 242)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .blur(radius: 5)
                    .opacity(0.56)
                    .offset(x: -74, y: geo.size.height * 0.39)
                    .accessibilityHidden(true)
            }
            if miniaturas.count > 1, let imagem = UIImage(data: miniaturas[1]) {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 132, height: 242)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .blur(radius: 5)
                    .opacity(0.56)
                    .offset(x: geo.size.width - 58, y: geo.size.height * 0.39)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }

    private func abrirImportacao() {
        erro = nil
        if !termos.isEmpty {
            importando = true
            return
        }
        Task {
            await carregarTermos()
            if !termos.isEmpty { importando = true }
        }
    }

    @MainActor
    private func carregarTermos() async {
        guard termos.isEmpty, !buscandoTermos else { return }
        buscandoTermos = true
        defer { buscandoTermos = false }
        do {
            termos = try await Supabase.shared.buscar(
                "termos",
                "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca,palavras_pt,palavras_en&order=dimensao,id")
        } catch {
            self.erro = "Could not load the taxonomy."
        }
    }

    private func carregarMiniaturas() {
        Task { @MainActor in
            let todas = await PecasSalvas.shared.todas()
            var dados: [Data] = []
            // Itens antigos podem não ter foto. Procurar até achar duas evita
            // esconder as imagens só porque as peças mais novas são legadas.
            for peca in todas {
                if let imagem = await PecasSalvas.shared.miniatura(de: peca) {
                    dados.append(imagem)
                    if dados.count == 2 { break }
                }
            }
            miniaturas = dados
        }
    }
}

/// Material nativo do iOS 17, com borda e reflexo. Mantém a linguagem de vidro
/// sem depender da API `glassEffect`, que só existe em SDK posterior ao alvo.
struct Vidro<S: InsettableShape>: View {
    let forma: S

    init(forma: S) { self.forma = forma }

    var body: some View {
        forma
            .fill(.ultraThinMaterial)
            .overlay {
                forma.stroke(
                    LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
            .shadow(color: Tokens.Cor.azulMarca.opacity(0.2), radius: 16, y: 8)
    }
}

extension Vidro where S == RoundedRectangle {
    init(raio: CGFloat) {
        self.init(forma: RoundedRectangle(cornerRadius: raio, style: .continuous))
    }
}
