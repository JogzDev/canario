import XCTest
@testable import CanarioLogica

/// O formulário de importação deixava montar peça que não existe.
///
/// Este era o item 5 da lista do Codex, marcado por mim como "plausível e
/// barato de checar; não abri o formulário". Abri em 19/08/2026 e os dois
/// defeitos estavam lá:
///
/// 1. `FluxoDeChips` fazia `insert`/`remove` direto no conjunto, sem olhar
///    `Termo.exclusiva` — que vem do banco e chega ao app, mas nada lia. Dava
///    para marcar `vestido` e `calca` juntos, ou `floral` e `xadrez`.
/// 2. As dimensões visíveis dependem da categoria, mas o conjunto de marcados
///    nunca era podado. Escolher `vestido`, marcar comprimento `midi` e trocar
///    para `calca` escondia a linha e mandava `midi` para o relatório.
///
/// A taxonomia usada aqui é a real, consultada no banco em 19/08/2026:
/// exclusivas são categoria, cintura, comprimento, estampa e silhueta;
/// múltiplas são cor, estética e tecido.
final class FormularioDaPecaTests: XCTestCase {

    private func termo(_ id: String, _ dimensao: String,
                       exclusiva: Bool) -> Termo {
        Termo(id: id, rotulo: id, dimensao: dimensao, exclusiva: exclusiva,
              sinonimos: nil, semPernaBusca: nil, palavrasPt: nil,
              palavrasEn: nil)
    }

    private var taxonomia: [Termo] {
        [termo("vestido", "categoria", exclusiva: true),
         termo("calca", "categoria", exclusiva: true),
         termo("saia", "categoria", exclusiva: true),
         termo("midi", "comprimento", exclusiva: true),
         termo("longo", "comprimento", exclusiva: true),
         termo("cintura_alta", "cintura", exclusiva: true),
         termo("floral", "estampa", exclusiva: true),
         termo("xadrez", "estampa", exclusiva: true),
         termo("reta_wide", "silhueta", exclusiva: true),
         termo("preto", "cor", exclusiva: false),
         termo("azul", "cor", exclusiva: false),
         termo("linho", "tecido", exclusiva: false),
         termo("algodao", "tecido", exclusiva: false)]
    }

    private func termo(_ id: String) -> Termo {
        taxonomia.first { $0.id == id }!
    }

    // MARK: Exclusividade

    func testCategoriaExclusivaTrocaEmVezDeAcumular() {
        var marcados: Set<String> = []
        marcados = FormularioDaPeca.alternar(termo("vestido"), em: marcados,
                                             termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("calca"), em: marcados,
                                             termos: taxonomia)
        XCTAssertEqual(marcados, ["calca"],
                       "vestido e calça ao mesmo tempo é peça que não existe")
    }

    func testEstampaEComprimentoTambemSaoExclusivos() {
        var marcados = FormularioDaPeca.alternar(
            termo("vestido"), em: [], termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("floral"), em: marcados,
                                             termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("xadrez"), em: marcados,
                                             termos: taxonomia)
        XCTAssertTrue(marcados.contains("xadrez"))
        XCTAssertFalse(marcados.contains("floral"), "estampa é exclusiva")

        marcados = FormularioDaPeca.alternar(termo("midi"), em: marcados,
                                             termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("longo"), em: marcados,
                                             termos: taxonomia)
        XCTAssertTrue(marcados.contains("longo"))
        XCTAssertFalse(marcados.contains("midi"), "comprimento é exclusivo")
    }

    /// Cor, estética e tecido NÃO são exclusivas. Uma peça pode ser de linho e
    /// algodão, e forçar escolha única aqui seria estragar o dado.
    func testCorETecidoAceitamMaisDeUmValor() {
        var marcados = FormularioDaPeca.alternar(
            termo("vestido"), em: [], termos: taxonomia)
        for id in ["preto", "azul", "linho", "algodao"] {
            marcados = FormularioDaPeca.alternar(termo(id), em: marcados,
                                                 termos: taxonomia)
        }
        XCTAssertEqual(marcados,
                       ["vestido", "preto", "azul", "linho", "algodao"])
    }

