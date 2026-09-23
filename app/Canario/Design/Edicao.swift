import SwiftUI
import UIKit
import Charts

// O PADRÃO DA EDIÇÃO — sistema visual do Seam (2.0)
// ================================================
//
// Nasceu no estudo v4 (17/09/2026) e é a única fonte de cor, tipo e forma das
// telas da 2.0. Nenhuma tela declara fonte, raio ou cor por conta própria.
//
// COR — cada uma tem um papel, e só um.
//
//   papel ........ fundo de toda tela, pontilhado
//   cartão ....... toda folha de conteúdo
//   tinta ........ texto: label e secondaryLabel do sistema
//   bordô ........ só o que se toca: botão, link, aba ativa, favorito
//   caneta ....... só anotação de dado: série, ponto, costura, chamada
//   marca-texto .. no máximo um destaque por tela
//   substrato .... só atrás de peça (A54)
//
//   Direção (acima ou abaixo da faixa) não tem cor: é dita por seta e texto.
//   As quatro fontes de dado usam os riscadores do caderno — caneta, sanguínea,
//   musgo e grafite —, e essas quatro só aparecem em gráfico e legenda.
//
// TIPO — New York (serif) NOMEIA; SF INFORMA. Sempre com Dynamic Type.
//
// FORMA — Folha (cartão com costura tracejada), Capa (foto sem costura) e
// Peça (substrato cinza; recorte entra inteiro, foto sem recorte ocupa o
// quadro). Linhas dentro de uma folha se separam por costura, nunca Divider.
//
// Inegociável: A53 (PT/EN em todo texto), A54 (peça sobre o substrato), A55
// (aba nomeia lugar) e A56 (captura de cor constante intacta).

enum Edicao {
    // MARK: Cor

    /// Ação. ≥ 4,5:1 contra `papel` e `cartao` nos dois temas.
    static let bordo = cor(0x8A1C2E, 0xF0899A)
    /// Anotação de dado: a esferográfica azul do caderno.
    static let caneta = cor(0x2743D6, 0x8FA2FF)
    static let marcaTexto = cor(0xF7E27A, 0x5E5421)
    /// Papel de caderno: quente no claro, grafite no escuro.
    static let papel = cor(0xF7F5EF, 0x1A1917)
    static let cartao = cor(0xFFFFFF, 0x262523)

    /// Os riscadores das fontes de dado. Só em gráfico e legenda.
    static let sanguinea = cor(0xA84A24, 0xF0A07C)
    static let musgo = cor(0x55713A, 0xA9C98A)
    static let grafite = cor(0x6A6760, 0xB9B5AC)

    static func tintaDaFonte(_ fonte: String) -> Color {
        switch fonte {
        case "busca": return caneta
        case "editorial_br": return sanguinea
        case "editorial_intl": return musgo
        default: return grafite
        }
    }

