import SwiftUI
import UIKit

/// Primeira tela do app, construída a partir do fluxo da Bianca e dos ativos do
/// Fadul. O Dynamic Island é o elemento real do iPhone: o app desenha somente
/// o feixe abaixo dele, nunca uma pílula preta falsa.
struct TelaInicialAdicionar: View {
    @State private var termos: [Termo] = []
    @State private var buscandoTermos = false
    @State private var erro: String?
    @State private var importando = false
    @State private var miniaturas: [UIImage] = []

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

        }
        .sheet(isPresented: $importando, onDismiss: carregarMiniaturas) {
            ImportarPeca(termos: termos)
        }
        // O Figma é uma experiência de entrada imersiva; o Dynamic Island
        // permanece físico, mas relógio/sinal não competem com menu e feixe.
        .task {
            carregarMiniaturas()
            // Prepara o formulário depois que o primeiro frame já apareceu.
            // Não há spinner nem dependência de rede para abrir a Home.
            try? await Task.sleep(for: .seconds(1))
            async let termos = CatalogoDeTermos.shared.carregar()
            async let indices = CatalogoDeIndices.shared.carregar()
            _ = try? await (termos, indices)
        }
    }

    /// Fotos reais das duas peças mais recentes. Sem peça salva, não desenha
    /// placeholder: o PDF mostrava apenas uma simulação do comportamento.
    @ViewBuilder
    private var miniaturasRecentes: some View {
        GeometryReader { geo in
            if let esquerda = miniaturas.first {
                Image(uiImage: esquerda)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 132, height: 242)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .blur(radius: 5)
                    .opacity(0.56)
                    .offset(x: -74, y: geo.size.height * 0.39)
                    .accessibilityHidden(true)
            }
            if miniaturas.count > 1 {
                Image(uiImage: miniaturas[1])
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
            termos = try await CatalogoDeTermos.shared.carregar()
        } catch {
            self.erro = "Could not load the taxonomy."
        }
    }

    private func carregarMiniaturas() {
        Task { @MainActor in
            let todas = await PecasSalvas.shared.todas()
            var imagens: [UIImage] = []
            // Itens antigos podem não ter foto. Procurar até achar duas evita
            // esconder as imagens só porque as peças mais novas são legadas.
            for peca in todas {
                if let dados = await PecasSalvas.shared.miniatura(de: peca),
                   let imagem = await MiniaturaParaTela.imagem(de: dados) {
                    imagens.append(imagem)
                    if imagens.count == 2 { break }
                }
            }
            miniaturas = imagens
        }
    }
}

/// Liquid Glass verdadeiro no iOS 26 e fallback compatível no iOS 17–25.
/// `ultraThinMaterial` não refrata nem reage como a API nova; por isso ele fica
/// restrito aos aparelhos em que Liquid Glass não existe.
struct Vidro<S: InsettableShape>: View {
    let forma: S

    init(forma: S) { self.forma = forma }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                forma
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: forma)
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        ZStack {
            forma.fill(.ultraThinMaterial)
            forma.fill(LinearGradient(
                colors: [.white.opacity(0.46), .white.opacity(0.10),
                         Tokens.Cor.ceu.opacity(0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            forma.stroke(LinearGradient(
                colors: [.white, .white.opacity(0.42),
                         Tokens.Cor.azulMarca.opacity(0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.25)
            forma.inset(by: 2).stroke(.white.opacity(0.28), lineWidth: 0.75)
        }
        .compositingGroup()
        .shadow(color: .white.opacity(0.35), radius: 2, x: -1, y: -1)
        .shadow(color: Tokens.Cor.azulMarca.opacity(0.26), radius: 18, y: 9)
    }
}

extension Vidro where S == RoundedRectangle {
    init(raio: CGFloat) {
        self.init(forma: RoundedRectangle(cornerRadius: raio, style: .continuous))
    }
}
