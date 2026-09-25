import SwiftUI

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
    /// 2.0: o pedido que abre a leitura específica. Só ao confirmar: cada
    /// leitura custa três chamadas da Luna e conta no limite diário.
    @State private var leituraPedida: String?

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

    var body: some View {
        NavigationStack {
            ZStack {
                PapelDaEdicao().ignoresSafeArea()

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
            .onSubmit(of: .search) { lerAgora() }
            .navigationDestination(item: $leituraPedida) { pedido in
                LeituraDaPeca(pedido: pedido)
            }
            .toolbar {
                if let aoFechar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: aoFechar)
                    }
                }
            }
        }
        .task {
            await carregar()
            #if DEBUG
            // Captura e teste: `-CanarioLeituraPedida "jaqueta napoleão"` abre a
            // leitura direto, sem digitar.
            let argumentos = ProcessInfo.processInfo.arguments
            if let i = argumentos.firstIndex(of: "-CanarioLeituraPedida"), i + 1 < argumentos.count {
                texto = argumentos[i + 1]
                lerAgora()
            }
            #endif
        }
        // Reroda a cada mudança do texto, com uma pausa antes: a busca é um
        // `ilike` sobre 172 mil títulos, e disparar uma por tecla digitada
        // gastaria o banco para jogar 19 respostas fora.
        .task(id: texto) { await procurarNaImprensa() }
        .tint(Edicao.bordo)
    }

    private var conteudo: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Edicao.entreFolhas) {
                if texto.isEmpty {
                    abertura
                } else {
                    // Uma peça fora da taxonomia ainda pode ser interpretada
                    // pela Leitura; o pedido humano segue inteiro.
                    botaoDaLeitura
                    if !casados.isEmpty {
                        if descreveUmaPeca { cardPecaCombinada }
                        cardAtributos
                    }
                    cardDaImprensa
                }
            }
            .padding(.horizontal, Edicao.margem)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var textoLimpo: String {
        texto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lerAgora() {
        guard Supabase.analiseRemotaHabilitada, textoLimpo.count >= 3 else { return }
        leituraPedida = String(textoLimpo.prefix(200))
    }

    @ViewBuilder
    private var botaoDaLeitura: some View {
        if Supabase.analiseRemotaHabilitada, textoLimpo.count >= 3 {
            Button(action: lerAgora) {
                HStack(spacing: 14) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(frase("Read “\(textoLimpo)” in the panel"))
                            .font(Edicao.Tipo.linha)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The reading finds the pieces, checks each one and shows the proof.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: Edicao.raio))
            .tint(Edicao.bordoCheio)
            .foregroundStyle(.white)
            .accessibilityHint(Text("Opens a reading with the pieces that prove each sentence"))
        }
    }

    /// O vocabulário real ocupa o estado inicial: não há exemplos fictícios nem
    /// uma tela vazia que dependa da pessoa adivinhar o que pode pesquisar.
    private var abertura: some View {
        Folha(espaco: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start with a word")
                    .font(Edicao.Tipo.secao)
                    .accessibilityAddTraits(.isHeader)
                Text("Combine words to describe a piece, like black leather coat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(gruposDoVocabulario.enumerated()), id: \.element.dimensao) { indice, grupo in
                if indice > 0 { CosturaDaEdicao() }
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: Traducao.rotuloDaDimensao(grupo.dimensao))
                        .font(Edicao.Tipo.linha)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    FlowLayout(espaco: 8) {
                        ForEach(grupo.termos) { termo in
                            Button {
                                atualizarTextoDaBusca(Traducao.rotuloExibido(termo))
                            } label: {
                                HStack(spacing: 7) {
                                    IconeDoTermo(termoId: termo.id, lado: 18)
                                        .accessibilityHidden(true)
                                    Text(verbatim: Traducao.rotuloExibido(termo))
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(Edicao.papel, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Search this attribute")
                        }
                    }
                }
            }
        }
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
            Folha {
                CabecalhoDaFolha(
                    titulo: Text(verbatim: descricaoDaBusca),
                    nota: frase("See similar pieces, attributes and the combined reading."),
                    abre: true)
            }
        }
        .buttonStyle(.plain)
    }

    /// A lista não antecipa números sem validar a cobertura da semana. Cada
    /// linha leva à tela que já aplica o portão completo antes de mostrar o índice.
    private var cardAtributos: some View {
        Folha(espaco: 0) {
            CabecalhoDaFolha(titulo: Text("Attributes"))
                .padding(.bottom, 8)
            ForEach(Array(casados.enumerated()), id: \.element.id) { index, termo in
                if index > 0 { CosturaDaEdicao() }
                NavigationLink {
                    RelatorioDoTermo(termo: termo)
                } label: {
                    LinhaDeAtributo(termoId: termo.id,
                                    rotulo: Traducao.rotuloAmigavel(termo, na: texto),
                                    dimensao: Traducao.rotuloDaDimensao(termo.dimensao),
                                    leitura: nil,
                                    mostraNumero: false, mostraFaixa: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// **In the press**: as matérias cujo TÍTULO contém o que foi digitado.
    ///
    /// O bloco só existe quando há matéria. Um cabeçalho "In the press" com
    /// "nada encontrado" embaixo ocupa a tela para não dizer nada -- e a
    /// revisão de UX já apontou excesso de texto duas vezes.
    @ViewBuilder
    private var cardDaImprensa: some View {
        if let r = imprensa, let manchete = ReferenciaEditorial.manchete(r) {
            Folha {
                CabecalhoDaFolha(titulo: Text("In the press"))
                Text(manchete)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(r.materias.enumerated()), id: \.element.id) { i, materia in
                    if i > 0 { CosturaDaEdicao() }
                    materiaEmLinha(materia)
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
        .frame(minHeight: 44)

        if let endereco = materia.endereco {
            Link(destination: endereco) {
                HStack(alignment: .top, spacing: 10) {
                    conteudo
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Edicao.bordo)
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
