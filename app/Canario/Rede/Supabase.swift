import Foundation

/// Resposta auditável da análise visual remota (A15).
///
/// Os nomes livres nunca entram no motor de tendências. Somente ids que já
/// existem na taxonomia podem pré-preencher o formulário, e a escolha humana
/// continua sendo o dado final salvo no Closet.
struct AnaliseVisualRemota: Decodable, Equatable {
    let targetClarity: String
    let garmentStructure: String
    let category: String
    let decisionEvidence: [String]
    let pattern: String
    let fabrics: [String]
    let length: String
    let silhouette: String
    let waist: String
    let aesthetics: [String]
    let colors: [String]
    let additionalVisualAttributes: [String]
    let model: String
    let promptVersion: String

    enum CodingKeys: String, CodingKey {
        case category, pattern, fabrics, length, silhouette, waist, aesthetics, colors, model
        case targetClarity = "target_clarity"
        case garmentStructure = "garment_structure"
        case decisionEvidence = "decision_evidence"
        case additionalVisualAttributes = "additional_visual_attributes"
        case promptVersion = "prompt_version"
    }

    /// Converte a saída fechada em sugestões, sem permitir que `not_visible`
    /// ou texto livre virem ids acidentalmente.
    /// As cores **na ordem que a Luna devolveu**, que é a ordem que importa.
    ///
    /// O prompt dela manda: *"Colors are ordered: the primary color first,
    /// followed by at most two secondary colors… Rank colors by visible
    /// surface area on the target garment only"*, com `maxItems: 3`. Ou seja,
    /// o ranqueamento por área visível já existe no servidor desde a A31 — e
    /// `idsSugeridos` jogava fora, porque `Set` não tem ordem. A tela de
    /// atributos precisa dessa ordem para dizer qual é a cor principal, e
    /// inventá-la a partir da ordem da taxonomia seria numerar por acaso.
    func coresSugeridas(existentes: Set<String>) -> [String] {
        var vistas: Set<String> = []
        return colors.filter { existentes.contains($0) && vistas.insert($0).inserted }
    }

    func idsSugeridos(existentes: Set<String>) -> Set<String> {
        let escalares = [category, pattern, length, silhouette, waist]
            .filter { $0 != "not_visible" }
        return Set(escalares + fabrics + aesthetics + colors)
            .intersection(existentes)
    }

    var alvoAmbiguo: Bool {
        targetClarity == "ambiguous_target" || category == "not_visible"
    }
}

/// Produto que o coletor já conhece. A origem é explícita: estes atributos
/// vieram do título/catalogação da loja, não da câmera nem de uma inferência.
struct ProdutoDoPainel: Decodable, Equatable, Sendable {
    let id: Int
    let title: String?
    let brand: String
    let imageURL: String?
    let price: Double?
    let termIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, brand, price
        case imageURL = "image_url"
        case termIDs = "term_ids"
    }
}

