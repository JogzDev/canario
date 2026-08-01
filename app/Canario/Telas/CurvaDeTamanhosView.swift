import SwiftUI

/// A curva de tamanhos (§24) — **marco de demo 1**.
///
/// É o achado que a cliente relatou em entrevista, devolvido quantificado: onde
/// a grade quebra ao longo da escada de tamanhos.
///
/// A tela mostra a taxa por tamanho, o formato da quebra, a composição sugerida
/// (soma zero, que é o único tipo de recomendação que a §24 autoriza) e as
/// ressalvas — que aqui não são rodapé, são condição de uso do número.
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
                    CoberturaInsuficiente(
                        titulo: "Cobertura insuficiente para a curva",
                        explicacao: "São \(emRisco) tamanhos em risco nesta seleção, e o mínimo é \(CurvaDeTamanhos.minimoEmRisco). Abaixo disso a taxa oscila demais para ser lida.",
                        oQueTem: "A base cresce a cada noite de coleta.")
                    .padding(Tokens.Espaco.m)
                }
            } else {
                conteudo
            }
        }
        .navigationTitle(termo == nil ? "Curva de tamanhos" : "Tamanhos · \(termo!.rotulo)")
        .navigationBarTitleDisplayMode(.inline)
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
                composicao
                ressalvas
            }
            .padding(Tokens.Espaco.m)
        }
    }

    private var manchete: some View {
        Cartao {
            Text("O que a grade do painel está dizendo").font(Tokens.Fonte.secao)
            if let frase = CurvaDeTamanhos.manchete(porRotulo: tamanhos) {
                Text(frase).font(Tokens.Fonte.corpo)
            } else {
                Text("Nenhum tamanho se destacou nesta janela.").font(Tokens.Fonte.corpo)
            }
            LinhaInsumo(texto: CurvaDeTamanhos.insumo(tamanhos))
        }
    }

    /// A curva propriamente dita. Barra horizontal por tamanho, na ordem em que
    /// a grade existe — do menor para o maior.
    private var barras: some View {
        let linhas = CurvaDeTamanhos.emOrdem(tamanhos)
        let maximo = linhas.compactMap(\.taxaQuebra).max() ?? 1
        return Cartao {
            Text("Taxa de saída por tamanho").font(Tokens.Fonte.secao)
            Text("Dos tamanhos que estavam disponíveis quando a janela abriu, quantos ficaram indisponíveis.")
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            ForEach(linhas) { linha in
                BarraDeTamanho(linha: linha, maximo: maximo)
            }
        }
    }

    private var formatoDaQuebra: some View {
        let menores = porFaixa.first { $0.faixa == "menores" }
        let maiores = porFaixa.first { $0.faixa == "maiores" }
        return Group {
            if let frase = CurvaDeTamanhos.formato(menores: menores, maiores: maiores) {
                Cartao {
                    Text("Formato da quebra").font(Tokens.Fonte.secao)
                    Text(frase).font(Tokens.Fonte.corpo)
                    if let m = menores, let g = maiores {
                        LinhaInsumo(texto: "Menores: \(m.nQuebrou) de \(m.nEmRisco). Maiores: \(g.nQuebrou) de \(g.nEmRisco).")
                    }
                }
            }
        }
    }

    /// §24: composição de grade é permitida (soma zero); volume, nunca.
    private var composicao: some View {
        Group {
            if let frase = CurvaDeTamanhos.composicao(porRotulo: tamanhos) {
                Cartao {
                    Text("Composição de grade").font(Tokens.Fonte.secao)
                    Text(frase).font(Tokens.Fonte.corpo)
                }
            }
        }
    }

    private var ressalvas: some View {
        Cartao {
            Text("Antes de usar isto").font(Tokens.Fonte.secao)
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
struct BarraDeTamanho: View {
    let linha: CurvaDeTamanhos.Faixa
    let maximo: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(linha.rotulo ?? "—")
                    .font(Tokens.Fonte.corpo.weight(.semibold))
                    .frame(width: 34, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta)
                            .fill(Tokens.Cor.superficie)
                        RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta)
                            .fill(destaque ? Tokens.Cor.alta : Tokens.Cor.tintaFraca)
                            .frame(width: max(4, geo.size.width * proporcao))
                    }
                }
                .frame(height: 18)
                Text("\(Leitura.numero(linha.taxaQuebra ?? 0, casas: 1))%")
                    .font(Tokens.Fonte.numero)
                    .frame(width: 58, alignment: .trailing)
            }
            LinhaInsumo(texto: "\(linha.nQuebrou) de \(linha.nEmRisco) saíram de linha")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tamanho \(linha.rotulo ?? ""), \(Leitura.numero(linha.taxaQuebra ?? 0, casas: 1)) por cento, \(linha.nQuebrou) de \(linha.nEmRisco)")
    }

    private var proporcao: Double {
        guard maximo > 0, let t = linha.taxaQuebra else { return 0 }
        return min(1, t / maximo)
    }

    private var destaque: Bool {
        guard let t = linha.taxaQuebra, maximo > 0 else { return false }
        return t >= maximo - 0.0001
    }
}
