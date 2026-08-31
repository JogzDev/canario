import SwiftUI

/// A curva de tamanhos (§24) — **marco de demo 1**.
///
/// É o achado que a cliente relatou em entrevista, devolvido quantificado: onde
/// a grade quebra ao longo da escada de tamanhos.
///
/// A tela mostra a taxa por tamanho, o formato da quebra e as ressalvas — que
/// aqui não são rodapé, são condição de uso do número.
struct CurvaDeTamanhosView: View {
    /// Nulo = o painel inteiro. Preenchido = a curva daquele atributo.
    var termo: Termo?

    @State private var porRotulo: [CurvaDeTamanhos.Faixa] = []
    @State private var porFaixa: [CurvaDeTamanhos.Faixa] = []
    @State private var carregando = true
    @State private var erro: String?

    var body: some View {
        Group {
            if carregando {
                Carregando()
            } else if let erro {
                FalhaDeRede(mensagem: erro) { Task { await carregar() } }
            } else if !temCobertura {
                ScrollView {
                    ContentUnavailableView(
                        "Size mapping unavailable",
                        systemImage: "ruler",
                        description: Text("No current size curve was returned for this selection."))
                        .padding(.top, Tokens.Espaco.g)
                }
            } else {
                conteudo
            }
        }
        // Mesmo motivo do relatório do termo: ela é aberta de dois lugares, e
        // um deles não declarava o território. Quem só existe no mercado diz
        // isso de si mesma.
        .territorio(.mercado)
        .navigationTitle(termo == nil ? "Size availability" : "Sizes · \(Traducao.rotuloExibido(termo!))")
        .navigationBarTitleDisplayMode(.inline)
        .navegacaoDoMercado()
        .task { await carregar() }
    }

    /// Uma linha por tamanho. O banco guarda por (faixa, rótulo) e o mesmo
    /// rótulo cai em faixas diferentes conforme o formato da grade.
    private var tamanhos: [CurvaDeTamanhos.Faixa] {
        CurvaDeTamanhos.consolidar(porRotulo)
    }

    private var emRisco: Int { tamanhos.reduce(0) { $0 + $1.nEmRisco } }
    private var temCobertura: Bool { emRisco >= CurvaDeTamanhos.minimoEmRisco }

