import XCTest
@testable import CanarioLogica

/// O bloco de similares aceita casamento parcial de propósito — exigir todos os
/// atributos deixaria a lista quase vazia. O que faltava era **dizer** qual
/// atributo ficou de fora.
///
/// O caso que motivou: em 19/08/2026 um testador enviou uma camiseta listrada
/// com `listra` marcada e viu peças lisas na lista. Medido contra a produção com
/// `['camisa','listra','branco_cru','algodao']`: 78 candidatos, apenas 2 com os
/// quatro atributos, e 6 das 12 exibidas sem listra nenhuma.
///
/// O app não estava errado — mostrava a terceira peça mais parecida que existe.
/// Estava calado, que nesse contexto dá no mesmo para quem lê.
final class CasamentoDeSimilaresTests: XCTestCase {

    private func termo(_ id: String, _ rotulo: String, _ dimensao: String) -> Termo {
        Termo(id: id, rotulo: rotulo, dimensao: dimensao, exclusiva: true,
              sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    private var pedidos: [Termo] {
        [termo("camisa", "Camisa", "categoria"),
         termo("listra", "Listra", "estampa"),
         termo("branco_cru", "Branco/Cru", "cor"),
         termo("algodao", "Algodão", "tecido")]
    }

    private func peca(emComum: Int, tem: [String]?) -> Similares.Peca {
        Similares.Peca(
            id: 1, marca: "C&A", papelDaMarca: nil, titulo: "Camisa",
            url: nil, imagem: nil, preco: nil, precoDe: nil, quedaPct: nil,
            emComum: emComum, termosEmComum: tem, grade: nil)
    }

    /// O caso do testador: a peça bate em três, e a que falta é justamente a
    /// que se enxerga na foto. O texto tem de nomeá-la.
    func testPecaSemListraDizQueNaoTemListra() {
        let texto = Similares.casamento(
            peca(emComum: 3, tem: ["camisa", "branco_cru", "algodao"]),
            pedidos: pedidos)
        XCTAssertEqual(texto, "3 of 4 · no stripes",
                       "o rótulo vem traduzido: o app é em inglês, e `listra` "
                       + "é id da taxonomia, não texto de interface")
    }

    func testPecaCompletaNaoAcusaDiferenca() {
        let texto = Similares.casamento(
            peca(emComum: 4, tem: ["camisa", "listra", "branco_cru", "algodao"]),
            pedidos: pedidos)
        XCTAssertEqual(texto, "All 4 attributes")
    }

    /// Duas ausências usam "or", não "and": são atributos que a peça NÃO tem, e
    /// "and" leria como se ela tivesse os dois.
    func testDuasAusenciasUsamOu() {
        let texto = Similares.casamento(
            peca(emComum: 2, tem: ["camisa", "branco_cru"]),
            pedidos: pedidos)
        XCTAssertEqual(texto, "2 of 4 · no stripes or cotton")
    }

    func testTresAusenciasSeparamComVirgulaEOu() {
        let texto = Similares.casamento(
            peca(emComum: 1, tem: ["camisa"]), pedidos: pedidos)
        XCTAssertEqual(texto, "1 of 4 · no stripes, white & cream or cotton")
    }

    /// Banco anterior ao P14 devolve a contagem sem a lista. Mostrar só o número
    /// é menos do que o ideal e ainda assim melhor que ficar calado — mas não
    /// pode inventar qual atributo faltou.
    func testSemAListaMostraSoAContagem() {
        XCTAssertEqual(
            Similares.casamento(peca(emComum: 3, tem: nil), pedidos: pedidos),
            "3 of 4 attributes")
        XCTAssertEqual(
            Similares.casamento(peca(emComum: 4, tem: nil), pedidos: pedidos),
            "All 4 attributes")
    }

    /// Sem atributos marcados não há casamento a relatar, e a etiqueta some em
    /// vez de dizer "0 of 0".
    func testSemAtributosNaoMostraEtiqueta() {
        XCTAssertNil(Similares.casamento(peca(emComum: 0, tem: []), pedidos: []))
    }

    /// Peça que traz um termo fora do pedido não vira "diferença": o que importa
    /// é só o que a pessoa marcou.
    func testTermoExtraNaPecaNaoAfetaOTexto() {
        let texto = Similares.casamento(
            peca(emComum: 4,
                 tem: ["camisa", "listra", "branco_cru", "algodao", "festa_brilho"]),
            pedidos: pedidos)
        XCTAssertEqual(texto, "All 4 attributes")
    }
}
