import XCTest
@testable import CanarioLogica

/// O filtro do Closet (A36) — comportamento e **custo**.
///
/// Este arquivo existe por causa de uma frase do JP no teste físico de 25/08:
/// *"Aplicativo ta travando MUITO e muito lento"*. A causa estava numa
/// propriedade computada dentro do `body` de `MinhasPecas`, e não podia ser
/// pega por nenhum teste porque morava numa View — a única parte do projeto
/// que a regra "lógica se verifica testando" deixa de fora.
///
/// Tirar o filtro da View resolveu as duas coisas: o custo e a ausência de
/// prova. O teste de orçamento no fim é o que impede a forma quadrática de
/// voltar sem ninguém ver.
final class ArmarioVisivelTests: XCTestCase {

    private func termo(_ id: String, _ rotulo: String, _ dimensao: String) -> Termo {
        Termo(id: id, rotulo: rotulo, dimensao: dimensao, exclusiva: false,
              sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    private var taxonomia: [Termo] {
        [termo("camisa", "Camisa", "categoria"),
         termo("vestido", "Vestido", "categoria"),
         termo("verde", "Verde", "cor"),
         termo("preto", "Preto", "cor"),
         termo("listra", "Listrado", "estampa"),
         termo("tomate_print", "Tomate", "motivo_estampa"),
         termo("malha", "Malha", "tecido")]
    }

    // MARK: Comportamento

    func testCatalogoTraduzRotuloEIsolaCategoria() {
        let catalogo = CatalogoDoArmario(termos: taxonomia)
        XCTAssertEqual(catalogo.rotulos["camisa"], "Shirt")
        XCTAssertEqual(catalogo.rotulos["malha"], "Knit & crochet")
        XCTAssertEqual(catalogo.categorias.keys.sorted(), ["camisa", "vestido"])
        XCTAssertEqual(catalogo.idsDeCategoria, ["camisa", "vestido"])
        XCTAssertEqual(
            catalogo.categoria(de: PecaSalva(termoIds: ["verde", "camisa"])),
            "Shirt")
        XCTAssertNil(catalogo.categoria(de: PecaSalva(termoIds: ["verde"])))
    }

    /// A38: `motivo_estampa` não é uma segunda dimensão para o usuário. Se ele
    /// escolher Stripes e Tomato, os dois competem dentro de Pattern (OR) em
    /// vez de se exigirem mutuamente (AND).
    func testMotivoDeEstampaFiltraDentroDeEstampa() {
        let catalogo = CatalogoDoArmario(termos: taxonomia)
        let listrada = PecaSalva(termoIds: ["camisa", "listra"])
        let tomate = PecaSalva(termoIds: ["vestido", "tomate_print"])
        let lisa = PecaSalva(termoIds: ["camisa", "verde"])

        let filtro = FiltroDoArmario(atributos: ["listra", "tomate_print"])
        let visiveis = filtro.aplicar(a: [listrada, tomate, lisa], catalogo: catalogo)
        XCTAssertEqual(visiveis.map(\.id), [listrada.id, tomate.id])
    }

    func testDimensoesDiferentesSaoAND_EMesmaDimensaoEhOR() {
        let catalogo = CatalogoDoArmario(termos: taxonomia)
        let verdeListrada = PecaSalva(termoIds: ["camisa", "verde", "listra"])
        let pretaListrada = PecaSalva(termoIds: ["camisa", "preto", "listra"])
        let verdeLisa = PecaSalva(termoIds: ["camisa", "verde"])
        let todas = [verdeListrada, pretaListrada, verdeLisa]

        // Cor + estampa: exige as duas dimensões.
        XCTAssertEqual(
            FiltroDoArmario(atributos: ["verde", "listra"])
                .aplicar(a: todas, catalogo: catalogo).map(\.id),
            [verdeListrada.id])

        // Duas cores: aceita qualquer uma delas.
        XCTAssertEqual(
            FiltroDoArmario(atributos: ["verde", "preto"])
                .aplicar(a: todas, catalogo: catalogo).map(\.id),
            todas.map(\.id))
    }

    func testFavoritoEBuscaCombinamComOsAtributos() {
        let catalogo = CatalogoDoArmario(termos: taxonomia)
        let favorita = PecaSalva(apelido: "Rugby", termoIds: ["camisa", "verde"],
                                 favorita: true)
        let comum = PecaSalva(termoIds: ["camisa", "verde"])
        let todas = [favorita, comum]

        XCTAssertEqual(
            FiltroDoArmario(somenteFavoritas: true)
                .aplicar(a: todas, catalogo: catalogo).map(\.id),
            [favorita.id])

        // Busca por nome dado pela pessoa.
        XCTAssertEqual(
            FiltroDoArmario(busca: "rug")
                .aplicar(a: todas, catalogo: catalogo).map(\.id),
            [favorita.id])

        // Busca por rótulo de atributo, já traduzido, e sem acento/caixa.
        XCTAssertEqual(
            FiltroDoArmario(busca: "GREEN")
                .aplicar(a: todas, catalogo: catalogo).map(\.id),
            todas.map(\.id))
    }

    /// Um id salvo que a taxonomia atual não conhece mais precisa ser
    /// ignorado. Tratá-lo como dimensão própria esvaziaria o armário sem dizer
    /// por quê — o oposto do que a tela fazia antes da extração.
    func testAtributoForaDaTaxonomiaNaoEsvaziaOArmario() {
        let catalogo = CatalogoDoArmario(termos: taxonomia)
        let peca = PecaSalva(termoIds: ["camisa", "verde"])
        XCTAssertEqual(
            FiltroDoArmario(atributos: ["termo_que_saiu_da_taxonomia"])
                .aplicar(a: [peca], catalogo: catalogo).map(\.id),
            [peca.id])
    }

    func testFiltroVazioDevolveTudoENaoSeDeclaraAtivo() {
        let catalogo = CatalogoDoArmario(termos: taxonomia)
        let todas = (0..<5).map { _ in PecaSalva(termoIds: ["camisa"]) }
        let filtro = FiltroDoArmario()
        XCTAssertFalse(filtro.ativo)
        XCTAssertEqual(filtro.aplicar(a: todas, catalogo: catalogo).count, 5)
    }

    // MARK: Custo

    /// O orçamento que o travamento de 25/08 não tinha.
    ///
    /// Cenário deliberadamente pessimista: armário no teto de peças, taxonomia
    /// do tamanho da real e busca preenchida — o caminho mais caro, que é o que
    /// roda a cada tecla digitada. Vinte passagens simulam vinte teclas.
    ///
    /// O limite é folgado de propósito. A forma correta faz isso em dezenas de
    /// milissegundos; a forma quadrática anterior reconstruía um dicionário de
    /// 212 termos por peça e levava dezenas de SEGUNDOS. Um teto de 1 s não
    /// oscila em CI e ainda assim separa os dois mundos por duas ordens de
    /// grandeza.
    func testFiltrarOArmarioCheioCabeNoOrcamentoDeInteracao() {
        var termos = taxonomia
        for i in 0..<205 {
            termos.append(termo("enchimento_\(i)", "Filler \(i)", "estetica"))
        }
        XCTAssertGreaterThanOrEqual(termos.count, 212)

        let catalogo = CatalogoDoArmario(termos: termos)
        let pecas = (0..<PecasSalvas.teto).map { i in
            PecaSalva(apelido: i % 3 == 0 ? "Peça \(i)" : "",
                      termoIds: ["camisa", "verde", "listra", "malha",
                                 "enchimento_\(i % 205)"])
        }
        XCTAssertEqual(pecas.count, 200)

        let filtro = FiltroDoArmario(atributos: ["verde", "listra"], busca: "shirt")
        let inicio = Date()
        var ultimo = 0
        for _ in 0..<20 {
            ultimo = filtro.aplicar(a: pecas, catalogo: catalogo).count
        }
        let gasto = Date().timeIntervalSince(inicio)

        XCTAssertEqual(ultimo, 200, "o cenário precisa casar, senão mede o atalho")
        XCTAssertLessThan(gasto, 1.0,
                          "20 filtragens de 200 peças levaram \(gasto)s; "
                          + "o filtro voltou a fazer trabalho por peça")
    }

    /// A mesma armadilha do outro lado: resolver nome com `termos:` monta o
    /// catálogo inteiro. Este teste fixa que a sobrecarga barata existe e
    /// devolve exatamente o mesmo nome, para as telas poderem migrar sem medo.
    func testResolverPorCatalogoDaOMesmoNomeQuePorTermos() {
        let catalogo = CatalogoDoArmario(termos: taxonomia)
        let semNome = PecaSalva(termoIds: ["verde", "camisa"])
        let comNome = PecaSalva(apelido: "Rugby", termoIds: ["camisa"])
        let placeholder = PecaSalva(apelido: "Replacing", termoIds: ["camisa"])
        let semCategoria = PecaSalva(termoIds: ["verde"])

        for peca in [semNome, comNome, placeholder, semCategoria] {
            XCTAssertEqual(NomeCompartilhavel.resolver(peca, catalogo: catalogo),
                           NomeCompartilhavel.resolver(peca, termos: taxonomia))
        }
        XCTAssertEqual(NomeCompartilhavel.resolver(semNome, catalogo: catalogo), "Shirt")
        XCTAssertEqual(NomeCompartilhavel.resolver(placeholder, catalogo: catalogo), "Shirt")
        XCTAssertEqual(NomeCompartilhavel.resolver(semCategoria, catalogo: catalogo),
                       "Clothing item")
    }
}
