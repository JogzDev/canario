import Foundation

/// As peças que o usuário já montou, guardadas no aparelho para ele não ter
/// que remontar.
///
/// ## O problema que isto resolve
///
/// Da revisão de 03/08: *"Vamos pensar que ele vai ser viciado no nosso app e
/// vai adicionar 5000 peças, será que não tá desgastante demais e pouco visual
/// fazer essa seleção repetidamente?"* Está. Hoje o app esquece tudo ao trocar
/// de aba, e a aba Comparar — que por desenho *"pressupõe peças já
/// analisadas"* — não tinha de onde tirá-las. Era a origem do *"a tab Comparar
/// tá bem confusa"* do mesmo relatório.
///
/// ## Onde fica a linha da §34
///
/// A §34 exclui *"closet/monitoramento contínuo por peça"*, e o time cogitou
/// uma aba **Armário**. A CANARIO.md já respondia a isso: aquela aba *"exigiria
/// entrada revogatória própria"*. A diferença não é de nome, é de promessa:
///
/// * **Armário** promete o app olhando a sua peça ao longo do tempo. Não
///   sustentamos: a peça é sua, não está no painel, e não temos como segui-la.
///   Prometer isso seria afirmar o que não foi medido (regra 2).
/// * **Minhas peças** é lista de trabalho. Guarda **só o que você digitou** —
///   os atributos e o contexto — e nada do que o motor calculou. Todo número é
///   recalculado do dado de hoje quando você abre. Sem alerta, sem "sua peça
///   subiu 3%", sem histórico por peça.
///
/// Essa distinção não é comentário: está no tipo. `PecaSalva` não tem campo
/// para índice, estado, z nem data de leitura, e o teste correspondente falha
/// se alguém acrescentar um.
///
/// ## Fica no aparelho
///
/// A §34 não tem conta de usuário na v1, então não há para onde sincronizar —
/// e não haveria por quê. Grava em Application Support, fora do backup de
/// documentos do usuário, em JSON legível.
struct PecaSalva: Codable, Equatable, Identifiable {

    /// Estável entre execuções: é ele que a aba Comparar usa para escolher.
    let id: UUID
    /// Como o usuário chama esta peça. Vazio vira um nome derivado dos termos.
    var apelido: String
    /// Os termos da taxonomia que o usuário confirmou. Só isso — a taxonomia é
    /// do servidor, e guardar o rótulo aqui deixaria a peça mentir quando o
    /// rótulo mudasse.
    var termoIds: [String]
    /// Contexto opcional da §27, que nunca bloqueia.
    var precoAlvo: Double?
    var canal: String?
    var criadaEm: Date

    init(id: UUID = UUID(), apelido: String = "", termoIds: [String],
         precoAlvo: Double? = nil, canal: String? = nil,
         criadaEm: Date = Date()) {
        self.id = id
        self.apelido = apelido
        self.termoIds = termoIds
        self.precoAlvo = precoAlvo
        self.canal = canal
        self.criadaEm = criadaEm
    }

    /// Nome para a lista quando o usuário não deu um. Usa os rótulos vindos do
    /// servidor, e cai nos ids só se a taxonomia não estiver carregada.
    func nome(comRotulos rotulos: [String: String]) -> String {
        if !apelido.trimmingCharacters(in: .whitespaces).isEmpty { return apelido }
        let partes = termoIds.compactMap { rotulos[$0] ?? $0 }
        return partes.isEmpty ? "Peça sem atributos" : partes.joined(separator: " · ")
    }
}

/// Guarda e devolve as peças. Ator porque a tela toca nela de várias tarefas.
actor PecasSalvas {
    static let shared = PecasSalvas()

    /// Teto deliberado. O relatório da revisão imaginou 5000 peças; 5000 peças
    /// numa lista sem hierarquia é o mesmo problema de tela cheia, em outro
    /// lugar. Enquanto não houver pasta ou busca dentro da lista, o teto evita
    /// prometer uma organização que não existe.
    static let teto = 200

    private var itens: [PecaSalva] = []
    private var carregado = false
    private let arquivo: URL?

    init(arquivo: URL? = nil) {
        if let arquivo {
            self.arquivo = arquivo
        } else {
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.arquivo = base?.appendingPathComponent("pecas_salvas.json")
        }
    }

    func todas() -> [PecaSalva] {
        carregarSeNecessario()
        // Mais recente primeiro: a peça que você acabou de montar é a que você
        // quer ver.
        return itens.sorted { $0.criadaEm > $1.criadaEm }
    }

    @discardableResult
    func salvar(_ peca: PecaSalva) -> Bool {
        carregarSeNecessario()
        if let i = itens.firstIndex(where: { $0.id == peca.id }) {
            itens[i] = peca
        } else {
            guard itens.count < Self.teto else { return false }
            itens.append(peca)
        }
        gravar()
        return true
    }

    func apagar(_ id: UUID) {
        carregarSeNecessario()
        itens.removeAll { $0.id == id }
        gravar()
    }

    func apagarTudo() {
        carregarSeNecessario()
        itens.removeAll()
        gravar()
    }

    private func carregarSeNecessario() {
        guard !carregado else { return }
        carregado = true
        guard let arquivo, let dados = try? Data(contentsOf: arquivo) else { return }
        // Arquivo corrompido não derruba o app nem apaga o que sobrou: começa
        // vazio e a próxima gravação reescreve.
        itens = (try? JSONDecoder().decode([PecaSalva].self, from: dados)) ?? []
    }

    private func gravar() {
        guard let arquivo else { return }
        let cod = JSONEncoder()
        cod.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let dados = try? cod.encode(itens) else { return }
        try? dados.write(to: arquivo, options: .atomic)
    }
}
