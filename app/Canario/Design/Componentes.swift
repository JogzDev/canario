import SwiftUI

/// Peças de interface reutilizadas pelas três abas.
/// Nenhuma declara cor ou espaçamento própria — tudo vem de `Tokens`.

// MARK: - Selo de estado

/// Mostra o estado de um termo. Quando não existe leitura publicável, não
/// inventa e também não transforma a ausência em um selo de fracasso: a tela
/// simplesmente não mostra estado.
///
/// §32: nunca comunica por cor sozinha — ícone e texto vão sempre juntos.
struct SeloEstado: View {
    let estado: String?
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
                .accessibilityLabel("Status: \(e.rotulo)")
        } else if let leitura {
            Label(Leitura.comoTitulo(leitura), systemImage: "waveform.path.ecg")
                .font(Tokens.Fonte.corpo.weight(.semibold))
                .padding(.horizontal, Tokens.Espaco.s)
                .padding(.vertical, Tokens.Espaco.xs)
                .background(Tokens.Cor.acao.opacity(0.14))
                .foregroundStyle(Tokens.Cor.acao)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta))
                .accessibilityLabel("Current signal: \(Leitura.comoTitulo(leitura)).")
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
/// Um "?" discreto que guarda a explicação até alguém pedir.
///
/// A revisão pediu isto por dois motivos opostos, e um toque resolve os dois.
/// De um lado faltava explicação: *"Solid cresceu 1,1, o que é esse número?
/// 110%? 10%?"* — número sem unidade é pior que número nenhum. Do outro sobrava
/// texto: *"olhar várias peças por dia e ter que ler tudo é maçante"*. Quem já
/// sabe não lê; quem não sabe acha.
struct BotaoDeAjuda: View {
    let titulo: String
    let texto: String
    /// O que o VoiceOver anuncia. O ícone sozinho vira "botão de interrogação".
    var rotulo: String = "What this means"

    @State private var aberto = false

    var body: some View {
        Button { aberto = true } label: {
            Image(systemName: "questionmark.circle")
                .font(Tokens.Fonte.miudo)
                .foregroundStyle(Tokens.Cor.tintaFraca)
                // 44 pt de alvo com um ícone de 13: o mínimo da Apple sem um
                // "?" enorme ao lado do número que ele explica.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
        .popover(isPresented: $aberto) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
                    Text(titulo).font(Tokens.Fonte.secao)
                    Text(texto)
                        .font(Tokens.Fonte.apoio)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Espaco.m)
            }
            .frame(idealWidth: 360, minHeight: 180)
            // Popover ancorado no "?" corta conteúdo comprido nas bordas do
            // iPhone. Em largura compacta, a folha oferece largura, rolagem e
            // um gesto de fechar previsíveis; no iPad continua sendo popover.
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Linha de insumo

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

// MARK: - Controle do menu

/// Conteúdo único do `ToolbarItem` que abre o menu nas três telas principais.
/// Tamanho, fundo e posição pertencem ao toolbar nativo; desenhar um círculo
/// próprio aqui foi justamente o que fez Add divergir de Closet.
struct BotaoDoMenu: View {
    let menuAberto: Bool
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Image(systemName: menuAberto ? "xmark" : "ellipsis")
        }
        .accessibilityLabel(menuAberto ? "Close menu" : "Open menu")
    }
}

// MARK: - Estados de carga

/// Espera com nome.
///
/// "Loading…" sozinho numa tela em branco não diz o que está acontecendo nem
/// quanto vai demorar. Na importação isso é pior que em outros lugares: são
/// três esperas de naturezas diferentes -- ler o arquivo, separar a peça e
/// mandar para a análise visual --, e a última leva segundos de rede.
///
/// `mensagem` diz o que está sendo feito; `expectativa` avisa quando a espera
/// é longa por natureza, em vez de deixar a pessoa achar que travou.
struct Carregando: View {
    var mensagem = "Loading…"
    var expectativa: String? = nil

    var body: some View {
        VStack(spacing: Tokens.Espaco.s) {
            HStack(spacing: Tokens.Espaco.s) {
                ProgressView()
                Text(mensagem).font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tinta)
            }
            if let expectativa {
                Text(expectativa)
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(Tokens.Espaco.g)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([mensagem, expectativa ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ". "))
    }
}

/// Erro de rede é diferente de ausência de dado, e o app não pode confundir os
/// dois: um é falha nossa, o outro é honestidade sobre o mercado.
struct FalhaDeRede: View {
    let mensagem: String
    let tentarNovamente: () -> Void

    var body: some View {
        VStack(spacing: Tokens.Espaco.s) {
            Label("Couldn't load data", systemImage: "wifi.exclamationmark")
                .font(Tokens.Fonte.secao)
            Text(mensagem)
                .font(Tokens.Fonte.apoio)
                .foregroundStyle(Tokens.Cor.tintaFraca)
                .multilineTextAlignment(.center)
            Button("Try again", action: tentarNovamente)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Espaco.g)
    }
}
