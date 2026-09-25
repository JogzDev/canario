import Foundation

/// Números observados na data da Leitura. Ausência continua ausente: zero é
/// reservado para um fato que o painel mediu como zero.
struct ResumoDaLeitura: Codable, Equatable, Sendable {
    let pecas: Int?
    let marcas: Int?
    let precoMinimo: Double?
    let precoMediano: Double?
    let precoMaximo: Double?
    let remarcadas: Int?
    let comTamanhoEsgotado: Int?

    init(_ leitura: LeituraEspecifica) {
        pecas = leitura.fatos["total"]?.pecas
        marcas = leitura.fatos["total"]?.marcas
        precoMinimo = leitura.fatos["preco"]?.minimo
        precoMediano = leitura.fatos["preco"]?.mediana
        precoMaximo = leitura.fatos["preco"]?.maximo
        remarcadas = leitura.fatos["remarcadas"]?.pecas
        comTamanhoEsgotado = leitura.fatos["grade"]?.comTamanhoEsgotado
    }
}

/// Compara duas fotografias do painel, sem inferir tendência entre elas.
struct ComparacaoDeLeituras: Equatable, Sendable {
    let antes: ResumoDaLeitura
    let depois: ResumoDaLeitura
    let painelAntes: String?
    let painelDepois: String?
    let entraramNoRecorte: Int
    let sairamDoRecorte: Int

    init(antes: LeituraEspecifica, depois: LeituraEspecifica) {
        self.antes = ResumoDaLeitura(antes)
        self.depois = ResumoDaLeitura(depois)
        painelAntes = antes.painelObservadoEm
        painelDepois = depois.painelObservadoEm
        let idsAntes = Set(antes.pecas.map(\.id))
        let idsDepois = Set(depois.pecas.map(\.id))
        entraramNoRecorte = idsDepois.subtracting(idsAntes).count
        sairamDoRecorte = idsAntes.subtracting(idsDepois).count
    }
}

/// Uma leitura pedida pela pessoa, conservada somente neste aparelho.
struct LeituraGuardada: Codable, Identifiable, Sendable {
    let id: UUID
    let feitaEm: Date
    let pedido: String
    let refinamento: String?
    let descricao: DescricaoDaPeca?
    let precoDaPessoa: Double?
    let leitura: LeituraEspecifica
    let resumo: ResumoDaLeitura

    init(id: UUID = UUID(), feitaEm: Date = Date(), pedido: String,
         refinamento: String? = nil,
         descricao: DescricaoDaPeca?, precoDaPessoa: Double?, leitura: LeituraEspecifica) {
        self.id = id
        self.feitaEm = feitaEm
        self.pedido = pedido
        self.refinamento = refinamento
        self.descricao = descricao
        self.precoDaPessoa = precoDaPessoa
        self.leitura = leitura
        self.resumo = ResumoDaLeitura(leitura)
    }

    private enum CodingKeys: String, CodingKey {
        case id, feitaEm, pedido, refinamento, descricao, precoDaPessoa, leitura, resumo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        feitaEm = try c.decode(Date.self, forKey: .feitaEm)
        pedido = try c.decode(String.self, forKey: .pedido)
        refinamento = try c.decodeIfPresent(String.self, forKey: .refinamento)
        descricao = try c.decodeIfPresent(DescricaoDaPeca.self, forKey: .descricao)
        precoDaPessoa = try c.decodeIfPresent(Double.self, forKey: .precoDaPessoa)
        leitura = try c.decode(LeituraEspecifica.self, forKey: .leitura)
        resumo = try c.decodeIfPresent(ResumoDaLeitura.self, forKey: .resumo)
            ?? ResumoDaLeitura(leitura)
    }

    var nome: String { leitura.nome ?? pedido }
}

/// Histórico local, separado por usuário como o Acervo. Não sincroniza.
actor LeiturasSalvas {
    static let shared = LeiturasSalvas()
    static let teto = 50

    private var itens: [LeituraGuardada] = []
    private var carregado = false
    private var arquivo: URL?
    private let raizGerenciada: URL?
    private var usuarioAtual: UUID?

    init(arquivo: URL? = nil) {
        if let arquivo {
            self.arquivo = arquivo
            self.raizGerenciada = nil
        } else {
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.arquivo = base?.appendingPathComponent("leituras_salvas.json")
            self.raizGerenciada = base
        }
    }

    func usarEspacoDoUsuario(_ usuario: UUID?) {
        guard let raizGerenciada, usuarioAtual != usuario else { return }
        let convidado = raizGerenciada.appendingPathComponent("leituras_salvas.json")
        if let usuario {
            let destino = raizGerenciada.appendingPathComponent(
                "leituras_salvas_\(usuario.uuidString.lowercased()).json")
            if !FileManager.default.fileExists(atPath: destino.path),
               FileManager.default.fileExists(atPath: convidado.path) {
                try? FileManager.default.copyItem(at: convidado, to: destino)
            }
            arquivo = destino
        } else {
            arquivo = convidado
        }
        usuarioAtual = usuario
        itens = []
        carregado = false
        carregarSeNecessario()
    }

    func todas() -> [LeituraGuardada] {
        carregarSeNecessario()
        return itens.sorted { $0.feitaEm > $1.feitaEm }
    }

    func guardar(_ leitura: LeituraGuardada) {
        carregarSeNecessario()
        itens.append(leitura)
        itens.sort { $0.feitaEm > $1.feitaEm }
        if itens.count > Self.teto { itens.removeLast(itens.count - Self.teto) }
        gravar()
        NotificationCenter.default.post(name: .leituraFoiGuardada, object: nil)
    }

    func apagarTudo() {
        carregarSeNecessario()
        itens = []
        gravar()
    }

    private func carregarSeNecessario() {
        guard !carregado else { return }
        carregado = true
        guard let arquivo, let dados = try? Data(contentsOf: arquivo) else { return }
        itens = (try? JSONDecoder().decode([LeituraGuardada].self, from: dados)) ?? []
        itens.sort { $0.feitaEm > $1.feitaEm }
        if itens.count > Self.teto { itens.removeLast(itens.count - Self.teto) }
    }

    private func gravar() {
        guard let arquivo, let dados = try? JSONEncoder().encode(itens) else { return }
        try? dados.write(to: arquivo, options: .atomic)
        var recurso = URLResourceValues()
        recurso.isExcludedFromBackup = true
        var caminho = arquivo
        try? caminho.setResourceValues(recurso)
    }
}

extension Notification.Name {
    static let leituraFoiGuardada = Notification.Name("leituraFoiGuardada")
}