    func testTocarNoMesmoChipDuasVezesDesmarca() {
        var marcados = FormularioDaPeca.alternar(
            termo("vestido"), em: [], termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("vestido"), em: marcados,
                                             termos: taxonomia)
        XCTAssertTrue(marcados.isEmpty)
    }

    // MARK: Poda ao trocar de categoria

    /// O caso silencioso: a linha some da tela e o atributo continua no envio.
    func testComprimentoNaoSobreviveATrocaParaCalca() {
        var marcados = FormularioDaPeca.alternar(
            termo("vestido"), em: [], termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("midi"), em: marcados,
                                             termos: taxonomia)
        XCTAssertEqual(marcados, ["vestido", "midi"])

        marcados = FormularioDaPeca.alternar(termo("calca"), em: marcados,
                                             termos: taxonomia)
        XCTAssertFalse(marcados.contains("midi"),
                       "calça com comprimento de vestido: ninguém escolheu "
                       + "isso e ninguém veria")
        XCTAssertEqual(marcados, ["calca"])
    }

    /// Trocar para saia mantém o comprimento, porque saia tem comprimento.
    /// A poda tira o que não cabe, não tudo que a pessoa marcou.
    func testTrocaEntreCategoriasCompativeisPreservaOAtributo() {
        var marcados = FormularioDaPeca.alternar(
            termo("vestido"), em: [], termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("midi"), em: marcados,
                                             termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("saia"), em: marcados,
                                             termos: taxonomia)
        XCTAssertEqual(marcados, ["saia", "midi"])
    }

    func testCorETecidoSobrevivemAQualquerTrocaDeCategoria() {
        var marcados = FormularioDaPeca.alternar(
            termo("vestido"), em: [], termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("preto"), em: marcados,
                                             termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("linho"), em: marcados,
                                             termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("calca"), em: marcados,
                                             termos: taxonomia)
        XCTAssertEqual(marcados, ["calca", "preto", "linho"])
    }

    func testTirarACategoriaLimpaOsAtributosDependentes() {
        var marcados = FormularioDaPeca.alternar(
            termo("vestido"), em: [], termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("midi"), em: marcados,
                                             termos: taxonomia)
        marcados = FormularioDaPeca.alternar(termo("vestido"), em: marcados,
                                             termos: taxonomia)
        XCTAssertTrue(marcados.isEmpty,
                      "sem categoria nenhuma dimensão faz sentido")
    }

    // MARK: Poda aplicada à sugestão da máquina

    /// A leitura visual devolve um valor por dimensão, então não sugere duas
    /// categorias — mas pode sugerir comprimento numa calça.
    func testPodaCorrigeSugestaoIncoerenteDaLeituraVisual() {
        let sugerido: Set<String> = ["calca", "midi", "preto", "cintura_alta"]
        let podado = FormularioDaPeca.podar(sugerido, termos: taxonomia)
        XCTAssertEqual(podado, ["calca", "preto", "cintura_alta"],
                       "calça tem cintura e não tem comprimento")
    }

    /// Sem a taxonomia carregada a poda não pode chutar: devolve o que recebeu.
    func testSemTaxonomiaCarregadaNadaEPodado() {
        let entrada: Set<String> = ["vestido", "midi"]
        XCTAssertEqual(FormularioDaPeca.podar(entrada, termos: []), entrada)
    }

    /// Id que o app não conhece pode ser termo novo do banco. Apagar seria
    /// perder escolha da pessoa por causa de um app desatualizado.
    func testIdDesconhecidoNaoEPodado() {
        let entrada: Set<String> = ["vestido", "termo_que_o_app_nao_conhece"]
        XCTAssertEqual(FormularioDaPeca.podar(entrada, termos: taxonomia),
                       entrada)
    }
}
