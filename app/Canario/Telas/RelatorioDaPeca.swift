import SwiftUI

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

    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var coberturas: [String: Cobertura] = [:]
    @State private var similares: Similares.Resposta?
    @State private var cluster: Cluster.Resposta?
    @State private var carregando = true
    @State private var erro: String?
    /// nil = ainda não tentou; true = guardada; false = a lista está no teto.
    @State private var guardada: Bool?

    /// Guarda a peça em "Minhas peças" (§27, A10).
    ///
    /// Grava só os `termoIds` — o que o usuário confirmou. Nada do que está na
    /// tela abaixo: índice, estado e similares são recomputados do dado de hoje
    /// quando ela for reaberta. É essa a diferença entre lista de trabalho e
    /// armário, e a §34 exclui o segundo.
    @ViewBuilder
    private var botaoDeGuardar: some View {
        switch guardada {
        case true:
            Label("Guardada", systemImage: "checkmark")
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
                    guardada = await PecasSalvas.shared.salvar(
                        PecaSalva(termoIds: termos.map(\.id), precoAlvo: precoAlvo))
                }
            } label: {
                Label("Guardar", systemImage: "square.stack.3d.up")
            }
            .disabled(termos.isEmpty)
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
                    // §29, na ordem que ela manda: o parágrafo vem primeiro, e
                    // ele é feito de similares — não do índice.
                    resumo
                    blocoDeSimilares
                    porAtributo
                    blocoDoCluster
                    limites
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .task { await carregar() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { botaoDeGuardar }
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
                Text(Similares.paragrafo(r, atributos: termos))
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
        if let s = similares, let r = s.resumo, !s.pecas.isEmpty {
            BlocoDeSimilares(resumo: r, pecas: s.pecas,
                             atributos: termos, precoAlvo: precoAlvo)
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
            partes.append("Acima do normal: \(acima.map(\.rotulo).joined(separator: ", ")).")
        }
        if !abaixo.isEmpty {
            partes.append("Abaixo do normal: \(abaixo.map(\.rotulo).joined(separator: ", ")).")
        }
        if acima.isEmpty && abaixo.isEmpty {
            partes.append("Todos dentro do normal deles.")
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
                            Text(termo.rotulo).font(Tokens.Fonte.corpo)
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
                                       : "Sem cobertura suficiente da mesma semana.")
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

    /// §22 / K5 — o número da peça inteira, com os pesos abertos.
    ///
    /// Esta tela declarava, até 02/08, que o cálculo não existia. Agora existe,
    /// e a honestidade mudou de lugar: em vez de dizer "não há número", ela diz
    /// **de que o número é feito** e, quando os atributos discordam entre si,
    /// se recusa a dar direção.
    @ViewBuilder
    private var blocoDoCluster: some View {
        if let c = cluster, c.nAtributos > 0 {
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
            LinhaInsumo(texto: "O arquivo que você enviou foi lido no aparelho e descartado. Nada foi guardado nem enviado.")
        }
    }

    private func carregar() async {
        carregando = true
        erro = nil
        guard !termos.isEmpty else { carregando = false; return }
        let ids = termos.map(\.id).joined(separator: ",")
        do {
            async let i: [IndiceSemanal] = Supabase.shared.buscar(
                "indices_do_app",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=in.(\(ids))&order=semana.desc&limit=400")
            async let c: [Cobertura] = Supabase.shared.buscar(
                "cobertura_por_celula",
                "select=*&segmento=eq.\(Recorte.segmento)&termo_id=in.(\(ids))&order=semana.desc&limit=400")

            var mapaI: [String: IndiceSemanal] = [:]
            for x in try await i where mapaI[x.termoId] == nil { mapaI[x.termoId] = x }
            indices = mapaI

            // A cobertura tem de ser a da MESMA semana do índice do atributo.
            var mapaC: [String: Cobertura] = [:]
            for x in try await c {
                guard let indice = mapaI[x.termoId], indice.semana == x.semana else { continue }
                mapaC[x.termoId] = x
            }
            coberturas = mapaC

            // §33: servidor calcula, app consulta. Trazer 18 mil peças pela
            // rede para contar quantas estão remarcadas seria o oposto disso.
            var args: [String: Any] = ["termos": termos.map(\.id), "limite": 8]
            if let precoAlvo { args["preco_alvo"] = precoAlvo }
            similares = try await Supabase.shared.chamar("similares_da_peca", args)

            // §22/K5. Chamada separada de propósito: se o cluster falhar, os
            // similares — que são o substituto aprovado da previsão (§5) —
            // continuam na tela. O contrário também vale.
            cluster = try? await Supabase.shared.chamar(
                "indice_do_cluster", ["termos": termos.map(\.id)])
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}
