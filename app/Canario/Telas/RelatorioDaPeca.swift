import Charts
import PhotosUI
import SwiftUI
import UIKit

/// Leitura de uma peça a partir dos atributos confirmados pelo usuário (§29).
///
/// **A ordem desta tela é a da §29, e ela é deliberada:** primeiro o parágrafo
/// dos similares (o substituto aprovado da previsão, §5), depois os similares,
/// depois cada atributo, e só então o número do conjunto (§22, K5).
///
/// O conjunto vem por último de propósito. Um número único no topo é lido como
/// veredito; o mesmo número depois das partes é lido como resumo delas. E ele
/// se cala quando os atributos discordam entre si — ver `Cluster.haDirecao`.
struct RelatorioDaPeca: View {
    let termos: [Termo]
    /// Preço que o usuário pretende praticar, se informou. §29.5 chama isso de
    /// contexto condicional, e a §5 autoriza o percentil de preço que sai dele.
    var precoAlvo: Double?
    /// Prévia local, já sem metadados. Só é persistida se o usuário guardar.
    var miniaturaJPEG: Data?
    /// Quando aberto pelo Closet, evita salvar uma duplicata da mesma peça.
    var pecaSalva: PecaSalva? = nil
    /// Linguagem usada na busca. Preserva "vestido de bolinha" sem alterar os
    /// ids `vestido` + `geometrica` que alimentam o cálculo.
    var descricaoAmigavel: String? = nil

    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var coberturas: [String: Cobertura] = [:]
    @State private var similares: Similares.Resposta?
    @State private var cluster: Cluster.Resposta?
    @State private var serie: SerieDoCluster.Resposta?
    @State private var erroDosSimilares: String?
    @State private var erroDoCluster: String?
    @State private var erroDaSerie: String?
    @State private var carregandoSimilares = true
    @State private var carregandoCluster = true
    @State private var carregandoSerie = true
    @State private var carregando = true
    @State private var erro: String?
    /// nil = ainda não tentou; true = guardada; false = a lista está no teto.
    @State private var guardada: Bool?
    @State private var rejeitouSimilares = false
    @State private var fotoEscolhida: PhotosPickerItem?
    @State private var miniaturaDaPeca: UIImage?
    @State private var processandoFoto = false
    @State private var erroDaFoto: String?
    @State private var pecaGuardadaNestaTela: PecaSalva?

