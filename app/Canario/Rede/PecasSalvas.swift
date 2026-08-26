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
/// ## Foto original nunca sai do aparelho
///
/// A §34 não tem sincronização na v1. Grava em Application Support, excluído
/// de backup. Desde A18, uma peça pode apontar para uma **miniatura local**:
/// PNG transparente quando o recorte local é confiável, ou JPEG reamostrado
/// quando não é; ambos sem metadados e apagados junto com a peça. Para uma
/// conta conectada, só essa miniatura reduzida pode ser sincronizada no bucket
/// privado do usuário. A foto original continua não sendo copiada para o app.
struct PecaSalva: Codable, Equatable, Identifiable, Sendable {

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
    /// Relógio de conflito da A26. Não é leitura de mercado: marca somente a
    /// última edição feita pelo usuário, inclusive quando estava offline.
    var atualizadaEm: Date?
    /// Nome opaco da miniatura local. Nunca contém caminho, URL de origem ou imagem
    /// em base64; `PecasSalvas` valida o nome antes de abrir.
    var miniaturaArquivo: String?
    /// Impressão e formato da cópia privada já aceita pelo servidor. Ausentes
    /// significam que uma miniatura local ainda precisa ser enviada.
    var miniaturaHashRemoto: String?
    var miniaturaExtensaoRemota: String?
    /// Escolha explícita do usuário. `nil` mantém compatibilidade com peças
    /// criadas antes de Favorites existir e não ocupa o JSON até ser usada.
    var favorita: Bool?
    /// Rejeição explícita da vitrine atual de similares. É escolha do usuário,
    /// não leitura calculada do motor, e pode ser persistida localmente.
    var similaresRejeitados: Bool?

    init(id: UUID = UUID(), apelido: String = "", termoIds: [String],
         precoAlvo: Double? = nil, canal: String? = nil,
         criadaEm: Date = Date(), miniaturaArquivo: String? = nil,
         miniaturaHashRemoto: String? = nil,
         miniaturaExtensaoRemota: String? = nil,
         favorita: Bool? = nil, similaresRejeitados: Bool? = nil,
         atualizadaEm: Date? = nil) {
        self.id = id
        self.apelido = apelido
        self.termoIds = Traducao.idsCanonicos(termoIds)
        self.precoAlvo = precoAlvo
        self.canal = canal
        self.criadaEm = criadaEm
        self.atualizadaEm = atualizadaEm
        self.miniaturaArquivo = miniaturaArquivo
        self.miniaturaHashRemoto = miniaturaHashRemoto
        self.miniaturaExtensaoRemota = miniaturaExtensaoRemota
        self.favorita = favorita
        self.similaresRejeitados = similaresRejeitados
    }

    /// Nome para a lista quando o usuário não deu um. Usa os rótulos vindos do
    /// servidor, e cai nos ids só se a taxonomia não estiver carregada.
    func nome(comRotulos rotulos: [String: String]) -> String {
        if let apelido = NomeCompartilhavel.apelidoValido(apelido) { return apelido }
        let partes = termoIds.compactMap { rotulos[$0] ?? $0 }
        return partes.isEmpty ? "Item without attributes" : partes.joined(separator: " · ")
    }

    /// Os atributos que sobram depois de tirar os que o título já mostra.
    ///
    /// O card do armário mostrava a lista INTEIRA truncada em duas linhas e,
    /// logo abaixo, a categoria de novo -- que já era a primeira coisa da
    /// lista. Visto em aparelho em 19/08/2026: "Coats & jackets · Gray ·
    /// Purple & li…" com "Coats & jackets" repetido embaixo. Duas linhas para
    /// dizer o mesmo, e a que truncava era a única que trazia algo novo.
    ///
    /// Devolve `nil` quando não sobra nada, para o card não desenhar uma linha
    /// vazia.
    func detalhe(comRotulos rotulos: [String: String],
                 semOsTermos excluidos: Set<String>) -> String? {
        let partes = termoIds
            .filter { !excluidos.contains($0) }
            .compactMap { rotulos[$0] ?? $0 }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    /// Se a pessoa deu um nome à peça, ele manda no card.
    var temApelido: Bool {
        NomeCompartilhavel.apelidoValido(apelido) != nil
    }
}

/// Contrato público e autocontido de uma peça compartilhada.
///
/// Não leva foto, leitura de mercado, identificador de usuário nem id interno
/// do Closet. Quem recebe ganha uma nova peça local com os atributos que a
/// outra pessoa decidiu compartilhar.
struct PecaCompartilhada: Identifiable, Equatable, Sendable {
    let id = UUID()
    let nome: String
    let termoIds: [String]

