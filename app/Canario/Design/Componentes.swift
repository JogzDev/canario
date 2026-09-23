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
    @Environment(\.territorio) private var territorio

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
    /// **Escolhido pelo TERRITÓRIO, não pelo tema do sistema (27/08).**
    ///
    /// Os quatorze pares já existiam e já estavam medidos; o que estava errado
    /// era o critério. `adaptativa` pergunta ao iPhone se ele está no modo
    /// escuro — e o app inteiro é `preferredColorScheme(.light)`, então a
    /// resposta é sempre "claro". Numa tela de mercado, que é escura por
    /// decisão de produto e não por tema, o selo escolhia o par CLARO e ficava
    /// texto escuro sobre fundo escuro.
    ///
    /// Não é hipótese: era o que aconteceria na primeira tela do território
    /// novo, em todos os sete estados de uma vez. Trocar `adaptativa` por
    /// `fixa` escolhida pelo território preserva os pares medidos e resolve.
    private func cores(_ faixa: Leitura.Faixa) -> (fundo: Color, frente: Color) {
        func par(_ claro: (Double, Double, Double),
                 _ escuro: (Double, Double, Double)) -> Color {
            let c = territorio == .mercado ? escuro : claro
            return Tokens.Cor.fixa(c.0, c.1, c.2)
        }
        switch faixa {
        case .muitoAcima:
            return (par((222, 246, 214), (24, 58, 30)),
                    par((24, 80, 30), (168, 230, 160)))
        case .acima:
            return (par((219, 234, 254), (26, 48, 84)),
                    par((26, 58, 120), (168, 200, 250)))
        case .poucoAcima:
            return (par((226, 236, 246), (30, 52, 72)),
                    par((32, 66, 102), (168, 205, 235)))
        case .habitual:
            return (par((233, 236, 239), (48, 54, 60)),
                    par((55, 65, 74), (202, 210, 217)))
        case .poucoAbaixo:
            return (par((255, 236, 222), (74, 45, 26)),
                    par((140, 62, 20), (250, 200, 165)))
        case .abaixo:
            return (par((255, 226, 209), (82, 40, 20)),
                    par((150, 50, 8), (255, 190, 150)))
        case .muitoAbaixo:
            return (par((255, 224, 224), (84, 28, 28)),
                    par((140, 26, 26), (255, 180, 180)))
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
    let titulo: LocalizedStringKey
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
    /// Título e corpo chegam calculados (a explicação da escala vem do
    /// `Explicacao`, já traduzida por `frase(_:)`). Ver a nota em
    /// `LinhaInsumo` sobre por que isto é `String` e não chave de catálogo.
    let titulo: String
    let texto: String
    /// O que o VoiceOver anuncia. O ícone sozinho vira "botão de interrogação".
    var rotulo: String = frase("What this means")

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
    /// `String`, e não `LocalizedStringKey`: quase todo chamador passa texto
    /// já calculado (`Similares.criterio`, `Perna.baseadoEm`), que sai de
    /// `frase(_:)` traduzido. Tratá-lo como chave mandaria o catálogo procurar
    /// tradução para uma frase que já é a tradução. Os poucos chamadores com
    /// literal envolvem em `frase("...")`, e o extrator os enxerga igual.
    let texto: String
    @Environment(\.territorio) private var territorio

    var body: some View {
        Text(texto)
            .font(Tokens.Fonte.miudo)
            .foregroundStyle(Tokens.Cor.tintaFracaDo(territorio))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Cartão

struct Cartao<Conteudo: View>: View {
    @ViewBuilder var conteudo: Conteudo
    @Environment(\.territorio) private var territorio

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Espaco.s) {
            conteudo
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Espaco.m)
        .background(Tokens.Cor.superficieDo(territorio))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Raio.cartao))
        // A tinta desce por herança: quem escreve dentro do cartão não precisa
        // saber onde está. Só quem pede uma cor explícita passa por cima --
        // e aí é escolha, não esquecimento.
        .foregroundStyle(Tokens.Cor.tintaDo(territorio))
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
        if !menuAberto {
            // 2.0: o menu lateral virou a sheet de conta; o botão das telas
            // antigas é o mesmo das novas enquanto elas não são refeitas.
            Button(action: acao) {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Account")
        }
        // Aberto, o painel opaco traz o próprio X. O botão da barra de trás
        // precisa sair da árvore, não só ficar visualmente coberto: o SwiftUI
        // continuava expondo dois "Close menu" para o VoiceOver.
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
    /// Idem `LinhaInsumo`: mensagem de erro chega pronta da camada de rede.
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

/// A moldura neutra em que TODA foto de peça é desenhada.
///
/// POR QUE ISTO EXISTE
/// ===================
///
/// Antes de 05/09 a peça era desenhada sobre o céu da marca em seis lugares
/// diferentes, e cada um repetia a cor na unha: o herói de 300 pt do relatório,
/// as três prévias do importador, o card do Closet, as miniaturas da home, os
/// favoritos do menu e as miniaturas de similares. Seis cópias da mesma decisão
/// é como `AbaDoApp` nasceu — e é como ela divergiu.
///
/// Aqui a repetição custa mais caro que layout inconsistente. O fundo cromático
/// desloca a cor percebida da peça na direção complementar; o `CorDaPeca` mede a
/// cor dominante do MESMO pixel e pré-marca a dimensão `cor` do formulário. Um
/// fundo azul empurra a percepção da pessoa para o quente enquanto o algoritmo
/// mede o valor cru: os dois discordam, e quem corrige o formulário é a pessoa,
/// que está sendo enganada pela moldura. A diretoria apontou isso olhando a
/// tela, sem saber do `CorDaPeca` — o que confirma o tamanho do efeito.
///
/// Um dono só, então: mudar a moldura de julgamento de cor é mudar este
/// arquivo, e não caçar `Tokens.Cor.ceu` por seis telas outra vez.
///
/// `conteudo` é a foto. Quando não há foto, use `SubstratoDaPeca` com o próprio
/// estado vazio dentro — a moldura não vira buraco branco nem some da tela.
struct SubstratoDaPeca<Conteudo: View>: View {
    var raio: CGFloat = Tokens.Raio.cartaoGrande
    /// Respiro entre a borda da moldura e a foto. Existe para a peça não
    /// encostar no canto arredondado, não para enquadrar: a foto continua
    /// `scaledToFit`, e o que sobra é substrato, que é justamente o ponto.
    var respiro: CGFloat = Tokens.Espaco.m
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: raio, style: .continuous)
                .fill(Tokens.Cor.substratoDaPeca)
            conteudo
                .padding(respiro)
        }
        .clipShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
    }
}

/// O estado vazio dentro da moldura: a peça não tem foto.
///
/// Fica aqui, e não em cada tela, porque a tinta precisa ser medida contra o
/// substrato — `.secondary` do sistema resolve contra o fundo da JANELA, não
/// contra os #CBCBCB que este componente pinta, e no primeiro esboço o ícone
/// quase sumiu por isso.
struct PecaSemFoto: View {
    var simbolo: String = "photo"
    var tamanho: CGFloat = 34
    var legenda: LocalizedStringKey?

    var body: some View {
        VStack(spacing: Tokens.Espaco.s) {
            Image(systemName: simbolo)
                .font(.system(size: tamanho, weight: .regular))
            if let legenda {
                Text(legenda).font(Tokens.Fonte.miudo)
            }
        }
        .foregroundStyle(Tokens.Cor.tintaSobreSubstrato)
        .multilineTextAlignment(.center)
    }
}
