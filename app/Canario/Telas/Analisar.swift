import SwiftUI
import UIKit

/// Aba **Analisar** (§27): entrada por busca textual.
///
/// A §11 é explícita: "a barra de busca do app nunca vira filtro de texto cru".
/// A string do usuário é traduzida para termos da taxonomia via rótulos,
/// sinônimos e as mesmas palavras que o coletor usa; o que não casar gera
/// resposta honesta, em vez de silêncio ou de resultado vazio.
struct Analisar: View {
    var aoFechar: (() -> Void)?
    @State private var termos: [Termo] = []
    @State private var texto = ""
    @State private var carregando = true
    @State private var erro: String?
    /// A58: as matérias que contêm a expressão literal, e não a tradução dela.
    @State private var imprensa: ReferenciaEditorial.Resposta?
    @State private var imprensaFalhou = false

    /// A tradução vive em `Traducao`, que é testada. Aqui a tela só consome.
    private var casados: [Termo] {
        Traducao.termos(para: texto, em: termos)
    }

    /// Quando a busca descreve uma peça, e não um atributo isolado.
    private var descreveUmaPeca: Bool {
        Set(casados.map(\.dimensao)).count >= 2
    }

    private var descricaoDaBusca: String {
        Traducao.descricaoAmigavel(casados, consulta: texto)
    }

    private let corLinha = Color.black.opacity(0.08)

    var body: some View {
        NavigationStack {
            ZStack {
                PapelDaBusca().ignoresSafeArea()

                Group {
                    if carregando {
                        Carregando()
                    } else if let erro {
                        FalhaDeRede(mensagem: erro) { Task { await carregar() } }
                    } else {
                        conteudo
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: textoDaBusca,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search by garment, fabric, cut, pattern…")
            .toolbar {
                if let aoFechar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: aoFechar)
                    }
                }
            }
        }
        .task { await carregar() }
        // Reroda a cada mudança do texto, com uma pausa antes: a busca é um
        // `ilike` sobre 172 mil títulos, e disparar uma por tecla digitada
        // gastaria o banco para jogar 19 respostas fora.
        .task(id: texto) { await procurarNaImprensa() }
        .tint(CorDaBusca.bordo)
        // A busca também abre sobre a aba de mercado, que usa outro esquema.
        // Fixar o território evita herdar cores de uma tela que ficou atrás.
        .territorio(.armario)
    }