    var url: URL? {
        var componentes = URLComponents(string: "https://jogzdev.github.io/item/")
        componentes?.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "name", value: nome),
            URLQueryItem(name: "terms", value: termoIds.joined(separator: ",")),
        ]
        return componentes?.url
    }

    init(nome: String, termoIds: [String]) {
        self.nome = String(nome.prefix(120))
        self.termoIds = Array(Set(termoIds.filter(Self.idValido))).sorted()
    }

    init?(url: URL) {
        guard url.scheme == "https", url.host == "jogzdev.github.io",
              url.path == "/item" || url.path.hasPrefix("/item/") else { return nil }
        let itens = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let valores = Dictionary(uniqueKeysWithValues: itens.map { ($0.name, $0.value ?? "") })
        guard valores["v"] == "1",
              let ids = valores["terms"]?.split(separator: ",").map(String.init),
              !ids.isEmpty else { return nil }
        self.init(nome: valores["name"] ?? "", termoIds: ids)
        guard !termoIds.isEmpty else { return nil }
    }

    private static func idValido(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).contains($0)
        }
    }
}

/// Única fonte de verdade para o título que sai do Closet. Link, cartão e CSV
/// não podem divergir nem promover todos os atributos a um nome gigantesco.
enum NomeCompartilhavel {
    /// Valores que já apareceram como instrução provisória de interface em
    /// builds de desenvolvimento não podem virar o nome público da peça. O
    /// dado local é preservado para que a pessoa ainda possa corrigi-lo em
    /// Rename; somente Closet, link, cartão e CSV deixam de promovê-lo.
    private static let placeholdersLegados: Set<String> = [
        "replacing", "clothing name", "project name",
    ]

    static func apelidoValido(_ valor: String) -> String? {
        let escrito = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !escrito.isEmpty,
              !placeholdersLegados.contains(escrito.lowercased()) else { return nil }
        return escrito
    }

    /// A forma barata: o catálogo já está montado e a resolução é uma busca.
    static func resolver(_ peca: PecaSalva, catalogo: CatalogoDoArmario) -> String {
        if let escrito = apelidoValido(peca.apelido) { return escrito }
        if let categoria = catalogo.categoria(de: peca) { return categoria }
        return "Clothing item"
    }

    /// Conveniência para quem tem só a lista de termos em mãos. **Monta o
    /// catálogo inteiro a cada chamada** — nunca use dentro de um laço de
    /// interface: em 25/08 esta sobrecarga era chamada uma vez por linha da
    /// lista de compartilhamento, refazendo um dicionário de 212 termos por
    /// peça a cada passagem do `body`.
    static func resolver(_ peca: PecaSalva, termos: [Termo]) -> String {
        resolver(peca, catalogo: CatalogoDoArmario(termos: termos))
    }
}

