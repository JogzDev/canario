import SwiftUI

/// Peças de interface reutilizadas pelas três abas.
/// Nenhuma declara cor ou espaçamento própria — tudo vem de `Tokens`.

// MARK: - Selo de estado

/// Mostra o estado de um termo. Quando `estado` é nulo, **não inventa**: diz
/// que não há cobertura para afirmar (regra 2 e regra 6).
///
/// §32: nunca comunica por cor sozinha — ícone e texto vão sempre juntos.
struct SeloEstado: View {
    let estado: String?
    let motivo: String?
    var leitura: Double? = nil

    var body: some View {
        if let bruto = estado, let e = Estado(rawValue: bruto) {
            Label(e.rotulo, systemImage: e.icone)
                .font(Tokens.Fonte.miudo.weight(.semibold))
                .padding(.horizontal, Tokens.Espaco.s)
                .padding(.vertical, Tokens.Espaco.xs)
                .background(cor(e).opacity(0.15))
                .foregroundStyle(cor(e))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta))
                .accessibilityLabel("Estado: \(e.rotulo)")
        } else if let leitura {
            Label(Leitura.emPalavras(leitura), systemImage: "waveform.path.ecg")
                .font(Tokens.Fonte.miudo.weight(.semibold))
                .padding(.horizontal, Tokens.Espaco.s)
                .padding(.vertical, Tokens.Espaco.xs)
                .background(Tokens.Cor.azulMarca.opacity(0.12))
                .foregroundStyle(Tokens.Cor.azulMarca)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta))
                .accessibilityLabel("Current signal, not yet confirmed as a trend. \(motivo ?? "")")
        } else {
            Label("Not confirmed", systemImage: "minus.circle")
                .font(Tokens.Fonte.miudo)
                .padding(.horizontal, Tokens.Espaco.s)
                .padding(.vertical, Tokens.Espaco.xs)
                .background(Tokens.Cor.semDado.opacity(0.12))
                .foregroundStyle(Tokens.Cor.semDado)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta))
                .accessibilityLabel("Not confirmed. \(motivo ?? "Coverage is insufficient.")")
        }
    }

    private func cor(_ e: Estado) -> Color {
        switch e {
        case .emAlta: return Tokens.Cor.alta
        case .emQueda: return Tokens.Cor.queda
        case .pico: return Tokens.Cor.pico
        case .estavel: return Tokens.Cor.estavel
        }
    }
}

// MARK: - Cobertura insuficiente

/// A tela que a regra 6 exige: quando falta cobertura, o app diz o que falta e
/// o que consegue mostrar, em vez de exibir um número plausível.
struct CoberturaInsuficiente: View {
    let titulo: String
    let explicacao: String
    var oQueTem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            Label(titulo, systemImage: "exclamationmark.triangle")
                .font(Tokens.Fonte.secao)
                .foregroundStyle(Tokens.Cor.tinta)
            Text(explicacao)
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
            if let oQueTem {
                Text(oQueTem)
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Espaco.m)
        .background(Tokens.Cor.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.cartao))
    }
}

// MARK: - Linha de insumo

/// Rodapé de rastreabilidade. A regra inviolável 3 exige que todo número
/// carregue origem e data de coleta acessíveis ao usuário.
struct LinhaInsumo: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(Tokens.Fonte.miudo)
            .foregroundStyle(Tokens.Cor.tintaFraca)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Cartão

struct Cartao<Conteudo: View>: View {
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            conteudo
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Espaco.m)
        .background(Tokens.Cor.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.cartao))
    }
}

// MARK: - Controle circular do menu

/// O mesmo componente abre e fecha o menu. Compartilhar tamanho, material e
/// símbolo evita o salto de posição que aparecia na transição da home.
struct BotaoCircularDoMenu: View {
    let simbolo: String
    let acessibilidade: String
    let acao: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: acao) { icone.frame(width: 62, height: 62) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            } else {
                Button(action: acao) {
                    ZStack {
                        Vidro(forma: Circle())
                        icone
                    }
                    .frame(width: 62, height: 62)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(acessibilidade)
    }

    private var icone: some View {
        Image(systemName: simbolo)
            .font(.system(size: simbolo == "xmark" ? 27 : 24,
                          weight: simbolo == "xmark" ? .medium : .bold))
            .foregroundStyle(Tokens.Cor.noite)
    }
}

// MARK: - Estados de carga

struct Carregando: View {
    var body: some View {
        HStack(spacing: Tokens.Espaco.s) {
            ProgressView()
            Text("Consultando…").font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(Tokens.Espaco.g)
    }
}

/// Erro de rede é diferente de ausência de dado, e o app não pode confundir os
/// dois: um é falha nossa, o outro é honestidade sobre o mercado.
struct FalhaDeRede: View {
    let mensagem: String
    let tentarNovamente: () -> Void

    var body: some View {
        VStack(spacing: Tokens.Espaco.s) {
            Label("Não consegui consultar", systemImage: "wifi.exclamationmark")
                .font(Tokens.Fonte.secao)
            Text(mensagem)
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
                .multilineTextAlignment(.center)
            Button("Tentar de novo", action: tentarNovamente)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Espaco.g)
    }
}