    /// Guarda a peça em "Minhas peças" (§27, A10).
    ///
    /// Grava só os `termoIds` — o que o usuário confirmou. Nada do que está na
    /// tela abaixo: índice, estado e similares são recomputados do dado de hoje
    /// quando ela for reaberta. É essa a diferença entre lista de trabalho e
    /// armário, e a §34 exclui o segundo.
    @ViewBuilder
    private var botaoDeGuardar: some View {
        if pecaSalva != nil {
            Label("Saved", systemImage: "archivebox.fill")
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(.secondary)
        } else {
            switch guardada {
        case true:
            Label("Saved", systemImage: "archivebox.fill")
                .labelStyle(.titleAndIcon)
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(.secondary)
        case false:
            // O teto é dito, e não engole a peça em silêncio.
            Text("Lista cheia (\(PecasSalvas.teto))")
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(.secondary)
        case nil:
            Button {
                Task {
                    let nova = PecaSalva(
                        termoIds: termos.map(\.id), precoAlvo: precoAlvo,
                        similaresRejeitados: rejeitouSimilares ? true : nil)
                    guardada = await PecasSalvas.shared.salvar(
                        nova, miniaturaDados: miniaturaJPEG)
                    if guardada == true { pecaGuardadaNestaTela = nova }
                }
            } label: {
                Label("Save", systemImage: "archivebox")
            }
            .disabled(termos.isEmpty)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else {
                    if pecaSalva != nil { fotoDaPeca }
                    // §29, na ordem que ela manda: o parágrafo vem primeiro, e
                    // ele é feito de similares — não do índice.
                    resumo
                    blocoDeSimilares
                    porAtributo
                    blocoDoCluster
                    blocoDoHistorico
                    limites
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .task { await carregar() }
        .task(id: pecaSalva?.miniaturaArquivo) { await carregarMiniaturaDaPeca() }
        .onAppear { rejeitouSimilares = pecaSalva?.similaresRejeitados ?? false }
        .onChange(of: fotoEscolhida) { _, item in
            guard let item else { return }
            Task { await substituirFoto(item) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { botaoDeGuardar }
        }
    }

    /// A edição visual mora no detalhe, onde há contexto para entender qual
    /// peça será alterada. O card continua oferecendo “Add photo” somente para
    /// itens antigos que ainda não têm nenhuma.
    private var fotoDaPeca: some View {
        Cartao {
            if let miniaturaDaPeca {
                Image(uiImage: miniaturaDaPeca)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .accessibilityLabel("Saved clothing photo")
            }
            if let erroDaFoto {
                Text(erroDaFoto).font(Tokens.Fonte.miudo).foregroundStyle(.secondary)
            }
            PhotosPicker(selection: $fotoEscolhida, matching: .images) {
                HStack {
                    if processandoFoto { ProgressView().controlSize(.small) }
                    Label(miniaturaDaPeca == nil ? "Add photo" : "Replace photo",
                          systemImage: "photo.badge.arrow.down")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(processandoFoto)
        }
    }

    @MainActor
    private func carregarMiniaturaDaPeca() async {
        guard let pecaSalva,
              let dados = await PecasSalvas.shared.miniatura(de: pecaSalva) else {
            miniaturaDaPeca = nil
            return
        }
        miniaturaDaPeca = await MiniaturaParaTela.imagem(de: dados)
    }

    @MainActor
    private func substituirFoto(_ item: PhotosPickerItem) async {
        guard let pecaSalva else { return }
        processandoFoto = true
        erroDaFoto = nil
        defer {
            processandoFoto = false
            fotoEscolhida = nil
        }
        do {
            guard let dados = try await item.loadTransferable(type: Data.self),
                  let imagem = MiniaturaLocal.imagem(de: dados),
                  let miniatura = await MiniaturaLocal.dados(de: imagem),
                  await PecasSalvas.shared.salvar(pecaSalva, miniaturaDados: miniatura)
            else {
                erroDaFoto = "I couldn't save that photo. Your existing image was not changed."
                return
            }
            miniaturaDaPeca = await MiniaturaParaTela.imagem(de: miniatura)
        } catch {
            erroDaFoto = "I couldn't read that image. Try another photo."
        }
    }

    /// §29.1 — template determinístico. Só conta o que foi medido.
    ///
    /// O parágrafo do painel vem PRIMEIRO, e o da taxonomia depois: é o que a
    /// §29 pede, e faz sentido — "encontrei 230 peças parecidas, 22% a preço
    /// cheio" responde a uma pergunta que o comprador tem; "3 atributos, 2 com
    /// leitura" responde a uma pergunta que ele não fez.
    private var resumo: some View {
        Cartao {
            if let r = similares?.resumo {
                Text(Similares.paragrafo(r, atributos: termos,
                                         descricao: descricaoAmigavel))
                    .font(Tokens.Fonte.corpo)
                Divider()
            }
            Text(frase).font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
        }
    }

    /// §29.4 — o bloco de insumos de varejo: similares com preço, remarcação e
    /// estado da grade, sempre.
    @ViewBuilder
    private var blocoDeSimilares: some View {
        if carregandoSimilares {
            secaoCarregando("Similar pieces")
        } else if let erroDosSimilares {
            falhaLocal(titulo: "Similar pieces", mensagem: erroDosSimilares)
        } else if let s = similares, let r = s.resumo,
                  !s.pecas.filter(Similares.podeExibir).isEmpty {
            if rejeitouSimilares {
                LinhaInsumo(texto: "You marked this selection as not similar. You can review it again at any time.")
                Button("Review similar pieces again") { rejeitarSimilares(false) }
                    .buttonStyle(.bordered)
            } else {
                BlocoDeSimilares(resumo: r,
                                 pecas: s.pecas.filter(Similares.podeExibir),
                                 atributos: termos, precoAlvo: precoAlvo)
                Button("None of these looks like my item") { rejeitarSimilares(true) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        } else {
            LinhaInsumo(texto: "No panel item matched all selected attributes.")
        }
    }

    private func secaoCarregando(_ titulo: String) -> some View {
        Cartao {
            HStack {
                Text(titulo).font(Tokens.Fonte.secao)
                Spacer()
                ProgressView()
            }
        }
    }

    private func falhaLocal(titulo: String, mensagem: String) -> some View {
        Cartao {
            Text(titulo).font(Tokens.Fonte.secao)
            Text(mensagem).font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            Button("Try again") { Task { await carregar() } }
                .buttonStyle(.bordered)
        }
    }

    private var frase: String {
        let comLeitura = termos.filter {
            let indice = indices[$0.id]
            return indice?.indice != nil
                && Elegibilidade.indice(indice, cobertura: coberturas[$0.id])
        }
        if comLeitura.isEmpty {
            return "Marquei \(termos.count) atributo\(termos.count == 1 ? "" : "s"), mas nenhum tem leitura disponível neste recorte."
        }
        let acima = comLeitura.filter { (indices[$0.id]?.indice ?? 0) >= 1 }
        let abaixo = comLeitura.filter { (indices[$0.id]?.indice ?? 0) <= -1 }
        var partes = ["Esta peça tem \(termos.count) atributo\(termos.count == 1 ? "" : "s"), \(comLeitura.count) com leitura."]
        if !acima.isEmpty {
            partes.append("Acima do normal: \(acima.map(Traducao.rotuloExibido).joined(separator: ", ")).")
        }
        if !abaixo.isEmpty {
            partes.append("Abaixo do normal: \(abaixo.map(Traducao.rotuloExibido).joined(separator: ", ")).")
        }
        if acima.isEmpty && abaixo.isEmpty {
            partes.append("Todos dentro da faixa normal deles.")
        }
        return partes.joined(separator: " ")
    }

    /// Um bloco por atributo, cada um com o próprio portão de cobertura.
    private var porAtributo: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            Text("Por atributo").font(Tokens.Fonte.secao)
            ForEach(termos) { termo in
                Cartao {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Tokens.Espaco.xs) {
                            Text(Traducao.rotuloExibido(termo)).font(Tokens.Fonte.corpo)
                            Text(termo.dimensao)
                                .font(Tokens.Fonte.miudo)
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                        }
                        Spacer()
                        let indice = indices[termo.id]
                        let podeMostrar = Elegibilidade.indice(
                            indice, cobertura: coberturas[termo.id])
                        SeloEstado(estado: podeMostrar ? indice?.estado : nil,
                                   motivo: podeMostrar
                                       ? "Só afirmo uma direção quando duas fontes concordam."
                                       : "Sem cobertura suficiente da mesma semana.",
                                   leitura: podeMostrar ? indice?.indice : nil)
                    }
                    conteudo(de: termo)
                }
            }
        }
    }

    @ViewBuilder
    private func conteudo(de termo: Termo) -> some View {
        let i = indices[termo.id]
        let c = coberturas[termo.id]
        if c == nil {
            LinhaInsumo(texto: "Não há medição de cobertura para este atributo nesta semana.")
        } else if !Elegibilidade.indice(i, cobertura: c) {
            // §8: sem cobertura, nem índice nem estado. O mesmo portão da
            // outra tela, aplicado atributo a atributo.
            LinhaInsumo(texto: "Cobertura insuficiente: \(c?.oQueFalta ?? "sem medição").")
        } else if let valor = i?.indice {
            Text(Leitura.emPalavras(valor)).font(Tokens.Fonte.apoio)
            LinhaInsumo(texto: Leitura.explicacao(valor))
            LinhaInsumo(texto: Perna.frase(i?.pernasAtivas)
                        + " · semana de \(Formato.data(i?.semana ?? ""))")
        } else {
            LinhaInsumo(texto: "Sem leitura para este atributo neste recorte.")
        }
    }

    /// O histórico dos ATRIBUTOS da peça (A14).
    ///
    /// Não é a peça do usuário ao longo do tempo — ela não está no painel, e a
    /// §34 exclui acompanhá-la. É o recorte de mercado que ela ocupa.
    @ViewBuilder
    private var blocoDoHistorico: some View {
        Cartao {
            Text("Como esse conjunto se moveu").font(Tokens.Fonte.secao)
            if carregandoSerie {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if let erroDaSerie {
                Text("Não consegui carregar o gráfico: \(erroDaSerie)")
                    .font(Tokens.Fonte.corpo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                Button("Tentar gráfico novamente") { Task { await carregar() } }
                    .buttonStyle(.bordered)
            } else if let motivo = SerieDoCluster.porQueNaoDesenha(serie) {
                // Nunca um espaço em branco: a tela diz o que falta.
                Text(motivo)
                    .font(Tokens.Fonte.corpo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            } else if let s = serie {
                Chart(s.pontos.filter { $0.data != nil }) { p in
                    AreaMark(x: .value("Semana", p.data!),
                             yStart: .value("Base", 0),
                             yEnd: .value("Índice", p.indice))
                        .foregroundStyle(Tokens.Cor.azulMarca.opacity(0.12))
                    LineMark(x: .value("Semana", p.data!),
                             y: .value("Índice", p.indice))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Tokens.Cor.azulMarca)
                    // Semana com menos atributos que o pedido ganha ponto
                    // visível: a linha sozinha mente por omissão, porque parece
                    // uniforme mesmo quando metade dela veio de um atributo só.
                    if SerieDoCluster.ralo(p, de: s.atributosPedidos) {
                        PointMark(x: .value("Semana", p.data!),
                                  y: .value("Índice", p.indice))
                            .symbolSize(28)
                            .foregroundStyle(Tokens.Cor.semDado)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartYAxisLabel(s.unidade ?? "")
                .frame(height: 160)
                .accessibilityLabel(
                    "Histórico do conjunto em \(s.pontos.count) semanas")
                if let r = SerieDoCluster.ressalva(s) { LinhaInsumo(texto: r) }
                if let c = s.categoriaUsada, c != "(todas)" {
                    LinhaInsumo(texto: "Raridade medida dentro de \(c).")
                }
            }
        }
    }

    /// §22 / K5 — o número da peça inteira, com os pesos abertos.
    ///
    /// Esta tela declarava, até 02/08, que o cálculo não existia. Agora existe,
    /// e a honestidade mudou de lugar: em vez de dizer "não há número", ela diz
    /// **de que o número é feito** e, quando os atributos discordam entre si,
    /// se recusa a dar direção.
    @ViewBuilder
    private var blocoDoCluster: some View {
        if carregandoCluster {
            secaoCarregando("Combined reading")
        } else if let erroDoCluster {
            falhaLocal(titulo: "Combined reading", mensagem: erroDoCluster)
        } else if let c = cluster, c.nAtributos > 0 {
            Cartao {
                Text("O conjunto").font(Tokens.Fonte.secao)
                Text(Cluster.manchete(c)).font(Tokens.Fonte.corpo)
                if let e = Cluster.explicacao(c) { LinhaInsumo(texto: e) }
                if let k = Cluster.concentracao(c) { LinhaInsumo(texto: k) }

                Divider()
                Text("De onde vem esse número").font(Tokens.Fonte.miudo.weight(.semibold))
                LinhaInsumo(texto: Cluster.criterioDaRaridade(c))
                ForEach(Cluster.dentro(c)) { a in
                    HStack(alignment: .firstTextBaseline) {
                        Text(a.rotulo).font(Tokens.Fonte.miudo)
                        Spacer()
                        if let i = a.indice {
                            Text(Leitura.numero(i, casas: 2, sinal: true))
                                .font(Tokens.Fonte.miudo.monospacedDigit())
                                .foregroundStyle(Tokens.Cor.tintaFraca)
                        }
                    }
                    if let p = Cluster.porQuePesa(a) { LinhaInsumo(texto: p) }
                }
                if let s = Cluster.ressalvaDeSemana(c) { LinhaInsumo(texto: s) }

                // Regra 6: o que ficou de fora aparece, e diz por quê.
                let fora = Cluster.deFora(c)
                if !fora.isEmpty {
                    Divider()
                    Text("Fora da conta").font(Tokens.Fonte.miudo.weight(.semibold))
                    ForEach(fora) { a in
                        LinhaInsumo(texto: "\(a.rotulo): \(a.foraPor ?? "sem motivo registrado")")
                    }
                }
            }
        } else {
            CoberturaInsuficiente(
                titulo: "Ainda não há número do conjunto para esta peça",
                explicacao: "Nenhum dos atributos marcados tem leitura com cobertura suficiente neste recorte, então não existe média a fazer.",
                oQueTem: "A leitura honesta é atributo por atributo, acima.")
        }
    }

    /// §29.6 — limites declarados, sempre.
    private var limites: some View {
        Cartao {
            Text("Limites").font(Tokens.Fonte.secao)
            LinhaInsumo(texto: "Não consideramos: seu histórico de vendas, seus custos, sua capacidade de produção.")
            LinhaInsumo(texto: "Sinal editorial carrega viés comercial de publicidade.")
            LinhaInsumo(texto: "A imagem original foi lida e descartada. Se você salvar no Closet, fica somente uma miniatura local sem metadados, apagada junto com a peça.")
        }
    }

    private func carregar() async {
        carregando = true
        erro = nil
        erroDosSimilares = nil
        erroDoCluster = nil
        erroDaSerie = nil
        carregandoSimilares = true
        carregandoCluster = true
        carregandoSerie = true
        guard !termos.isEmpty else { carregando = false; return }
        let termoIds = termos.map(\.id)
        let ids = termoIds.joined(separator: ",")
        let conjuntoIds = Set(termoIds)
        do {
            // Todas as cinco operações começam no mesmo instante. A versão
            // anterior esperava índice+cobertura e SÓ DEPOIS iniciava os três
            // RPCs; a duração percebida era a soma de duas ondas de rede.
            async let i = CatalogoDeIndices.shared.carregar()
            async let c: [Cobertura] = Supabase.shared.buscar(
                "cobertura_por_celula",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=in.(\(ids))&order=semana.desc&limit=600")

            let args: [String: Any] = {
                var argumentos: [String: Any] = ["termos": termoIds, "limite": 8]
                if let precoAlvo { argumentos["preco_alvo"] = precoAlvo }
                return argumentos
            }()
            async let respostaSimilar: Similares.Resposta = Supabase.shared.chamar(
                "similares_da_peca", args)
            async let respostaCluster: Cluster.Resposta = Supabase.shared.chamar(
                "indice_do_cluster", ["termos": termoIds])
            async let respostaSerie: SerieDoCluster.Resposta = Supabase.shared.chamar(
                "serie_do_cluster", ["termos": termoIds, "semanas": 52])

            let recebidosI = try await i.filter { conjuntoIds.contains($0.termoId) }
            let mapaI = SelecaoDeEstado.porTermo(recebidosI)
            indices = mapaI

            // A cobertura tem de ser a da MESMA semana do índice do atributo.
            var mapaC: [String: Cobertura] = [:]
            for x in try await c {
                guard let indice = mapaI[x.termoId], indice.semana == x.semana else { continue }
                mapaC[x.termoId] = x
            }
            coberturas = mapaC
            // Índices e cobertura bastam para liberar a tela. Os três RPCs
            // continuam em voo e ocupam somente suas próprias seções.
            carregando = false

            do {
                similares = try await respostaSimilar
            } catch {
                erroDosSimilares = mensagem(error)
            }
            carregandoSimilares = false
            do { cluster = try await respostaCluster }
            catch { erroDoCluster = mensagem(error) }
            carregandoCluster = false
            do { serie = try await respostaSerie }
            catch { erroDaSerie = mensagem(error) }
            carregandoSerie = false
        } catch {
            erro = mensagem(error)
        }
        carregando = false
    }

    private func mensagem(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }

    private func rejeitarSimilares(_ rejeitados: Bool) {
        rejeitouSimilares = rejeitados
        guard var atualizada = pecaSalva ?? pecaGuardadaNestaTela else { return }
        atualizada.similaresRejeitados = rejeitados ? true : nil
        pecaGuardadaNestaTela = atualizada
        Task { await PecasSalvas.shared.salvar(atualizada) }
    }
}