    @ViewBuilder
    private var conteudo: some View {
        if texto.isEmpty {
            abertura
        } else if casados.isEmpty {
            ScrollView {
                VStack(spacing: 20) {
                    CoberturaInsuficiente(
                        titulo: "This term isn't tracked yet",
                        explicacao: "“\(texto)” is outside the reviewed vocabulary, so there is no market reading for it yet.",
                        oQueTem: frase("Try: \(sugestoes.joined(separator: ", "))")
                    )
                    // O vocabulário não cobre a expressão, mas a imprensa pode
                    // tê-la escrito -- foi exatamente o caso de "Napoleon
                    // Jacket". Este é o lugar onde a busca deixa de terminar
                    // em "não temos isso".
                    cardDaImprensa
                }
                .padding(Tokens.Espaco.m)
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    if descreveUmaPeca {
                        cardPecaCombinada
                    }

                    cardAtributos
                    // Depois dos atributos, e não antes: a leitura de mercado
                    // é o que o app mede; a matéria é referência de fora.
                    cardDaImprensa
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }

    /// O vocabulário real ocupa o estado inicial: não há exemplos fictícios nem
    /// uma tela vazia que dependa da pessoa adivinhar o que pode pesquisar.
    private var abertura: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start with a word")
                        .font(.system(.title, design: .serif, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Combine words to describe a piece, like black leather coat.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(gruposDoVocabulario, id: \.dimensao) { grupo in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: Traducao.rotuloDaDimensao(grupo.dimensao))
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        FlowLayout(espaco: 8) {
                            ForEach(grupo.termos) { termo in
                                Button {
                                    atualizarTextoDaBusca(Traducao.rotuloExibido(termo))
                                } label: {
                                    Text(verbatim: Traducao.rotuloExibido(termo))
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(CorDaBusca.papel, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Search this attribute")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .modifier(FolhaDaBusca())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var gruposDoVocabulario: [(dimensao: String, termos: [Termo])] {
        let ordem = ["categoria", "cor", "estampa", "tecido", "comprimento",
                     "silhueta", "cintura", "estetica"]
        let extras = Set(termos.map(\.dimensao))
            .subtracting(ordem)
            .subtracting(["motivo_estampa"])
            .sorted()
        return (ordem + extras).compactMap { dimensao in
            var vistos = Set<String>()
            let disponiveis = termos.filter {
                $0.dimensao == dimensao
                    && vistos.insert(Traducao.rotuloExibido($0)).inserted
            }
            return disponiveis.isEmpty ? nil : (dimensao, disponiveis)
        }
    }

    /// A combinação é uma porta para a leitura da coorte, nunca uma média dos
    /// índices dos atributos. Essa média não é histórico da peça pesquisada.
    private var cardPecaCombinada: some View {
        NavigationLink {
            RelatorioDaPeca(termos: casados, pecaSalva: nil,
                           descricaoAmigavel: descricaoDaBusca)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(descricaoDaBusca)
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CorDaBusca.bordo)
                }
                Text("See similar pieces, attributes and the combined reading.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .modifier(FolhaDaBusca())
        }
        .buttonStyle(.plain)
    }

    /// A lista não antecipa números sem validar a cobertura da semana. Cada
    /// linha leva à tela que já aplica o portão completo antes de mostrar o índice.
    private var cardAtributos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attributes")
                .font(.system(.title3, design: .serif, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(casados.enumerated()), id: \.element.id) { index, termo in
                    NavigationLink {
                        RelatorioDoTermo(termo: termo)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: Traducao.rotuloAmigavel(termo, na: texto))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(verbatim: Traducao.rotuloDaDimensao(termo.dimensao))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CorDaBusca.bordo)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if index < casados.count - 1 {
                        Rectangle()
                            .fill(corLinha)
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(20)
        .modifier(FolhaDaBusca())
    }

    /// **In the press**: as matérias cujo TÍTULO contém o que foi digitado.
    ///
    /// O bloco só existe quando há matéria. Um cabeçalho "In the press" com
    /// "nada encontrado" embaixo ocupa a tela para não dizer nada -- e a
    /// revisão de UX já apontou excesso de texto duas vezes.
    @ViewBuilder
    private var cardDaImprensa: some View {
        if let r = imprensa, let manchete = ReferenciaEditorial.manchete(r) {
            VStack(alignment: .leading, spacing: 12) {
                Text("In the press")
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(manchete)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(r.materias.enumerated()), id: \.element.id) { i, materia in
                        materiaEmLinha(materia)
                        if i < r.materias.count - 1 {
                            Rectangle().fill(corLinha).frame(height: 1)
                        }
                    }
                }

                if let recorte = ReferenciaEditorial.recorte(r) {
                    Text(recorte)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(ReferenciaEditorial.ondeEstaOTexto)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Controle deterministico, presente apenas no processo de
                // UI test, para trocar A por B em uma unica mutacao do estado.
                // Digitar/apagar caractere por caractere passaria por uma
                // consulta curta e esconderia o defeito que o teste procura.
                if ImprensaDeTeste.caso == "troca" {
                    Button("Switch press query") { atualizarTextoDaBusca("segunda") }
                        .accessibilityIdentifier("trocar-consulta-editorial")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FolhaDaBusca())
        } else if imprensaFalhou {
            // Falha declarada, em voz baixa: este bloco é referência de fora,
            // não o resultado da busca, e não pode virar alarme vermelho no
            // meio de uma tela que respondeu o que sabia.
            Text("Press references could not be loaded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("imprensa-falhou")
        }
    }

    /// Uma matéria: título, procedência e o link que abre a fonte.
    @ViewBuilder
    private func materiaEmLinha(_ materia: ReferenciaEditorial.Materia) -> some View {
        let conteudo = VStack(alignment: .leading, spacing: 4) {
            Text(materia.titulo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !materia.procedencia.isEmpty {
                Text(materia.procedencia)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)

        if let endereco = materia.endereco {
            Link(destination: endereco) {
                HStack(alignment: .top, spacing: 10) {
                    conteudo
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CorDaBusca.bordo)
                        .padding(.top, 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(materia.titulo), \(materia.procedencia), opens the article")
        } else {
            conteudo
        }
    }

    /// Limpa a resposta anterior na mesma mutacao que muda a pergunta.
    ///
    /// Fazer essa limpeza apenas dentro de `.task(id:)` deixa uma janela entre
    /// o `Binding` mudar e a nova tarefa ser agendada pelo SwiftUI. Nesse
    /// intervalo a tela ja mostra a pergunta B, mas ainda associa a ela a
    /// materia de A. O binding explicito fecha essa janela tanto para teclado
    /// quanto para mudancas programaticas usadas pelos testes.
    private var textoDaBusca: Binding<String> {
        Binding(
            get: { texto },
            set: { atualizarTextoDaBusca($0) }
        )
    }

    private func atualizarTextoDaBusca(_ novoTexto: String) {
        guard novoTexto != texto else { return }
        imprensa = nil
        imprensaFalhou = false
        texto = novoTexto
    }

    /// Pergunta ao banco pela expressão LITERAL, em paralelo com a tradução.
    ///
    /// Silêncio em dois casos, e só nestes dois: quando a RPC ainda não existe
    /// no servidor (a A58 é publicada junto com esta versão do app, então um
    /// aparelho atualizado antes do banco receberia 404 a cada tecla) e quando
    /// a própria tarefa foi cancelada pela tecla seguinte.
    private func procurarNaImprensa() async {
        let expressao = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expressao.count >= 3 else {
            imprensa = nil
            imprensaFalhou = false
            return
        }
        // A materia pertence a pergunta anterior. Ela deixa a tela no mesmo
        // instante em que uma nova expressao valida comeca, antes do debounce
        // e da rede; mante-la ali faria o titulo A parecer resposta de B por
        // ate todo o timeout da requisicao.
        imprensa = nil
        imprensaFalhou = false
        // A pausa é a primeira proteção: se a pessoa continuar digitando, esta
        // tarefa é cancelada antes de chegar ao banco.
        do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
        guard !Task.isCancelled else { return }
        do {
            let r = try await buscar(expressao)
            guard aindaVale(expressao) else { return }
            imprensa = r
            imprensaFalhou = false
        } catch {
            guard aindaVale(expressao) else { return }
            imprensa = nil
            imprensaFalhou = !aFalhaEEsperada(error)
        }
    }

    /// A resposta só escreve na tela se a pergunta ainda for esta.
    ///
    /// Duas condições, e as duas são necessárias. O cancelamento cobre a
    /// tarefa que o SwiftUI já derrubou; a identidade cobre a janela em que
    /// ela ainda não foi derrubada — uma consulta lenta de "lenta" respondendo
    /// depois da resposta rápida de "rapida" apagaria a segunda com a
    /// primeira, e a tela mostraria a matéria de uma pergunta que a pessoa já
    /// abandonou.
    private func aindaVale(_ expressao: String) -> Bool {
        !Task.isCancelled
            && expressao == texto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buscar(_ expressao: String) async throws
    -> ReferenciaEditorial.Resposta {
        if ImprensaDeTeste.ativa { return try await ImprensaDeTeste.responder(expressao) }
        return try await Supabase.shared.chamar(
            "buscar_referencia_editorial", ["expressao": expressao, "limite": 5])
    }

    /// Duas falhas não viram aviso: a função que ainda não existe no servidor
    /// e o cancelamento pela tecla seguinte.
    ///
    /// O 404 é restrito ao **PGRST202**, que é o código do PostgREST para
    /// função inexistente. Calar em qualquer 404 esconderia um caminho errado,
    /// uma rota removida ou um proxy fora do ar — falhas reais, com a mesma
    /// aparência e outra causa.
    private func aFalhaEEsperada(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let erro = error as? Supabase.Falha {
            switch erro {
            case .resposta(let codigo, let corpo):
                return codigo == 404
                    && Supabase.Falha.codigoDoCorpo(corpo) == "PGRST202"
            case .rede(let causa): return (causa as? URLError)?.code == .cancelled
            default: return false
            }
        }
        return (error as? URLError)?.code == .cancelled
    }

    private var sugestoes: [String] {
        var vistas = Set<String>()
        return termos.filter { vistas.insert($0.dimensao).inserted }
            .prefix(5).map(Traducao.rotuloExibido)
    }

    private func carregar() async {
        carregando = true
        erro = nil
        if ProcessInfo.processInfo.arguments.contains("-CanarioUITestBuscaVocabulario") {
            termos = [
                Termo(id: "vestido", rotulo: "Dress", dimensao: "categoria",
                      exclusiva: true, sinonimos: nil, semPernaBusca: nil,
                      palavrasPt: nil, palavrasEn: nil),
                Termo(id: "preto", rotulo: "Black", dimensao: "cor",
                      exclusiva: false, sinonimos: nil, semPernaBusca: nil,
                      palavrasPt: nil, palavrasEn: nil),
            ]
            carregando = false
            return
        }
        do {
            termos = try await CatalogoDeTermos.shared.carregar()
        } catch is CancellationError {
            return
        } catch {
            erro = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        carregando = false
    }
}

/// Primeiro recorte do sistema visual da 2.0. As mesmas superfícies serão
/// extraídas para o design compartilhado quando os três percursos estiverem
/// aprovados; por ora não mudam telas que ainda não passaram pelo redesenho.
private enum CorDaBusca {
    static let papel = dinamica(claro: 0xF7F5EF, escuro: 0x1A1917)
    static let cartao = dinamica(claro: 0xFFFFFF, escuro: 0x262523)
    static let bordo = dinamica(claro: 0x8A1C2E, escuro: 0xF0899A)
    static let costura = dinamica(claro: 0x2743D6, escuro: 0x8FA2FF)

    private static func dinamica(claro: UInt32, escuro: UInt32) -> Color {
        Color(UIColor { tracos in
            let valor = tracos.userInterfaceStyle == .dark ? escuro : claro
            return UIColor(red: CGFloat((valor >> 16) & 0xFF) / 255,
                           green: CGFloat((valor >> 8) & 0xFF) / 255,
                           blue: CGFloat(valor & 0xFF) / 255, alpha: 1)
        })
    }
}

private struct PapelDaBusca: View {
    @Environment(\.colorScheme) private var esquema

    var body: some View {
        Canvas { contexto, tamanho in
            let ponto = esquema == .dark ? Color.white.opacity(0.08)
                : Color.black.opacity(0.10)
            for y in stride(from: CGFloat(9), through: tamanho.height, by: 18) {
                for x in stride(from: CGFloat(9), through: tamanho.width, by: 18) {
                    contexto.fill(Path(ellipseIn: CGRect(x: x, y: y,
                                                         width: 1.5, height: 1.5)),
                                  with: .color(ponto))
                }
            }
        }
        .background(CorDaBusca.papel)
        .accessibilityHidden(true)
    }
}

private struct FolhaDaBusca: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CorDaBusca.cartao)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(CorDaBusca.costura.opacity(0.25))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
