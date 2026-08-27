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

    /// Padding e raio crescem junto com a fonte do sistema. Com valores fixos,
    /// aumentar o texto nos ajustes de acessibilidade fazia a frase encostar na
    /// borda e truncar dentro da cápsula.
    @ScaledMetric(relativeTo: .footnote) private var respiro: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var raio: CGFloat = 14

    var body: some View {
        if let leitura {
            let faixa = Leitura.faixa(leitura)
            Label(faixa.rotulo, systemImage: faixa.icone)
                .font(Tokens.Fonte.miudo.weight(.semibold))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                // Sem isto o selo continua com uma linha só e a frase corta em
                // "Far Above the usual…" nos tamanhos grandes.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, respiro)
                .padding(.vertical, respiro * 0.5)
                .background(cores(faixa).fundo)
                .foregroundStyle(cores(faixa).frente)
                .clipShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
                .accessibilityLabel("Current signal: \(faixa.rotulo).")
        } else if let bruto = estado, let e = Estado(rawValue: bruto) {
            Label(e.rotulo, systemImage: e.icone)
                .font(Tokens.Fonte.miudo.weight(.semibold))
                .padding(.horizontal, Tokens.Espaco.s)
                .padding(.vertical, Tokens.Espaco.xs)
                .background(cor(e).opacity(0.15))
                .foregroundStyle(cor(e))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.etiqueta))
                .accessibilityLabel("Status: \(e.rotulo)")
        }
    }

    /// A paleta dos sete estados, uma cor por tema.
    ///
    /// POR QUE FOI REFEITA EM 26/08
    /// ============================
    ///
    /// A primeira versão copiou os SVGs de referência literalmente: pares RGB
    /// fixos, vários deles com `opacity(0.56)` sobre um fundo que o desenho
    /// presumia. Fora daquele fundo o resultado ia de sofrível a ilegível — o
    /// pior caso era `abaixo`, laranja translúcido com texto laranja-claro por
    /// cima. E, sendo fixos, os sete ignoravam o modo escuro.
    ///
    /// O JP: *"eu queria que você usasse as cores e o texto deles mas fizesse o
    /// seu próprio, que se adaptaria naturalmente"*. Então o que veio do
    /// desenho é a **família de cor** de cada nível e o texto; o valor exato é
    /// escolhido por tema e **medido**: os 14 pares passam de 4,5:1 em contraste
    /// WCAG AA (o menor é 6,19:1). `Tokens.Cor.adaptativa` resolve no momento de
    /// desenhar, então trocar de tema com o app aberto repinta o selo.
    private func cores(_ faixa: Leitura.Faixa) -> (fundo: Color, frente: Color) {
        switch faixa {
        case .muitoAcima:
            return (Tokens.Cor.adaptativa(claro: (222, 246, 214), escuro: (24, 58, 30)),
                    Tokens.Cor.adaptativa(claro: (24, 80, 30), escuro: (168, 230, 160)))
        case .acima:
            return (Tokens.Cor.adaptativa(claro: (219, 234, 254), escuro: (26, 48, 84)),
                    Tokens.Cor.adaptativa(claro: (26, 58, 120), escuro: (168, 200, 250)))
        case .poucoAcima:
            return (Tokens.Cor.adaptativa(claro: (226, 236, 246), escuro: (30, 52, 72)),
                    Tokens.Cor.adaptativa(claro: (32, 66, 102), escuro: (168, 205, 235)))
        case .habitual:
            return (Tokens.Cor.adaptativa(claro: (233, 236, 239), escuro: (48, 54, 60)),
                    Tokens.Cor.adaptativa(claro: (55, 65, 74), escuro: (202, 210, 217)))
        case .poucoAbaixo:
            return (Tokens.Cor.adaptativa(claro: (255, 236, 222), escuro: (74, 45, 26)),
                    Tokens.Cor.adaptativa(claro: (140, 62, 20), escuro: (250, 200, 165)))
        case .abaixo:
            return (Tokens.Cor.adaptativa(claro: (255, 226, 209), escuro: (82, 40, 20)),
                    Tokens.Cor.adaptativa(claro: (150, 50, 8), escuro: (255, 190, 150)))
        case .muitoAbaixo:
            return (Tokens.Cor.adaptativa(claro: (255, 224, 224), escuro: (84, 28, 28)),
                    Tokens.Cor.adaptativa(claro: (140, 26, 26), escuro: (255, 180, 180)))
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
    /// Substitui `expectativa` quando a espera passa de `segundosParaDemora`.
    ///
    /// Existe por causa do relato de "loading de ~30 s" no iPhone 15. O teto de
    /// tempo da análise remota é literalmente 30 s (`Supabase.analisarPeca`), e
    /// durante todo esse tempo a tela dizia *"usually takes a few seconds"* — a
    /// frase certa nos primeiros segundos e uma mentira nos últimos vinte.
    /// Espera longa sem aviso é indistinguível de travamento, e a pessoa não
    /// sabe que pode sair.
    ///
    /// Isto não acelera nada e não finge acelerar: troca "parece travado" por
    /// "está demorando, e você pode fechar".
    var avisoDeDemora: String? = nil
    var segundosParaDemora: Double = 8
    @State private var demorou = false

    private var apoio: String? {
        (demorou ? avisoDeDemora : nil) ?? expectativa
    }

    var body: some View {
        VStack(spacing: Tokens.Espaco.s) {
            HStack(spacing: Tokens.Espaco.s) {
                ProgressView()
                Text(mensagem).font(Tokens.Fonte.apoio)
                    .foregroundStyle(Tokens.Cor.tinta)
            }
            if let apoio {
                Text(apoio)
                    .font(Tokens.Fonte.miudo)
                    .foregroundStyle(Tokens.Cor.tintaFraca)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(Tokens.Espaco.g)
        // `id: mensagem` reinicia a contagem quando a espera muda de natureza:
        // separar a peça e analisar na nuvem são duas esperas, não uma longa.
        .task(id: mensagem) {
            demorou = false
            guard avisoDeDemora != nil else { return }
            try? await Task.sleep(for: .seconds(segundosParaDemora))
            guard !Task.isCancelled else { return }
            demorou = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([mensagem, apoio ?? ""]
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

/// A barra de uma proporção, fina e sem número próprio.
///
/// Ela nunca aparece sozinha: mora colada à frase que diz a porcentagem, e é
/// essa vizinhança que a define. Uma barra com número próprio ao lado de um
/// segundo número vira adivinhação sobre qual dos dois ela mede — foi o que
/// aconteceu no primeiro desenho da procedência do cluster, onde ela dividia a
/// linha com o valor do atributo.
///
/// Fica escondida do VoiceOver de propósito: o texto ao lado já diz a
/// porcentagem, e uma barra falada como "56 por cento" logo antes de alguém
/// ouvir "56% of the weight" é a mesma informação duas vezes.
struct BarraDePeso: View {
    /// 0 a 1. Valor fora da faixa é preso na faixa em vez de estourar o
    /// desenho: peso vem do servidor, e desenho não é lugar de confiar.
    let fracao: Double

    var body: some View {
        GeometryReader { area in
            let cheia = max(0, min(1, fracao))
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.Cor.superficie)
                Capsule()
                    .fill(Tokens.Cor.azulMarca.opacity(0.55))
                    .frame(width: max(2, area.size.width * cheia))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
