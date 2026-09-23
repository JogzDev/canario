import SwiftUI

/// A primeira aba do Seam: o que mudou no mercado observado, com a prova.
///
/// Substitui a "Tendências" da 1.x. Três regras que vêm do plano de 17/09 e
/// da conversa com o JP em 22–23/09:
///
/// - A manchete sai da PROPORÇÃO do catálogo que se mexeu, não da contagem
///   bruta (`DadosDaSemana.historia`). A foto mostra as peças do achado, não a
///   campanha de uma marca: foto sim, anúncio não.
/// - A frase lidera e o número explica (`LinhaDeAtributo`).
/// - O período e a idade do dado estão sempre na tela. Coleta atrasada é dita,
///   nunca apresentada como "agora".
struct EstaSemana: View {
    var abrirConta: () -> Void = {}
    @StateObject private var dados = DadosDaSemana()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                    if #unavailable(iOS 26.0), let periodo { Text(periodo).font(.footnote).foregroundStyle(.secondary) }
                    avisos
                    conteudo
                }
                .padding(.horizontal, Edicao.margem)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .papelDaEdicao()
            .navigationTitle(Text("This week"))
            .subtituloDaEdicao(periodo)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: abrirConta) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel(Text("Account"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { Comparar() } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .accessibilityLabel(Text("Compare attributes"))
                }
            }
            .refreshable { await dados.carregar() }
            .task { await dados.carregar() }
        }
        .tint(Edicao.bordo)
    }

    /// O carimbo da janela: de quando até quando, e há quanto tempo terminou.
    private var periodo: String? {
        dados.resumos["reposicao"].flatMap(ResumoDeEventos.janela)
    }

    @ViewBuilder private var avisos: some View {
        if let aviso = dados.avisoDeCache {
            Label(aviso, systemImage: "wifi.slash")
                .font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(dados.avisos, id: \.self) { aviso in
            Label(aviso, systemImage: "exclamationmark.circle")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var conteudo: some View {
        let reposicao = dados.historia("reposicao")
        let remarcacao = dados.historia("remarcacao", evitando: reposicao?.marca.marca)
        if let erro = dados.erro, dados.resumos.isEmpty {
            ContentUnavailableView {
                Label("This week could not load", systemImage: "wifi.slash")
            } description: {
                Text(erro)
            } actions: {
                Button("Try again") { Task { await dados.carregar() } }
            }
        } else if dados.carregandoEventos && dados.resumos.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 280)
        } else {
            if let reposicao { CapaDaHistoria(historia: reposicao, grande: true) }
            if let remarcacao { CapaDaHistoria(historia: remarcacao, grande: false) }
            // "Nada se mexeu" só é afirmação quando os movimentos CARREGARAM.
            // Falha de rede não pode virar mercado parado.
            if reposicao == nil && remarcacao == nil && !dados.carregandoEventos
                && !dados.resumos.isEmpty {
                Folha {
                    CabecalhoDaFolha(titulo: Text("No store movement in this window"),
                                     nota: frase("The collection ran, and no monitored brand restocked or cut prices in the period above."))
                }
            }
            folhaDaBusca
            if !dados.manchetes.isEmpty {
                CartaoDeImprensaDaEdicao(manchetes: Array(dados.manchetes.prefix(4)))
            }
            prateleira(usadas: Set([reposicao?.marca.marca, remarcacao?.marca.marca].compactMap { $0 }))
        }
    }

    // MARK: Busca

    @ViewBuilder private var folhaDaBusca: some View {
        let linhas = Array(dados.buscaDaSemana.prefix(6))
        if !linhas.isEmpty {
            Folha(espaco: 4) {
                CabecalhoDaFolha(
                    titulo: Text("What Brazil is searching"),
                    nota: dados.semanaDaBusca.map {
                        frase("Google searches in Brazil, each term against its own last 12 weeks. Week of \(Formato.data($0)).")
                    },
                    simbolo: "magnifyingglass")
                    .padding(.bottom, 6)
                ForEach(Array(linhas.enumerated()), id: \.element.termoId) { i, ponto in
                    Group {
                        if let termo = dados.termo(ponto.termoId) {
                            NavigationLink { RelatorioDoTermo(termo: termo) } label: {
                                linha(ponto, destacar: i == 0)
                            }
                            .buttonStyle(.plain)
                        } else {
                            linha(ponto, destacar: i == 0)
                        }
                    }
                    if i < linhas.count - 1 { CosturaDaEdicao() }
                }
            }
        }
    }

    private func linha(_ ponto: PontoSerie, destacar: Bool) -> some View {
        LinhaDeAtributo(termoId: ponto.termoId,
                        rotulo: dados.rotulo(ponto.termoId),
                        dimensao: dados.dimensao(ponto.termoId),
                        leitura: ponto.z,
                        serie: dados.serieDeBusca(ponto.termoId),
                        destacar: destacar,
                        abre: dados.termo(ponto.termoId) != nil)
    }

    // MARK: Prateleira

    @ViewBuilder private func prateleira(usadas: Set<String>) -> some View {
        let marcas = dados.prateleira("reposicao", sem: usadas)
        if !marcas.isEmpty, let resposta = dados.resumos["reposicao"] {
            VStack(alignment: .leading, spacing: 12) {
                Text("Also back in stock")
                    .font(Edicao.Tipo.secao)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(marcas) { marca in
                            NavigationLink {
                                MovimentosDaMarca(marca: marca, tipo: "reposicao", resposta: resposta)
                            } label: {
                                CartaoDaPrateleira(marca: marca)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
    }
}

// MARK: - Capa

/// Uma história da semana: as peças do achado, a manchete e o porquê.
struct CapaDaHistoria: View {
    let historia: DadosDaSemana.Historia
    let grande: Bool

    private var ehReposicao: Bool { historia.tipo == "reposicao" }
    private var marca: String { NomeDeMarca.exibido(historia.marca.marca) }
    private var fotos: [String] { historia.marca.exemplos.compactMap(\.imagem) }

    var body: some View {
        NavigationLink {
            MovimentosDaMarca(marca: historia.marca, tipo: historia.tipo, resposta: historia.resposta)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if grande { mosaico.frame(height: 300) }
                HStack(alignment: .top, spacing: 14) {
                    if !grande, let primeira = fotos.first {
                        FotoDoPainel(endereco: primeira)
                            .frame(width: 96, height: 124)
                            .clipShape(RoundedRectangle(cornerRadius: Edicao.raioDaPeca, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ChamadaDaEdicao(texto: ehReposicao ? frase("Back in stock") : frase("Price cuts"))
                        Text(manchete)
                            .font(grande ? Edicao.Tipo.manchete : Edicao.Tipo.titulo)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(apoio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .capaDaEdicao()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows the items"))
    }

    /// Uma grande e duas pequenas: as peças que a manchete conta.
    @ViewBuilder private var mosaico: some View {
        GeometryReader { g in
            HStack(spacing: 3) {
                FotoDoPainel(endereco: fotos.first)
                    .frame(width: fotos.count > 1 ? g.size.width * 0.62 : g.size.width)
                if fotos.count > 1 {
                    VStack(spacing: 3) {
                        FotoDoPainel(endereco: fotos[1])
                        if fotos.count > 2 { FotoDoPainel(endereco: fotos[2]) }
                    }
                }
            }
        }
        .clipped()
    }

    private var manchete: String {
        let n = Formato.contagem(historia.marca.pecas)
        return ehReposicao
            ? frase("\(marca) brought back \(n) items")
            : frase("\(marca) cut prices on \(n) items")
    }

    /// Por que ESTA marca é a história, e o que mais ela diz.
    private var apoio: String {
        var partes: [String] = []
        if historia.porProporcao, let cem = historia.deCadaCem {
            partes.append(ehReposicao
                ? frase("\(String(cem)) of every 100 items on sale came back, the highest share among the brands.")
                : frase("\(String(cem)) of every 100 items on sale got cheaper, the highest share among the brands."))
        } else {
            partes.append(frase("The largest count this week; no assortment count covers this period, so there is no share."))
        }
        if ehReposicao, let tamanhos = historia.marca.tamanhos, !tamanhos.isEmpty {
            partes.append(frase("Sizes that came back most: \(ListFormatter.localizedString(byJoining: Array(tamanhos.prefix(3))))."))
        }
        if !ehReposicao, let queda = historia.marca.maiorQuedaPct, queda > 0 {
            partes.append(frase("Largest cut: \(String(Int(queda.rounded())))%."))
        }
        return partes.joined(separator: " ")
    }
}

// MARK: - Prateleira

struct CartaoDaPrateleira: View {
    let marca: ResumoDeEventos.Marca

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FotoDoPainel(endereco: marca.exemplos.compactMap(\.imagem).first)
                .frame(width: 132, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: Edicao.raioDaPeca, style: .continuous))
            Text(NomeDeMarca.exibido(marca.marca))
                .font(Edicao.Tipo.nome)
                .lineLimit(1)
            Text(marca.pecas == 1 ? frase("1 item") : frase("\(Formato.contagem(marca.pecas)) items"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(width: 132, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - As peças de uma marca

/// As peças que ilustram o movimento de uma marca. É amostra, e diz de quantas.
struct MovimentosDaMarca: View {
    let marca: ResumoDeEventos.Marca
    let tipo: String
    let resposta: ResumoDeEventos.Resposta
    var inicioDaColeta = "2026-07-24"

    private let colunas = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                Folha(espaco: 6) {
                    FaixaDeNumeros(itens: numeros)
                    if let recorte = ResumoDeEventos.recorte(marca) {
                        Text(recorte).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: colunas, alignment: .leading, spacing: 18) {
                    ForEach(marca.exemplos) { e in cartao(e) }
                }
            }
            .padding(.horizontal, Edicao.margem)
            .padding(.bottom, 32)
        }
        .papelDaEdicao()
        .navigationTitle(Text(verbatim: NomeDeMarca.exibido(marca.marca)))
        .subtituloDaEdicao(ResumoDeEventos.janela(resposta))
    }

    private var numeros: [(valor: String, rotulo: String)] {
        var itens: [(String, String)] = [
            (Formato.contagem(marca.pecas), tipo == "reposicao" ? frase("items back") : frase("items cheaper"))
        ]
        if let porMil = marca.porMilOfertadas {
            itens.append(("\(Int((porMil / 10).rounded()))%", frase("of what is on sale")))
        }
        if marca.eventos > marca.pecas {
            itens.append((Formato.contagem(marca.eventos), frase("events")))
        }
        return itens
    }

    private func cartao(_ e: ResumoDeEventos.Exemplo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FotoDoPainel(endereco: e.imagem)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Edicao.raioDaPeca, style: .continuous))
            Text(verbatim: e.peca ?? "—")
                .font(Edicao.Tipo.nome)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(e.resumo(tipo: tipo))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let r = e.repeticao(tipo: tipo, desde: inicioDaColeta) {
                Text(r).font(.footnote.weight(.semibold)).foregroundStyle(Edicao.caneta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = e.urlDaPeca, let link = URL(string: url) {
                Link(destination: link) {
                    Label("View in store", systemImage: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Edicao.bordo)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
