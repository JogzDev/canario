import SwiftUI

/// Aba **Analisar** (§27): entrada por busca textual.
///
/// A §11 é explícita: "a barra de busca do app nunca vira filtro de texto cru".
/// A string do usuário é traduzida para termos da taxonomia via rótulos,
/// sinônimos e as mesmas palavras que o coletor usa; o que não casar gera
/// resposta honesta, em vez de silêncio ou de resultado vazio.
struct Analisar: View {
    var aoFechar: (() -> Void)?
    @State private var termos: [Termo] = []
    @State private var texto = ""
    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var carregando = true
    @State private var erro: String?

    /// A tradução vive em `Traducao`, que é testada. Aqui a tela só consome.
    private var casados: [Termo] {
        Traducao.termos(para: texto, em: termos)
    }

    /// Quando a busca descreve uma peça, e não um atributo isolado.
    private var descreveUmaPeca: Bool {
        Set(casados.map(\.dimensao)).count >= 2
    }

    private var descricaoDaBusca: String {
        Traducao.descricaoAmigavel(casados, consulta: texto)
    }

    // Cores do gradiente de fundo
    private let azulBase = Tokens.Cor.ceuFixo
    private let azulMaisClaro = Color(red: 212/255, green: 239/255, blue: 244/255)
    private let corLinha = Color.white.opacity(0.65)

    var body: some View {
        NavigationStack {
            ZStack {
                // Fundo com degradê suave do azul base para um azul mais branquinho
                LinearGradient(
                    colors: [azulBase, azulMaisClaro],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Ondas em SVG centralizadas e com largura de 410 pt
                Image("SVG Background Search")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 410)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .ignoresSafeArea()

                Group {
                    if carregando {
                        Carregando()
                    } else if let erro {
                        FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                    } else {
                        conteudo
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $texto,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search by garment, fabric, cut, pattern…")
            .toolbar {
                if let aoFechar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: aoFechar)
                    }
                }
            }
        }
        .task { await carregar() }
        // A busca é `fullScreenCover` da `Raiz` e abre de QUALQUER aba,
        // inclusive da Trends -- e a Trends deixa a cena em escuro. Como esta
        // tela pinta o próprio fundo em #BBE5ED, sem declarar o esquema ela
        // herdava tinta clara sobre fundo claro. É o mesmo defeito dos prints
        // do Profile e do Q&A, só que numa tela que ninguém tinha aberto por
        // esse caminho ainda.
        .territorio(.armario)
    }

    @ViewBuilder
    private var conteudo: some View {
        if texto.isEmpty {
            abertura
        } else if casados.isEmpty {
            ScrollView {
                CoberturaInsuficiente(
                    titulo: "This term isn't tracked yet",
                    explicacao: "“\(texto)” is outside the reviewed vocabulary, so there is no market reading for it yet.",
                    oQueTem: frase("Try: \(sugestoes.joined(separator: ", "))")
                )
                .padding(Tokens.Espaco.m)
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    if descreveUmaPeca {
                        cardPecaCombinada
                    }

                    cardAtributos
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }

    /// Estado vazio com textos dentro de uma pílula translúcida centralizada na tela
    private var abertura: some View {
        VStack {
            Spacer()

            VStack(spacing: 6) {
                Text("Search by garment, fabric, cut, pattern…")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Text(frase("Try: \(sugestoes.prefix(3).joined(separator: ", "))"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.80))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.85), Color.white.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Card de leitura combinada (Liquid Glass)
    private var cardPecaCombinada: some View {
        NavigationLink {
            RelatorioDaPeca(termos: casados, pecaSalva: nil,
                           descricaoAmigavel: descricaoDaBusca)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(descricaoDaBusca)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Rectangle()
                    .fill(corLinha)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Combined reading")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))

                    Text(leituraCombinadaFormatada)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(18)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    /// Card de atributos individuais com linhas e pílulas
    private var cardAtributos: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(descreveUmaPeca ? "By attribute" : "Attributes")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            VStack(spacing: 0) {
                ForEach(Array(casados.enumerated()), id: \.element.id) { index, termo in
                    NavigationLink {
                        RelatorioDoTermo(termo: termo)
                    } label: {
                        LinhaTermoGlass(
                            termo: termo,
                            indice: indices[termo.id],
                            rotulo: Traducao.rotuloAmigavel(termo, na: texto)
                        )
                    }
                    .buttonStyle(.plain)

                    if index < casados.count - 1 {
                        Rectangle()
                            .fill(corLinha)
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .background(cardBackground)
    }

    private var leituraCombinadaFormatada: String {
        let leituras = casados.compactMap { indices[$0.id]?.indice }
        guard !leituras.isEmpty else { return "--" }
        let media = leituras.reduce(0, +) / Double(leituras.count)
        let sinal = media >= 0 ? "+" : ""
        return String(format: "\(sinal)%.2f", media).replacingOccurrences(of: ".", with: ",")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.85), Color.white.opacity(0.50)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var sugestoes: [String] {
        var vistas = Set<String>()
        return termos.filter { vistas.insert($0.dimensao).inserted }
            .prefix(5).map(Traducao.rotuloExibido)
    }

    private func carregar() async {
        carregando = true
        erro = nil
        do {
            async let t = CatalogoDeTermos.shared.carregar()
            async let i = CatalogoDeIndices.shared.carregar()
            termos = try await t
            carregando = false
            let recentes = try await i
            indices = SelecaoDeEstado.porTermo(recentes)
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}

/// Linha de atributo no padrão Figma / Liquid Glass com pílula de status
struct LinhaTermoGlass: View {
    let termo: Termo
    let indice: IndiceSemanal?
    var rotulo: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(rotulo ?? Traducao.rotuloExibido(termo))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)

                    if let valor = indice?.indice {
                        Text(formatarIndice(valor))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                if let indice {
                    pilulaGenerica(para: indice)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func pilulaGenerica(para indice: IndiceSemanal) -> some View {
        if let valor = indice.indice {
            if valor >= 1.0 {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 10, weight: .bold))
                    Text("Far Above the usual range")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.52, green: 0.85, blue: 0.38).opacity(0.85), in: Capsule())
            } else if valor > 0.3 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Above the usual range")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.18, green: 0.40, blue: 0.15))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.65, green: 0.90, blue: 0.55).opacity(0.85), in: Capsule())
            } else if valor < -1.0 {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 10, weight: .bold))
                    Text("Far Below the usual range")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.60, green: 0.10, blue: 0.10))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.95, green: 0.50, blue: 0.50).opacity(0.85), in: Capsule())
            } else if valor < -0.3 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Below the usual range")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.55, green: 0.15, blue: 0.15))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.95, green: 0.65, blue: 0.65).opacity(0.85), in: Capsule())
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "equal")
                        .font(.system(size: 10, weight: .bold))
                    Text("Within the usual range")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.primary.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.55).opacity(0.35), in: Capsule())
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "equal")
                    .font(.system(size: 10, weight: .bold))
                Text("Within the usual range")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.primary.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(white: 0.55).opacity(0.35), in: Capsule())
        }
    }

    private func formatarIndice(_ valor: Double) -> String {
        let sinal = valor >= 0 ? "+" : ""
        return String(format: "\(sinal)%.2f", valor)
    }
}