    private var conteudo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                manchete
                barras
                formatoDaQuebra
                ressalvas
            }
            .padding(Tokens.Espaco.m)
        }
    }

    private var manchete: some View {
        Cartao {
            Text("What panel sizing is showing").font(Tokens.Fonte.secao)
            if let frase = CurvaDeTamanhos.manchete(porRotulo: tamanhos) {
                Text(frase).font(Tokens.Fonte.corpo)
            } else {
                Text("No size stood out in this window.").font(Tokens.Fonte.corpo)
            }
            LinhaInsumo(texto: CurvaDeTamanhos.insumo(tamanhos))
        }
    }

    /// A curva propriamente dita. Barra horizontal por tamanho, na ordem em que
    /// a grade existe — do menor para o maior.
    private var barras: some View {
        let linhas = CurvaDeTamanhos.emOrdem(tamanhos)
        let maximo = linhas.compactMap(\.taxaQuebra).max() ?? 1
        let lideres = CurvaDeTamanhos.lideres(linhas)
        return Cartao {
            Text("Availability loss by size").font(Tokens.Fonte.secao)
            Text("Of the sizes available when the window opened, how many became unavailable.")
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            ForEach(linhas) { linha in
                BarraDeTamanho(linha: linha, maximo: maximo,
                               destacado: lideres.contains(linha.rotulo ?? ""))
            }
        }
    }

    private var formatoDaQuebra: some View {
        let menores = porFaixa.first { $0.faixa == "menores" }
        let maiores = porFaixa.first { $0.faixa == "maiores" }
        return Group {
            if let frase = CurvaDeTamanhos.formato(menores: menores, maiores: maiores) {
                Cartao {
                    Text("Shape of the break").font(Tokens.Fonte.secao)
                    Text(frase).font(Tokens.Fonte.corpo)
                    if let m = menores, let g = maiores {
                        LinhaInsumo(texto: "Smaller sizes: \(m.nQuebrou) of \(m.nEmRisco). Larger sizes: \(g.nQuebrou) of \(g.nEmRisco).")
                    }
                }
            }
        }
    }

    private var ressalvas: some View {
        Cartao {
            Text("Before using this").font(Tokens.Fonte.secao)
            ForEach(CurvaDeTamanhos.ressalvas, id: \.self) { LinhaInsumo(texto: $0) }
        }
    }

    private func carregar() async {
        carregando = true
        erro = nil
        // A escada de letra é a que o painel tem em maior volume e a única em
        // que dá para NOMEAR o tamanho sem misturar sentido entre marcas.
        let filtroTermo = termo.map { "termo_id=eq.\($0.id)" } ?? "termo_id=is.null"
        do {
            async let r: [CurvaDeTamanhos.Faixa] = Supabase.shared.buscar(
                "curva_tamanhos",
                "select=*&\(filtroTermo)&sistema=eq.letra&rotulo=not.is.null&order=semana.desc&limit=60")
            async let f: [CurvaDeTamanhos.Faixa] = Supabase.shared.buscar(
                "curva_tamanhos",
                "select=*&\(filtroTermo)&sistema=eq.letra&rotulo=is.null&order=semana.desc&limit=20")

            // Só a semana mais recente; a tabela guarda histórico.
            let todasR = try await r
            let semana = todasR.map(\.semana).max()
            porRotulo = todasR.filter { $0.semana == semana }
            porFaixa = (try await f).filter { $0.semana == semana }
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}

/// Uma barra por tamanho. §32: nunca comunica por cor sozinha — o número vai
/// junto, e a ordem da escada carrega a leitura.
///
/// **A cor e o destaque mudaram em 29/08.** O verde de `Tokens.Cor.alta` não é
/// deste app -- o JP já tinha vetado a mesma cor no painel da peça: *"esse
/// verde não encaixa com a identidade do app"* --, e o verde ainda era pintado
/// sobre tokens claros, num gráfico que hoje abre em território de mercado. O
/// destaque agora sai de `CurvaDeTamanhos.lideres`, que respeita a margem de
/// erro e portanto concorda com a manchete acima do gráfico.
///
struct BarraDeTamanho: View {
    let linha: CurvaDeTamanhos.Faixa
    let maximo: Double
    var destacado: Bool = false
    @Environment(\.territorio) private var territorio

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(linha.rotulo ?? "—")
                    .font(Tokens.Fonte.corpo.weight(.semibold))
                    .frame(width: 34, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // O trilho é a BORDA do território, não a superfície:
                        // no escuro a superfície é a cor do próprio cartão, e
                        // a barra vazia sumiria dentro dele.
                        RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta)
                            .fill(Tokens.Cor.bordaDo(territorio))
                        RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta)
                            .fill(destacado ? Tokens.Cor.acentoDo(territorio)
                                            : Tokens.Cor.tintaFracaDo(territorio))
                            .frame(width: max(4, geo.size.width * proporcao))
                    }
                }
                .frame(height: 18)
                Text("\(Leitura.numero(linha.taxaQuebra ?? 0, casas: 1))%")
                    .font(Tokens.Fonte.numero)
                    .frame(width: 58, alignment: .trailing)
            }
            LinhaInsumo(texto: "\(linha.nQuebrou) of \(linha.nEmRisco) became unavailable")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Size \(linha.rotulo ?? ""), \(Leitura.numero(linha.taxaQuebra ?? 0, casas: 1)) percent, \(linha.nQuebrou) of \(linha.nEmRisco)")
    }

    private var proporcao: Double {
        guard maximo > 0, let t = linha.taxaQuebra else { return 0 }
        return min(1, t / maximo)
    }
}