/// Cliente de leitura do Supabase.
///
/// O app **só lê** (§33: servidor calcula, app consulta). A chave é a
/// publishable, que é pública por desenho e vai embutida no binário — a
/// segurança vem inteiramente das políticas RLS, e não do sigilo dela.
///
/// Sem dependência de terceiros: `URLSession` basta, e §26 pede dependências
/// mínimas e justificadas uma a uma.
actor Supabase {
    static let shared = Supabase()

    private let url: URL
    private let chave: String
    private let sessao: URLSession
    private let esperaEntreTentativas: UInt64

    /// Erros que a interface precisa saber diferenciar para ser honesta.
    enum Falha: LocalizedError {
        case semConfiguracao
        case rede(Error)
        case resposta(Int, String)
        case urlInvalida(String, String)

        var errorDescription: String? {
            switch self {
            case .semConfiguracao:
                return frase("Config.xcconfig is missing or incomplete. Copy Config.xcconfig.example.")
            case .rede:
                return frase("The server could not be reached.")
            case .resposta(let codigo, let corpo):
                return Falha.mensagem(codigo: codigo, corpo: corpo)
            case .urlInvalida(let caminho, _):
                return frase("Malformed request for \(caminho).")
            }
        }

        /// Traduz a recusa do servidor para o que a pessoa precisa saber.
        ///
        /// Até 20/08/2026 quem estourava o teto diário de análise visual via
        /// **"The server returned 429."** — um código HTTP na cara de quem só
        /// queria ler uma peça. O corpo da resposta já trazia o motivo exato e
        /// era descartado.
        ///
        /// Sobre "from this network": o teto é contado por **IP**, não por
        /// aparelho nem por conta. Duas pessoas no mesmo Wi-Fi dividem as 12, e
        /// quem troca de Wi-Fi para 4G recebe outras 12. Dizer "seu limite"
        /// seria mentira para os dois casos, e mentira sobre limite é pior que
        /// silêncio: a pessoa se planeja e é bloqueada antes da conta fechar.
        ///
        /// Toda mensagem de recusa termina lembrando que o caminho manual
        /// continua aberto. Nenhuma dessas falhas impede adicionar a peça.
        static func mensagem(codigo: Int, corpo: String) -> String {
            let reset = "It resets at midnight, São Paulo time."
            let manual = "You can still add the item and choose its attributes yourself."
            switch Falha.codigoDoCorpo(corpo) {
            case "daily_origin_limit":
                return frase("This network reached today's limit of 12 visual analyses. \(reset) \(manual)")
            case "daily_project_limit":
                return frase("DataDrobe reached its overall daily limit for visual analysis. \(reset) \(manual)")
            case "rate_limited":
                return frase("The visual analysis was refused for exceeding a daily limit. \(reset) \(manual)")
            case "rate_limit_unavailable":
                return frase("The usage check is unavailable, so nothing was sent for analysis. Try again in a few minutes. \(manual)")
            case "analysis_not_configured":
                return frase("Cloud visual analysis is off in this build. \(manual)")
            case "invalid_image":
                return frase("I could not read this image. Try another photo or file.")
            case "invalid_target_hint":
                return frase("The target hint is too long. Keep it under 160 characters.")
            case "analysis_contract_failed":
                return frase("The analysis came back in a shape I do not accept, so I discarded it rather than guess. \(manual)")
            case "BOOT_ERROR":
                return frase("The visual analysis service is not responding. \(manual)")
            default:
                // Codigo desconhecido continua aparecendo -- some-lo esconderia
                // um caso novo de quem pode consertar.
                return frase("The analysis could not be completed (HTTP \(String(codigo))). \(manual)")
            }
        }

        /// O `error` ou `code` que a Edge Function devolve no corpo JSON.
        static func codigoDoCorpo(_ corpo: String) -> String? {
            guard let dados = corpo.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: dados)
                    as? [String: Any] else { return nil }
            return (json["error"] as? String) ?? (json["code"] as? String)
        }
    }

    init() {
        let info = Bundle.main.infoDictionary
        let bruto = (info?["SUPABASE_URL"] as? String) ?? ""
        // O xcconfig engole `//`, então a URL pode chegar sem o esquema.
        let normalizado = bruto.hasPrefix("http") ? bruto : "https://\(bruto)"
        self.url = URL(string: normalizado) ?? URL(string: "https://invalido.invalido")!
        self.chave = (info?["SUPABASE_PUBLISHABLE_KEY"] as? String) ?? ""

        let cfg = URLSessionConfiguration.default
        // §27 exige modo offline servindo o cache da última sincronização com
        // carimbo visível. O cache do protocolo é a base disso.
        cfg.requestCachePolicy = .useProtocolCachePolicy
        cfg.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        // 20s era tempo demais para falhar. Com a segunda tentativa em cima,
        // uma requisição travada segurava a tela por 40s -- e o JP viu isso
        // como "tela preta por alguns segundos" com `Hang detected: 5.25s` no
        // Xcode. Dez segundos ainda é folgado para uma consulta que roda em
        // milissegundos no banco, e falha rápido quando a rede não colabora.
        cfg.timeoutIntervalForRequest = 10
        // Sem isto o iOS enfileira a requisição esperando rede aparecer, em
        // vez de devolver erro e deixar a tela dizer que está offline (§27).
        cfg.waitsForConnectivity = false
        self.sessao = URLSession(configuration: cfg)
        self.esperaEntreTentativas = 400_000_000
    }

    /// Inicializador injetável para verificar o contrato HTTP sem tocar na
    /// rede real. Ele também torna explícitas as três dependências do cliente:
    /// endpoint, chave publicável e sessão. A espera configurável mantém o
    /// teste da segunda tentativa instantâneo.
    init(url: URL, chave: String, sessao: URLSession,
         esperaEntreTentativas: UInt64 = 400_000_000) {
        self.url = url
        self.chave = chave
        self.sessao = sessao
        self.esperaEntreTentativas = esperaEntreTentativas
    }

    var configurado: Bool {
        !chave.isEmpty && url.host != "invalido.invalido"
    }

    /// O interruptor só fica verde depois que a migração, a Edge Function e os
    /// secrets foram implantados. Uma substituição ausente chega literalmente
    /// como `$(REMOTE_ANALYSIS_ENABLED)` e, portanto, permanece desligada.
    static var analiseRemotaHabilitada: Bool {
        let valor = (Bundle.main.infoDictionary?["REMOTE_ANALYSIS_ENABLED"] as? String) ?? ""
        return ["YES", "TRUE", "1"].contains(valor.uppercased())
    }

    /// Caracteres que o PostgREST usa como sintaxe e que NÃO podem ser
    /// escapados: `=` separa chave e valor, `.` separa operador (`eq.`, `in.`),
    /// `,` separa itens de lista, `()` delimita `in.(...)`, `*` é o select
    /// completo, `&` separa parâmetros. Tudo o mais — inclusive espaço e aspas —
    /// precisa ser codificado.
    private static let sintaxePostgREST = CharacterSet(
        charactersIn: "=&.,()*:-_~/").union(.alphanumerics)

    /// Codifica a query preservando a sintaxe do PostgREST.
    ///
    /// Existe por um crash real: a consulta de Explorar tinha
    /// `estado=in.("em alta","em queda",pico)` com espaços literais, a URL
    /// ficava inválida e o app morria com SIGTRAP no force-unwrap abaixo.
    static func codificar(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: sintaxePostgREST) ?? query
    }

    /// GET em uma tabela/view exposta, com query PostgREST.
    /// Ex.: `buscar("indices_semanais", "select=*&limit=10")`
    func buscar<T: Decodable>(_ caminho: String, _ query: String) async throws -> [T] {
        guard configurado else { throw Falha.semConfiguracao }

        guard var componentes = URLComponents(
            url: url.appendingPathComponent("rest/v1/\(caminho)"),
            resolvingAgainstBaseURL: false) else {
            throw Falha.urlInvalida(caminho, query)
        }
        componentes.percentEncodedQuery = Supabase.codificar(query)

        // SEM force-unwrap. Uma consulta malformada é bug de programação, mas
        // derrubar o app na cara do usuário é a pior forma possível de reportar
        // isso — vira erro tratado, e a tela mostra falha de consulta.
        guard let enderecoFinal = componentes.url else {
            throw Falha.urlInvalida(caminho, query)
        }
        var req = URLRequest(url: enderecoFinal)
        req.setValue(chave, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let dados = try await comUmaSegundaChance(req)
        return try JSONDecoder().decode([T].self, from: dados)
    }

    /// Faz o pedido e, em falha **transitória**, tenta mais uma vez.
    ///
    /// **Por que existe.** Na revisão de 03/08 o companheiro de time do JP
    /// registrou, na aba Explorar: *"Primeiro recebi 'Não consegui consultar.
    /// O servidor respondeu 500'. Depois que cliquei em tentar novamente foi."*
    /// O erro é real e é passageiro — a tela abre quatro pedidos ao mesmo tempo
    /// e a rotina noturna segura conexões por mais de uma hora com a chave de
    /// serviço, então o pool nega um deles de vez em quando.
    ///
    /// Fazer o usuário ser o laço de repetição é o pior desenho possível: ele
    /// não sabe que "tentar de novo" resolve, e uma tela de erro que some no
    /// segundo toque ensina que o app é instável.
    ///
    /// **Uma só tentativa, e só no que é transitório.** 5xx e queda de rede
    /// repetem; 4xx não — consulta malformada ou permissão negada repetida dá o
    /// mesmo resultado e só atrasa o erro honesto na tela. O intervalo curto é
    /// para o pool respirar, não para insistir.
    private func comUmaSegundaChance(_ req: URLRequest) async throws -> Data {
        for tentativa in 0...1 {
            do {
                let (dados, resposta) = try await sessao.data(for: req)
                let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(codigo) { return dados }
                guard codigo >= 500, tentativa == 0 else {
                    throw Falha.resposta(codigo, String(data: dados, encoding: .utf8) ?? "")
                }
            } catch let falha as Falha {
                throw falha
            } catch let erro as URLError where erro.code == .timedOut {
                // Tempo esgotado NÃO repete. Repetir custa outros 10s e o
                // motivo mais provável de estourar é congestionamento -- que
                // uma segunda chamada só piora. 5xx repete porque ali o
                // servidor respondeu, e rápido.
                throw Falha.rede(erro)
            } catch {
                guard tentativa == 0 else { throw Falha.rede(error) }
            }
            try? await Task.sleep(nanoseconds: esperaEntreTentativas)
        }
        throw Falha.rede(URLError(.cannotLoadFromNetwork))
    }

    /// Chama uma função do banco (`rpc/`) e decodifica a resposta.
    ///
    /// Existe para o bloco de similares (§29). Poderia ter sido feito com
    /// várias consultas `GET` e a agregação no dispositivo, e seria errado: a
    /// §33 diz **servidor calcula, app consulta**, e trazer 18 mil peças pela
    /// rede para contar quantas estão remarcadas é exatamente o oposto.
    ///
    /// A função roda com o papel `anon`, cujo `statement_timeout` é de 3
    /// segundos — o que restringiu o desenho dela do lado do banco.
    func chamar<T: Decodable>(_ funcao: String, _ argumentos: [String: Any]) async throws -> T {
        guard configurado else { throw Falha.semConfiguracao }
        let endereco = url.appendingPathComponent("rest/v1/rpc/\(funcao)")

        var req = URLRequest(url: endereco)
        req.httpMethod = "POST"
        req.setValue(chave, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: argumentos)

        do {
            // RPC também recebe a segunda chance reservada a 5xx/quebra de
            // rede. Antes, consultas GET repetiam e as funções que alimentam
            // similares e gráficos não, embora falhassem pelo mesmo pool.
            let dados = try await comUmaSegundaChance(req)
            return try JSONDecoder().decode(T.self, from: dados)
        } catch let falha as Falha {
            throw falha
        } catch {
            throw Falha.rede(error)
        }
    }

    /// Atalho sem custo de visão: só resolve uma URL exata que já existe no
    /// painel. URLs externas voltam `nil` e permanecem no fluxo normal da foto.
    func produtoDoPainel(url: String) async throws -> ProdutoDoPainel? {
        try await chamar("produto_do_painel_por_url", ["p_url": url])
    }

    /// Envia apenas a miniatura já reamostrada e sem metadados para a função
    /// segura do projeto. A chave da OpenAI nunca atravessa esta fronteira.
    func analisarPeca(_ dados: Data, alvo: String? = nil) async throws
        -> AnaliseVisualRemota {
        guard configurado, Self.analiseRemotaHabilitada else {
            throw Falha.semConfiguracao
        }
        guard !dados.isEmpty, dados.count <= 3_000_000 else {
            throw Falha.resposta(413, "image_size_not_allowed")
        }

        let tipo: String
        if dados.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            tipo = "image/png"
        } else if dados.starts(with: [0xFF, 0xD8, 0xFF]) {
            tipo = "image/jpeg"
        } else {
            throw Falha.resposta(415, "unsupported_image_type")
        }

        let endereco = url.appendingPathComponent("functions/v1/analisar-peca")
        var req = URLRequest(url: endereco,
                             cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 30)
        req.httpMethod = "POST"
        // Publishable keys are API keys, not JWTs. The Edge Function validates
        // this header with Supabase's `publishable` auth mode.
        req.setValue(chave, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var corpo: [String: Any] = [
            "image_base64": dados.base64EncodedString(),
            "media_type": tipo,
        ]
        if let alvo {
            let limpo = alvo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !limpo.isEmpty { corpo["target_hint"] = String(limpo.prefix(160)) }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let resposta = try await comUmaSegundaChance(req)
        do {
            return try JSONDecoder().decode(AnaliseVisualRemota.self, from: resposta)
        } catch {
            throw Falha.resposta(502, "analysis_contract_failed")
        }
    }
}

/// Taxonomia com cache local stale-while-revalidate.
///
/// Ela muda raramente, era buscada novamente por Home, Closet, Search e
/// Compare e fazia cada troca de tela pagar outra abertura TLS. A primeira
/// leitura vem da rede; as seguintes devolvem o arquivo local imediatamente e
/// renovam silenciosamente para a próxima abertura.
actor CatalogoDeTermos {
    static let shared = CatalogoDeTermos()
    private var memoria: [Termo]?
    private var buscaEmCurso: Task<[Termo], Error>?

    private var arquivo: URL {
        let raiz = FileManager.default.urls(for: .cachesDirectory,
                                             in: .userDomainMask)[0]
        return raiz.appendingPathComponent("canario-taxonomia-v1.json")
    }

    func carregar() async throws -> [Termo] {
        if let memoria { return memoria }
        if let dados = try? Data(contentsOf: arquivo),
           let locais = try? JSONDecoder().decode([Termo].self, from: dados),
           !locais.isEmpty {
            memoria = locais
            Task { await renovar() }
            return locais
        }
        return try await buscarESalvar()
    }

    func renovar() async {
        _ = try? await buscarESalvar()
    }

    private func buscarESalvar() async throws -> [Termo] {
        if let buscaEmCurso { return try await buscaEmCurso.value }
        let tarefa = Task<[Termo], Error> {
            try await Supabase.shared.buscar(
                "termos",
                // `order=dimensao,id` ordenava os chips pelo IDENTIFICADOR
                // INTERNO, em português, numa tela que mostra o rótulo
                // traduzido: `Dress` é a segunda categoria mais comum do
                // mercado e caía em último, porque "vestido" é o último
                // alfabeticamente. Agora a ordem vem calculada do servidor
                // (§33), por frequência real no painel.
                "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca,"
                + "palavras_pt,palavras_en"
                + "&order=dimensao,ordem_de_exibicao.nullsfirst,id")
        }
        buscaEmCurso = tarefa
        let recebidos: [Termo]
        do {
            recebidos = try await tarefa.value
        } catch {
            buscaEmCurso = nil
            throw error
        }
        buscaEmCurso = nil
        memoria = recebidos
        if let dados = try? JSONEncoder().encode(recebidos) {
            try? dados.write(to: arquivo, options: .atomic)
        }
        return recebidos
    }
}

/// Últimas 14 semanas de índices, compartilhadas por busca, relatórios,
/// comparação e radar. Antes cada aba baixava as mesmas ~500 linhas; como o
/// custo dominante é abrir TLS, trocar de aba parecia reiniciar o aplicativo.
/// A data continua em cada `IndiceSemanal`, então servir o snapshot local não
/// esconde sua idade enquanto a renovação silenciosa prepara o próximo toque.
actor CatalogoDeIndices {
    static let shared = CatalogoDeIndices()
    private var memoria: [IndiceSemanal]?
    private var buscaEmCurso: Task<[IndiceSemanal], Error>?

    private var arquivo: URL {
        FileManager.default.urls(for: .cachesDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("canario-indices-v1.json")
    }

    func carregar() async throws -> [IndiceSemanal] {
        // A Home já aquece a sessão. Renovar aqui transformava cada navegação
        // posterior em uma nova abertura TLS para o mesmo snapshot semanal.
        if let memoria { return memoria }
        if let dados = try? Data(contentsOf: arquivo),
           let locais = try? JSONDecoder().decode([IndiceSemanal].self, from: dados),
           !locais.isEmpty {
            memoria = locais
            Task { await renovar() }
            return locais
        }
        return try await buscarESalvar()
    }

    func renovar() async {
        _ = try? await buscarESalvar()
    }

    private func buscarESalvar() async throws -> [IndiceSemanal] {
        if let buscaEmCurso { return try await buscaEmCurso.value }
        let calendario = Calendar(identifier: .iso8601)
        let corte = calendario.date(byAdding: .day, value: -98, to: Date()) ?? Date()
        let f = DateFormatter()
        f.calendar = calendario
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let consulta = "select=*&segmento=eq.\(Recorte.segmento)"
            + "&semana=gte.\(f.string(from: corte))&order=semana.desc&limit=1000"
        let tarefa = Task<[IndiceSemanal], Error> {
            try await Supabase.shared.buscar("indices_do_app", consulta)
        }
        buscaEmCurso = tarefa
        let recebidos: [IndiceSemanal]
        do {
            recebidos = try await tarefa.value
        } catch {
            buscaEmCurso = nil
            throw error
        }
        buscaEmCurso = nil
        memoria = recebidos
        if let dados = try? JSONEncoder().encode(recebidos) {
            try? dados.write(to: arquivo, options: .atomic)
        }
        return recebidos
    }
}
