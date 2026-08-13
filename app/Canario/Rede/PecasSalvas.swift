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
/// A §34 não tem sincronização na v1. Grava em Application Support, excluído
/// de backup. Desde A18, uma peça pode apontar para uma **miniatura local**:
/// PNG transparente quando o recorte local é confiável, ou JPEG reamostrado
/// quando não é; ambos sem metadados e apagados junto com a peça. A foto
/// original continua não sendo copiada para o app.
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
    /// Nome opaco da miniatura local. Nunca contém caminho, URL de origem ou imagem
    /// em base64; `PecasSalvas` valida o nome antes de abrir.
    var miniaturaArquivo: String?
    /// Escolha explícita do usuário. `nil` mantém compatibilidade com peças
    /// criadas antes de Favorites existir e não ocupa o JSON até ser usada.
    var favorita: Bool?
    /// Rejeição explícita da vitrine atual de similares. É escolha do usuário,
    /// não leitura calculada do motor, e pode ser persistida localmente.
    var similaresRejeitados: Bool?

    init(id: UUID = UUID(), apelido: String = "", termoIds: [String],
         precoAlvo: Double? = nil, canal: String? = nil,
         criadaEm: Date = Date(), miniaturaArquivo: String? = nil,
         favorita: Bool? = nil, similaresRejeitados: Bool? = nil) {
        self.id = id
        self.apelido = apelido
        self.termoIds = termoIds
        self.precoAlvo = precoAlvo
        self.canal = canal
        self.criadaEm = criadaEm
        self.miniaturaArquivo = miniaturaArquivo
        self.favorita = favorita
        self.similaresRejeitados = similaresRejeitados
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
    private let pastaDeMiniaturas: URL?

    init(arquivo: URL? = nil, pastaDeMiniaturas: URL? = nil) {
        if let arquivo {
            self.arquivo = arquivo
            self.pastaDeMiniaturas = pastaDeMiniaturas
                ?? arquivo.deletingLastPathComponent()
                    .appendingPathComponent("pecas_salvas_miniaturas", isDirectory: true)
        } else {
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.arquivo = base?.appendingPathComponent("pecas_salvas.json")
            self.pastaDeMiniaturas = pastaDeMiniaturas
                ?? base?.appendingPathComponent("pecas_salvas_miniaturas", isDirectory: true)
        }
    }

    func todas() -> [PecaSalva] {
        carregarSeNecessario()
        // Mais recente primeiro: a peça que você acabou de montar é a que você
        // quer ver.
        return itens.sorted { $0.criadaEm > $1.criadaEm }
    }

    @discardableResult
    func salvar(_ peca: PecaSalva, miniaturaDados: Data? = nil) -> Bool {
        carregarSeNecessario()
        let existente = itens.first(where: { $0.id == peca.id })
        guard existente != nil || itens.count < Self.teto else { return false }

        var salva = peca
        if salva.miniaturaArquivo == nil {
            salva.miniaturaArquivo = existente?.miniaturaArquivo
        }
        if let miniaturaDados,
           let nome = gravarMiniatura(miniaturaDados, id: salva.id) {
            if let anterior = existente?.miniaturaArquivo, anterior != nome {
                apagarMiniatura(anterior)
            }
            salva.miniaturaArquivo = nome
        }
        if let i = itens.firstIndex(where: { $0.id == peca.id }) {
            itens[i] = salva
        } else {
            itens.append(salva)
        }
        gravar()
        return true
    }

    func miniatura(de peca: PecaSalva) -> Data? {
        carregarSeNecessario()
        guard let url = urlDaMiniatura(peca.miniaturaArquivo) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    func apagar(_ id: UUID) {
        carregarSeNecessario()
        if let nome = itens.first(where: { $0.id == id })?.miniaturaArquivo {
            apagarMiniatura(nome)
        }
        itens.removeAll { $0.id == id }
        gravar()
    }

    func apagarTudo() {
        carregarSeNecessario()
        for item in itens {
            if let nome = item.miniaturaArquivo { apagarMiniatura(nome) }
        }
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
        excluirDeBackup(arquivo)
    }

    private func gravarMiniatura(_ dados: Data, id: UUID) -> String? {
        guard !dados.isEmpty, let pastaDeMiniaturas else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: pastaDeMiniaturas, withIntermediateDirectories: true)
            excluirDeBackup(pastaDeMiniaturas)
            let extensao = dados.prefix(4) == Data([0x89, 0x50, 0x4e, 0x47])
                ? "png" : "jpg"
            let nome = "\(id.uuidString.lowercased()).\(extensao)"
            let url = pastaDeMiniaturas.appendingPathComponent(nome)
            try dados.write(to: url, options: .atomic)
            excluirDeBackup(url)
            return nome
        } catch {
            return nil
        }
    }

    private func urlDaMiniatura(_ nome: String?) -> URL? {
        guard let nome, !nome.isEmpty, nome == URL(fileURLWithPath: nome).lastPathComponent,
              ["jpg", "jpeg", "png"].contains(URL(fileURLWithPath: nome)
                    .pathExtension.lowercased()),
              let pastaDeMiniaturas else {
            return nil
        }
        return pastaDeMiniaturas.appendingPathComponent(nome)
    }

    private func apagarMiniatura(_ nome: String) {
        guard let url = urlDaMiniatura(nome) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func excluirDeBackup(_ url: URL) {
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        var mutavel = url
        try? mutavel.setResourceValues(valores)
    }
}