    static func cor(_ claro: UInt32, _ escuro: UInt32) -> Color {
        Color(UIColor { tracos in
            let v = tracos.userInterfaceStyle == .dark ? escuro : claro
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }

    // MARK: Tipo

    enum Tipo {
        /// Título de matéria, nome da peça, nome do atributo, título do Estúdio.
        static let destaque = Font.system(.largeTitle, design: .serif, weight: .bold)
        /// A história da capa.
        static let manchete = Font.system(.title, design: .serif, weight: .bold)
        /// Seção fora de folha e história secundária.
        static let secao = Font.system(.title2, design: .serif, weight: .bold)
        /// Título de folha.
        static let titulo = Font.system(.title3, design: .serif, weight: .bold)
        /// Nome de peça numa grade ou fileira.
        static let nome = Font.system(.headline, design: .serif)
        /// A chamada acima de uma manchete ("De volta ao estoque").
        static let chamada = Font.footnote.weight(.semibold)
        /// Manchete de terceiros, citada: a única linha em New York que não é nome.
        static let citacao = Font.system(.body, design: .serif)
        /// Título de linha dentro de folha.
        static let linha = Font.headline
        static let numero = Font.body.weight(.semibold).monospacedDigit()
        static let numeroGrande = Font.title.weight(.semibold).monospacedDigit()
        /// Número de uma faixa de estatísticas lado a lado.
        static let estatistica = Font.title3.weight(.semibold).monospacedDigit()
    }

    // MARK: Forma

    static let raio: CGFloat = 16
    static let raioDaPeca: CGFloat = 12
    /// Margem lateral de toda tela.
    static let margem: CGFloat = 20
    /// Distância entre folhas.
    static let entreFolhas: CGFloat = 24
}

// MARK: - Papel

/// Papel pontilhado. Discreto: 11% de tinta no claro, 8% no escuro.
struct PapelDaEdicao: View {
    @Environment(\.colorScheme) private var esquema

    var body: some View {
        Canvas { contexto, tamanho in
            let passo: CGFloat = 18
            let raio: CGFloat = 0.9
            let cor = esquema == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.11)
            var y = passo / 2
            while y < tamanho.height {
                var x = passo / 2
                while x < tamanho.width {
                    contexto.fill(Path(ellipseIn: CGRect(x: x - raio, y: y - raio,
                                                         width: raio * 2, height: raio * 2)),
                                  with: .color(cor))
                    x += passo
                }
                y += passo
            }
        }
        .background(Edicao.papel)
        .accessibilityHidden(true)
    }
}

extension View {
    /// O fundo de toda tela da edição.
    func papelDaEdicao() -> some View {
        background { PapelDaEdicao().ignoresSafeArea() }
    }
}

// MARK: - Folha

/// A folha: todo agrupamento de conteúdo, em toda tela.
struct Folha<Conteudo: View>: View {
    var respiro: CGFloat = 20
    var espaco: CGFloat = 12
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: espaco) {
            conteudo
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(respiro)
        .background {
            RoundedRectangle(cornerRadius: Edicao.raio, style: .continuous)
                .fill(Edicao.cartao)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .overlay { CosturaDaFolha() }
        .foregroundStyle(.primary)
    }
}

/// A margem de costura por dentro da folha.
struct CosturaDaFolha: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Edicao.raio - 6, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(Edicao.caneta.opacity(0.26))
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// O título de uma folha: New York, com símbolo e nota opcionais.
struct CabecalhoDaFolha: View {
    let titulo: Text
    var nota: String?
    var simbolo: String?
    var chamada: String?
    /// Quando o cabeçalho inteiro é uma porta.
    var abre = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let chamada { ChamadaDaEdicao(texto: chamada) }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let simbolo {
                        Image(systemName: simbolo)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Edicao.caneta)
                    }
                    titulo
                        .font(Edicao.Tipo.titulo)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if let nota {
                    Text(nota)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if abre {
                Spacer(minLength: 8)
                SetaDaLinha()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Separador de linhas dentro de uma folha.
struct CosturaDaEdicao: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: g.size.width, y: 0))
            }
            .stroke(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

struct SetaDaLinha: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Capa

extension View {
    /// Cartão de foto: mesmo raio e sombra da folha, sem costura.
    func capaDaEdicao() -> some View {
        background(Edicao.cartao)
            .clipShape(RoundedRectangle(cornerRadius: Edicao.raio, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

/// A chamada acima de uma manchete.
struct ChamadaDaEdicao: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(Edicao.Tipo.chamada)
            .foregroundStyle(Edicao.caneta)
    }
}

// MARK: - Peça

/// A foto de uma peça da pessoa, sempre sobre o substrato (A54).
///
/// **Nunca dois fundos.** O aparelho recorta a peça ao salvar
/// (`MiniaturaLocal`, primeiro plano da Vision) e guarda PNG transparente: esse
/// entra inteiro, com respiro, e o cinza é o único fundo. Quando não houve
/// recorte — a pessoa escolheu "Foto inteira", ou a Vision não achou sujeito —
/// a foto já traz o próprio fundo, e desenhá-la encolhida sobre o cinza dava a
/// moldura dupla que o JP apontou no Closet. Aí ela ocupa o quadro todo.
struct ImagemDaPeca: View {
    let imagem: UIImage?
    var raio: CGFloat = Edicao.raioDaPeca
    var respiro: CGFloat = 12
    var simbolo = "tshirt"

    var body: some View {
        Tokens.Cor.substratoDaPeca
            .overlay {
                if let imagem {
                    if Self.recortada(imagem) {
                        Image(uiImage: imagem)
                            .resizable()
                            .scaledToFit()
                            .padding(respiro)
                    } else {
                        Image(uiImage: imagem)
                            .resizable()
                            .scaledToFill()
                    }
                } else {
                    PecaSemFoto(simbolo: simbolo, tamanho: 30)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
    }

    static func recortada(_ imagem: UIImage) -> Bool {
        switch imagem.cgImage?.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast: return true
        default: return false
        }
    }
}

/// Foto de produto do painel: sempre foto inteira de loja, ocupa o quadro.
struct FotoDoPainel: View {
    let endereco: String?

    var body: some View {
        Tokens.Cor.substratoDaPeca
            .overlay { PecaSemFoto(simbolo: "hanger", tamanho: 22) }
            .overlay {
                ImagemRemota(endereco: endereco.flatMap(URL.init(string:)), modo: .fill)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Atributo

/// A linha de um atributo, igual em toda tela: Esta semana, peça, busca.
///
/// Ícone do termo, nome, dimensão e faixa por escrito, número à direita. A
/// faixa sai de `Leitura.faixa`, a mesma régua do resto do app — a busca tinha
/// limiares próprios e chamava +1,2 de "muito acima" enquanto o painel da peça
/// chamava o mesmo número de "acima".
struct LinhaDeAtributo: View {
    let termoId: String
    let rotulo: String
    let dimensao: String?
    let leitura: Double?
    var serie: [PontoSerie] = []
    var destacar = false
    var abre = true
    /// Onde a tela antes não mostrava número, a linha também não mostra.
    var mostraNumero = true
    /// A busca do Google já desenha a série; ali a faixa escrita sobra.
    var mostraFaixa = true

    var body: some View {
        HStack(spacing: 12) {
            IconeDoTermo(termoId: termoId, lado: 22)
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                // A dimensão pequena ao lado do nome, como legenda: "Preto"
                // sozinho não dizia se era a cor. Um `Text` só, para quebrar
                // junto com o nome em vez de empurrá-lo.
                Text("\(Text(rotulo).font(Edicao.Tipo.linha).foregroundStyle(.primary)) \(Text(dimensao ?? "").font(.footnote).foregroundStyle(.secondary))")
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if mostraFaixa { apoio }
            }
            Spacer(minLength: 8)
            if serie.count >= 3 {
                SerieMarcadaDaEdicao(serie: serie)
                    .frame(width: 56, height: 30)
            }
            if mostraNumero {
                NumeroDaEdicao(valor: leitura, destacar: destacar)
            }
            if abre { SetaDaLinha() }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(leitura.map { Leitura.faixa($0).rotulo } ?? frase("No reading yet"))
    }

    /// A faixa por escrito, com a seta. Um `Text` só, para quebrar como frase.
    private var apoio: some View {
        Group {
            if let leitura {
                let faixa = Leitura.faixa(leitura)
                Text("\(Image(systemName: Self.seta(faixa))) \(faixa.rotulo)")
            } else {
                Text(frase("No reading yet"))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    static func seta(_ faixa: Leitura.Faixa) -> String {
        switch faixa {
        case .muitoAcima: return "arrow.up"
        case .acima, .poucoAcima: return "arrow.up.right"
        case .habitual: return "equal"
        case .poucoAbaixo, .abaixo: return "arrow.down.right"
        case .muitoAbaixo: return "arrow.down"
        }
    }
}

/// O número de uma leitura, com o marca-texto quando é o destaque da tela.
struct NumeroDaEdicao: View {
    let valor: Double?
    var destacar = false

    var body: some View {
        // Duas casas, como na tela do atributo. Com uma, −0,98 saía "−1.0"
        // ao lado de "um pouco abaixo" — e −1 já é "abaixo" na régua.
        Text(valor.map { Leitura.numero($0, casas: 2, sinal: abs($0) >= 0.005) } ?? "—")
            // A frase ao lado lidera; o número fica como explicação (JP, 23/09).
            .font(destacar ? Edicao.Tipo.numero : .subheadline.monospacedDigit())
            .foregroundStyle(destacar ? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                if destacar {
                    Capsule().fill(Edicao.marcaTexto)
                        .rotationEffect(.degrees(-3))
                        .padding(.vertical, 2)
                }
            }
            .frame(minWidth: 56, alignment: .trailing)
    }
}

/// Estatísticas lado a lado: número em cima, o que ele conta embaixo.
struct FaixaDeNumeros: View {
    let itens: [(valor: String, rotulo: String)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(itens.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.valor)
                        .font(Edicao.Tipo.estatistica)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item.rotulo)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Conta

/// O menu lateral vira o padrão do sistema: botão de conta na barra e sheet
/// com lista agrupada, como nos Ajustes.
struct ContaDaEdicao: View {
    let escolher: (EntradaDoMenu) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(EntradaDoMenu.acoes, id: \.self) { linha($0) }
                }
                Section {
                    ForEach(EntradaDoMenu.leituras, id: \.self) { linha($0) }
                }
            }
            .navigationTitle(Text("Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Edicao.bordo)
    }

    private func linha(_ entrada: EntradaDoMenu) -> some View {
        Button { escolher(entrada) } label: {
            Label {
                Text(entrada.titulo)
            } icon: {
                Image(systemName: Self.simbolo(entrada)).foregroundStyle(Edicao.bordo)
            }
        }
        .tint(.primary)
    }

    static func simbolo(_ entrada: EntradaDoMenu) -> String {
        switch entrada {
        case .favoritos: return "heart"
        case .conta: return "person.crop.circle"
        case .ajustes: return "gearshape"
        case .termos: return "doc.text"
        case .privacidade: return "hand.raised"
        case .perguntas: return "questionmark.circle"
        }
    }
}

extension View {
    @ViewBuilder func subtituloDaEdicao(_ texto: String?) -> some View {
        if #available(iOS 26.0, *), let texto {
            navigationSubtitle(texto)
        } else {
            self
        }
    }

    @ViewBuilder func origemDoZoom(_ id: String, em ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { matchedTransitionSource(id: id, in: ns) } else { self }
    }

    @ViewBuilder func destinoDoZoom(_ id: String, em ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { navigationTransition(.zoom(sourceID: id, in: ns)) } else { self }
    }
}

// MARK: - Série

/// A série marcada a caneta, com o zero tracejado e o último ponto cheio.
struct SerieMarcadaDaEdicao: View {
    let serie: [PontoSerie]

    var body: some View {
        let pontos = Array(serie.suffix(10).enumerated())
        Chart {
            RuleMark(y: .value("Usual", 0))
                .foregroundStyle(Color(.separator))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            ForEach(pontos, id: \.offset) { i, p in
                LineMark(x: .value("Week", i), y: .value("Reading", p.z ?? 0))
                    .foregroundStyle(Edicao.caneta)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Week", i), y: .value("Reading", p.z ?? 0))
                    .foregroundStyle(Edicao.caneta)
                    .symbolSize(i == pontos.count - 1 ? 30 : 9)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: -3...3)
        .accessibilityHidden(true)
    }
}

// MARK: - Imprensa

struct CartaoDeImprensaDaEdicao: View {
    let manchetes: [PontoSerie.Meta.Exemplo]

    var body: some View {
        Folha(espaco: 6) {
            CabecalhoDaFolha(titulo: Text("In the press"))
                .padding(.bottom, 4)
            ForEach(manchetes, id: \.titulo) { m in
                let url = m.url.flatMap(URL.init(string:))
                let linha = HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: m.veiculo)
                            .font(Edicao.Tipo.chamada)
                            .foregroundStyle(.secondary)
                        // Manchete não se traduz: é citação da fonte (A53).
                        Text(verbatim: m.titulo)
                            .font(Edicao.Tipo.citacao)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if url != nil {
                        Image(systemName: "arrow.up.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())

                if let url {
                    Link(destination: url) { linha }.buttonStyle(.plain)
                } else {
                    linha
                }
                if m.titulo != manchetes.last?.titulo { CosturaDaEdicao() }
            }
        }
    }
}
