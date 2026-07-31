import SwiftUI

/// Leitura de uma peça a partir dos atributos confirmados pelo usuário (§29).
///
/// **O que esta tela ainda NÃO faz, e declara:** o índice do cluster ponderado
/// por raridade (§22 e K5) não está implementado. Sem ele, não existe um número
/// único da peça — existe o número de cada atributo. Mostrar uma média simples
/// seria pior que não mostrar: daria ao usuário um número com aparência de
/// síntese e sem o peso de raridade que o torna significativo ("vestido" pesa
/// pouco, "floral" pesa muito).
struct RelatorioDaPeca: View {
    let termos: [Termo]

    @State private var indices: [String: IndiceSemanal] = [:]
    @State private var coberturas: [String: Cobertura] = [:]
    @State private var carregando = true
    @State private var erro: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Espaco.g) {
                if carregando {
                    Carregando()
                } else if let erro {
                    FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                } else {
                    resumo
                    porAtributo
                    clusterPendente
                    limites
                }
            }
            .padding(Tokens.Espaco.m)
        }
        .task { await carregar() }
    }

    /// §29.1 — template determinístico. Só conta o que foi medido.
    private var resumo: some View {
        Cartao {
            Text(frase).font(Tokens.Fonte.corpo)
        }
    }

    private var frase: String {
        let comLeitura = termos.filter { indices[$0.id]?.indice != nil }
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
                        SeloEstado(estado: indices[termo.id]?.estado,
                                   motivo: "A §22 exige duas fontes concordando.")
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
        if let c, !c.suficiente {
            // §8: sem cobertura, nem índice nem estado. O mesmo portão da
            // outra tela, aplicado atributo a atributo.
            LinhaInsumo(texto: "Cobertura insuficiente: \(c.oQueFalta).")
        } else if let valor = i?.indice {
            Text(Leitura.emPalavras(valor)).font(Tokens.Fonte.apoio)
            LinhaInsumo(texto: Leitura.explicacao(valor))
            LinhaInsumo(texto: Perna.frase(i?.pernasAtivas)
                        + " · semana de \(Formato.data(i?.semana ?? ""))")
        } else {
            LinhaInsumo(texto: "Sem leitura para este atributo neste recorte.")
        }
    }

    /// Honestidade sobre o que falta, no lugar onde o usuário esperaria o
    /// número da peça inteira.
    private var clusterPendente: some View {
        CoberturaInsuficiente(
            titulo: "Ainda não há um número único da peça",
            explicacao: "O índice do conjunto exige ponderar os atributos por raridade — \"vestido\" pesa pouco porque quase toda peça é vestido, \"floral\" pesa muito. Esse cálculo ainda não está implementado.",
            oQueTem: "Até lá, a leitura honesta é atributo por atributo, acima.")
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
                "indices_semanais",
                "select=*&termo_id=in.(\(ids))&order=semana.desc&limit=400")
            async let c: [Cobertura] = Supabase.shared.buscar(
                "cobertura_por_celula",
                "select=*&termo_id=in.(\(ids))&order=semana.desc&limit=400")

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
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}