/// Guarda e devolve as peças. Ator porque a tela toca nela de várias tarefas.
actor PecasSalvas {
    static let shared = PecasSalvas()

    struct EstadoParaSincronizar: Sendable {
        let itens: [PecaSalva]
        let exclusoes: [UUID: Date]
    }

    struct MiniaturaParaSincronizar: Sendable {
        let dados: Data
        let extensao: String
    }

    /// Teto deliberado. O relatório da revisão imaginou 5000 peças; 5000 peças
    /// numa lista sem hierarquia é o mesmo problema de tela cheia, em outro
    /// lugar. Enquanto não houver pasta ou busca dentro da lista, o teto evita
    /// prometer uma organização que não existe.
    static let teto = 200

    private var itens: [PecaSalva] = []
    private var exclusoes: [UUID: Date] = [:]
    private var carregado = false
    private var arquivo: URL?
    private var arquivoDeExclusoes: URL?
    private var pastaDeMiniaturas: URL?
    private let raizGerenciada: URL?
    private var usuarioAtual: UUID?

    init(arquivo: URL? = nil, pastaDeMiniaturas: URL? = nil) {
        if let arquivo {
            self.arquivo = arquivo
            self.arquivoDeExclusoes = arquivo.deletingPathExtension()
                .appendingPathExtension("exclusoes.json")
            self.pastaDeMiniaturas = pastaDeMiniaturas
                ?? arquivo.deletingLastPathComponent()
                    .appendingPathComponent("pecas_salvas_miniaturas", isDirectory: true)
            self.raizGerenciada = nil
        } else {
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.arquivo = base?.appendingPathComponent("pecas_salvas.json")
            self.arquivoDeExclusoes = base?.appendingPathComponent("pecas_salvas_exclusoes.json")
            self.pastaDeMiniaturas = pastaDeMiniaturas
                ?? base?.appendingPathComponent("pecas_salvas_miniaturas", isDirectory: true)
            self.raizGerenciada = base
        }
    }

    /// Troca o namespace local depois de autenticar. A cópia convidada da 1.1
    /// é importada somente na primeira abertura daquela identidade e nunca é
    /// removida durante o merge, permitindo voltar ao modo local sem perda.
    func usarEspacoDoUsuario(_ usuario: UUID?) {
        guard let raizGerenciada, usuarioAtual != usuario else { return }
        let fm = FileManager.default
        let arquivoConvidado = raizGerenciada.appendingPathComponent("pecas_salvas.json")
        let pastaConvidada = raizGerenciada.appendingPathComponent(
            "pecas_salvas_miniaturas", isDirectory: true)

        if let usuario {
            let sufixo = usuario.uuidString.lowercased()
            let novoArquivo = raizGerenciada.appendingPathComponent("pecas_salvas_\(sufixo).json")
            let novaPasta = raizGerenciada.appendingPathComponent(
                "pecas_salvas_miniaturas_\(sufixo)", isDirectory: true)
            if !fm.fileExists(atPath: novoArquivo.path),
               fm.fileExists(atPath: arquivoConvidado.path) {
                try? fm.copyItem(at: arquivoConvidado, to: novoArquivo)
                if fm.fileExists(atPath: pastaConvidada.path) {
                    try? fm.copyItem(at: pastaConvidada, to: novaPasta)
                }
            }
            arquivo = novoArquivo
            arquivoDeExclusoes = raizGerenciada.appendingPathComponent(
                "pecas_salvas_exclusoes_\(sufixo).json")
            pastaDeMiniaturas = novaPasta
        } else {
            arquivo = arquivoConvidado
            arquivoDeExclusoes = raizGerenciada.appendingPathComponent(
                "pecas_salvas_exclusoes.json")
            pastaDeMiniaturas = pastaConvidada
        }
        usuarioAtual = usuario
        itens = []
        exclusoes = [:]
        carregado = false
        carregarSeNecessario()
        NotificationCenter.default.post(name: .closetMudouDeUsuario, object: nil)
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
        salva.termoIds = Traducao.idsCanonicos(salva.termoIds)
        salva.atualizadaEm = Date()
        if salva.miniaturaArquivo == nil {
            salva.miniaturaArquivo = existente?.miniaturaArquivo
        }
        if let miniaturaDados,
           let nome = gravarMiniatura(miniaturaDados, id: salva.id) {
            if let anterior = existente?.miniaturaArquivo, anterior != nome {
                apagarMiniatura(anterior)
            }
            salva.miniaturaArquivo = nome
            // A imagem mudou. O hash anterior não pode declarar que a nova já
            // chegou ao bucket; a extensão antiga fica para limpeza posterior.
            salva.miniaturaHashRemoto = nil
            if salva.miniaturaExtensaoRemota == nil {
                salva.miniaturaExtensaoRemota = existente?.miniaturaExtensaoRemota
            }
        }
        if let i = itens.firstIndex(where: { $0.id == peca.id }) {
            itens[i] = salva
        } else {
            itens.append(salva)
        }
        exclusoes.removeValue(forKey: salva.id)
        gravar()
        agendarSincronizacaoSeNecessario()
        return true
    }

    func miniatura(de peca: PecaSalva) -> Data? {
        carregarSeNecessario()
        guard let url = urlDaMiniatura(peca.miniaturaArquivo) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    func miniaturaParaSincronizar(de peca: PecaSalva) -> MiniaturaParaSincronizar? {
        carregarSeNecessario()
        guard let url = urlDaMiniatura(peca.miniaturaArquivo),
              let dados = try? Data(contentsOf: url, options: .mappedIfSafe),
              !dados.isEmpty else { return nil }
        let extensao = url.pathExtension.lowercased() == "png" ? "png" : "jpg"
        return MiniaturaParaSincronizar(dados: dados, extensao: extensao)
    }

    /// Registra transporte concluído sem fabricar uma edição do usuário nem
    /// disparar uma nova sincronização recursiva.
    func registrarMiniaturaSincronizada(id: UUID, hash: String, extensao: String) {
        carregarSeNecessario()
        guard let indice = itens.firstIndex(where: { $0.id == id }) else { return }
        itens[indice].miniaturaHashRemoto = hash
        itens[indice].miniaturaExtensaoRemota = extensao
        gravar()
    }

    /// Restaura a miniatura reduzida de uma conta sem alterar o relógio de
    /// conflito dos atributos da peça.
    func restaurarMiniaturaSincronizada(id: UUID, dados: Data,
                                        hash: String, extensao: String) -> Bool {
        carregarSeNecessario()
        guard let indice = itens.firstIndex(where: { $0.id == id }),
              let nome = gravarMiniatura(dados, id: id) else { return false }
        if let anterior = itens[indice].miniaturaArquivo, anterior != nome {
            apagarMiniatura(anterior)
        }
        itens[indice].miniaturaArquivo = nome
        itens[indice].miniaturaHashRemoto = hash
        itens[indice].miniaturaExtensaoRemota = extensao
        gravar()
        return true
    }

    func apagar(_ id: UUID) {
        carregarSeNecessario()
        if let nome = itens.first(where: { $0.id == id })?.miniaturaArquivo {
            apagarMiniatura(nome)
        }
        if itens.contains(where: { $0.id == id }) { exclusoes[id] = Date() }
        itens.removeAll { $0.id == id }
        gravar()
        agendarSincronizacaoSeNecessario()
    }

    func apagarTudo() {
        carregarSeNecessario()
        for item in itens {
            if let nome = item.miniaturaArquivo { apagarMiniatura(nome) }
        }
        let agora = Date()
        for item in itens { exclusoes[item.id] = agora }
        itens.removeAll()
        gravar()
        agendarSincronizacaoSeNecessario()
    }

    func estadoParaSincronizar() -> EstadoParaSincronizar {
        carregarSeNecessario()
        return EstadoParaSincronizar(itens: itens, exclusoes: exclusoes)
    }

    /// Aplica a visão remota sem fabricar novas edições locais. O mais recente
    /// ganha por peça; exclusão é uma versão, não ausência de linha.
    func aplicarRemotos(_ remotos: [PecaSalva], removidos: [UUID: Date]) {
        carregarSeNecessario()
        var porId = Dictionary(uniqueKeysWithValues: itens.map { ($0.id, $0) })
        for remoto in remotos {
            let dataRemota = remoto.atualizadaEm ?? remoto.criadaEm
            let local = porId[remoto.id]
            let dataLocal = local.map { $0.atualizadaEm ?? $0.criadaEm }
            let exclusaoLocal = exclusoes[remoto.id]
            if let exclusaoLocal, exclusaoLocal >= dataRemota { continue }
            if dataLocal == nil || dataRemota > dataLocal! {
                var mesclado = remoto
                // A miniatura chega por uma rota privada separada. Uma edição
                // estrutural não apaga o arquivo que este aparelho já tem.
                mesclado.miniaturaArquivo = local?.miniaturaArquivo
                porId[remoto.id] = mesclado
                if exclusaoLocal != nil { exclusoes.removeValue(forKey: remoto.id) }
            }
        }
        for (id, dataRemota) in removidos {
            let dataLocal = porId[id].map { $0.atualizadaEm ?? $0.criadaEm }
            if dataLocal == nil || dataRemota >= dataLocal! {
                if let nome = porId[id]?.miniaturaArquivo { apagarMiniatura(nome) }
                porId.removeValue(forKey: id)
            }
            if let exclusaoLocal = exclusoes[id], dataRemota >= exclusaoLocal {
                exclusoes.removeValue(forKey: id)
            }
        }
        itens = Array(porId.values)
        gravar()
        NotificationCenter.default.post(name: .closetFoiSincronizado, object: nil)
    }

    private func carregarSeNecessario() {
        guard !carregado else { return }
        carregado = true
        if let arquivo, let dados = try? Data(contentsOf: arquivo) {
            // Arquivo corrompido não derruba o app nem apaga o que sobrou:
            // começa vazio e a próxima gravação reescreve.
            itens = ((try? JSONDecoder().decode([PecaSalva].self, from: dados)) ?? [])
                .map { peca in
                    var normalizada = peca
                    normalizada.termoIds = Traducao.idsCanonicos(peca.termoIds)
                    return normalizada
                }
        }
        if let arquivoDeExclusoes,
           let dados = try? Data(contentsOf: arquivoDeExclusoes),
           let registros = try? JSONDecoder().decode([String: Date].self, from: dados) {
            exclusoes = Dictionary(uniqueKeysWithValues: registros.compactMap { chave, data in
                UUID(uuidString: chave).map { ($0, data) }
            })
        }
    }

    private func gravar() {
        guard let arquivo else { return }
        let cod = JSONEncoder()
        cod.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let dados = try? cod.encode(itens) else { return }
        try? dados.write(to: arquivo, options: .atomic)
        excluirDeBackup(arquivo)
        if let arquivoDeExclusoes,
           let dadosExclusoes = try? JSONEncoder().encode(Dictionary(
            uniqueKeysWithValues: exclusoes.map { ($0.key.uuidString.lowercased(), $0.value) })) {
            try? dadosExclusoes.write(to: arquivoDeExclusoes, options: .atomic)
            excluirDeBackup(arquivoDeExclusoes)
        }
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

    private func agendarSincronizacaoSeNecessario() {
        guard usuarioAtual != nil else { return }
        Task { try? await SincronizacaoDoCloset.shared.sincronizar() }
    }
}

extension Notification.Name {
    static let closetMudouDeUsuario = Notification.Name("DataDrobe.closetMudouDeUsuario")
    static let closetFoiSincronizado = Notification.Name("DataDrobe.closetFoiSincronizado")
}
