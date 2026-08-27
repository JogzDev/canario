import Foundation

/// O recorte visível do Closet: rótulos, categorias e o filtro local (A36).
///
/// POR QUE ISTO SAIU DA TELA
/// =========================
///
/// O JP, no teste físico de 25/08: *"Aplicativo ta travando MUITO e muito
/// lento"*. A causa mais cara estava aqui, e ela era invisível porque morava
/// dentro do `body` de `MinhasPecas`:
///
/// ```swift
/// private var rotulos: [String: String] {          // PROPRIEDADE COMPUTADA
///     Dictionary(uniqueKeysWithValues: termos.map { ... })
/// }
/// ```
///
/// `rotulos` percorre a taxonomia inteira — 212 termos — a **cada acesso**. E
/// ele era acessado de dentro do laço que filtra as peças (`peca.nome(comRotulos:
/// rotulos)`), mais três vezes por card da grade. Com 200 peças no armário, uma
/// única avaliação do `body` reconstruía o dicionário ~800 vezes: ~170 mil
/// inserções e outras tantas buscas, **na main thread**, a cada tecla digitada
/// na busca e a cada rolagem que invalidasse a view.
///
/// Não é micro-otimização: é trabalho quadrático dentro do laço de interface.
///
/// O outro motivo de estar aqui é a regra do projeto — *"tela se verifica
/// olhando, lógica se verifica testando"*. Filtro de armário é lógica, estava
/// numa View e por isso nunca foi medido. Agora está no pacote, com teste de
/// comportamento e orçamento de tempo.
struct CatalogoDoArmario: Sendable {
    /// id do termo → rótulo já traduzido para a interface.
    let rotulos: [String: String]
    /// Só os termos de categoria, que dão o título do card.
    let categorias: [String: String]
    /// O mesmo conjunto de chaves de `categorias`, pronto para o card não
    /// repetir a categoria no detalhe.
    let idsDeCategoria: Set<String>
    /// id do termo → dimensão de FILTRO.
    private let dimensaoDeFiltro: [String: String]

    init(termos: [Termo]) {
        var rotulos: [String: String] = [:]
        var categorias: [String: String] = [:]
        var dimensoes: [String: String] = [:]
        rotulos.reserveCapacity(termos.count)
        dimensoes.reserveCapacity(termos.count)
        for termo in termos {
            let rotulo = Traducao.rotuloExibido(termo)
            rotulos[termo.id] = rotulo
            dimensoes[termo.id] = termo.dimensao
            if termo.dimensao == "categoria" { categorias[termo.id] = rotulo }
        }
        self.rotulos = rotulos
        self.categorias = categorias
        self.idsDeCategoria = Set(categorias.keys)
        self.dimensaoDeFiltro = dimensoes
    }

    /// O título do card: a categoria da peça, quando ela tem uma.
    func categoria(de peca: PecaSalva) -> String? {
        peca.termoIds.compactMap { categorias[$0] }.first
    }
}

/// O que a pessoa escolheu na barra de busca e na folha de filtros.
struct FiltroDoArmario: Equatable, Sendable {
    var somenteFavoritas: Bool
    var atributos: Set<String>
    var busca: String

    init(somenteFavoritas: Bool = false,
         atributos: Set<String> = [],
         busca: String = "") {
        self.somenteFavoritas = somenteFavoritas
        self.atributos = atributos
        self.busca = busca
    }

    var ativo: Bool {
        somenteFavoritas || !atributos.isEmpty || !busca.isEmpty
    }

    /// Aplica o recorte. Semântica preservada da A36: **AND entre dimensões,
    /// OR dentro da mesma dimensão** — Green + Stripes exige os dois; Green +
    /// Blue aceita qualquer das duas cores.
    ///
    /// O texto pesquisável de cada peça é montado no máximo uma vez por peça, e
    /// só quando existe consulta: sem busca, o laço nem toca em string.
    func aplicar(a pecas: [PecaSalva],
                 catalogo: CatalogoDoArmario) -> [PecaSalva] {
        let consulta = Traducao.normalizar(busca)

        // Id que não existe na taxonomia é IGNORADO, e não vira uma dimensão
        // própria: era o que a tela fazia (`termos.filter { selecionados… }`),
        // e inverter isso transformaria um filtro obsoleto salvo na sessão num
        // armário vazio sem explicação.
        var porDimensao: [String: Set<String>] = [:]
        for id in atributos {
            guard let dimensao = catalogo.dimensao(deFiltro: id) else { continue }
            porDimensao[dimensao, default: []].insert(id)
        }
        let exigidos = Array(porDimensao.values)

        return pecas.filter { peca in
            if somenteFavoritas && !(peca.favorita ?? false) { return false }
            if !exigidos.isEmpty {
                let idsDaPeca = Set(peca.termoIds)
                for conjunto in exigidos where idsDaPeca.isDisjoint(with: conjunto) {
                    return false
                }
            }
            guard !consulta.isEmpty else { return true }
            return Traducao.normalizar(
                catalogo.textoPesquisavel(de: peca)).contains(consulta)
        }
    }
}

extension CatalogoDoArmario {
    /// `dimensaoDeFiltro` é privada de propósito — quem filtra não precisa do
    /// mapa inteiro, só da dimensão de um id. `nil` quer dizer "esse id não
    /// está na taxonomia carregada".
    func dimensao(deFiltro id: String) -> String? {
        dimensaoDeFiltro[id]
    }

    /// Nome exibido + rótulos dos atributos, que é exatamente o que a barra de
    /// busca do Closet promete encontrar.
    func textoPesquisavel(de peca: PecaSalva) -> String {
        var partes = [peca.nome(comRotulos: rotulos)]
        partes.append(contentsOf: peca.termoIds.compactMap { rotulos[$0] })
        return partes.joined(separator: " ")
    }
}
