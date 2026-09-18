import Foundation
import XCTest
@testable import CanarioLogica

/// A busca que devolve a matéria, e não a tradução dela (A58).
///
/// O caso que originou tudo está aqui como teste: em 17/09/2026 o JP pesquisou
/// "Napoleon Jacket" -- a expressão exata de uma manchete que o próprio app
/// exibia -- e recebeu "Casacos e jaquetas". O título estava gravado: 1 entre
/// 172.649 artigos, Refinery29, 31/08/2026.
final class ReferenciaEditorialTests: XCTestCase {

    private func resposta(expressao: String = "Napoleon Jacket",
                          buscavel: Bool = true,
                          total: Int = 1,
                          materias: [ReferenciaEditorial.Materia]? = nil)
    -> ReferenciaEditorial.Resposta {
        ReferenciaEditorial.Resposta(
            expressao: expressao, buscavel: buscavel, total: total,
            materias: materias ?? [
                .init(titulo: "The Napoleon Jacket Is Making A Comeback This Fall",
                      veiculo: "Refinery29", data: "2026-08-31",
                      url: "https://exemplo/napoleon")])
    }

    func testContratoDaRPCChegaInteiro() throws {
        let json = #"{"expressao":"Napoleon Jacket","buscavel":true,"total":1,"materias":[{"titulo":"The Napoleon Jacket Is Making A Comeback This Fall","veiculo":"Refinery29","data":"2026-08-31","url":"https://exemplo/napoleon"}]}"#
        let r = try JSONDecoder().decode(
            ReferenciaEditorial.Resposta.self, from: Data(json.utf8))
        XCTAssertEqual(r.total, 1)
        XCTAssertEqual(r.materias.first?.veiculo, "Refinery29")
        XCTAssertEqual(r.materias.first?.procedencia, "Refinery29 · 31/08/2026")
        XCTAssertNotNil(r.materias.first?.endereco)
    }

    func testUmaMateriaFalaNoSingular() throws {
        let t = try XCTUnwrap(ReferenciaEditorial.manchete(resposta()))
        XCTAssertTrue(t.contains("1 story in the press we track mentions"))
        XCTAssertTrue(t.contains("“Napoleon Jacket”"),
                      "a expressão é do usuário e aparece entre aspas")
    }

    func testMuitasMateriasContamComSeparadorDeMilhar() throws {
        let t = try XCTUnwrap(
            ReferenciaEditorial.manchete(resposta(expressao: "dress", total: 1203)))
        XCTAssertTrue(t.contains("1,203 stories"))
        XCTAssertTrue(t.contains("mention "))
    }

    /// Expressão curta demais não é buscável, e o banco diz isso. A tela não
    /// pode transformar "não perguntei" em "não existe".
    func testExpressaoNaoBuscavelNaoAbreBloco() {
        XCTAssertNil(ReferenciaEditorial.manchete(
            resposta(expressao: "ja", buscavel: false, total: 0, materias: [])))
    }

    func testSemMateriaNaoAbreBloco() {
        XCTAssertNil(ReferenciaEditorial.manchete(resposta(total: 0, materias: [])))
    }

    /// Cinco linhas na tela não podem afirmar "cinco matérias" quando existem
    /// vinte e três: é o mesmo defeito que derrubou a manchete da capa, onde a
    /// amostra de 120 eventos era contada como se fosse a população.
    func testListaParcialSeDeclaraAmostra() throws {
        let cinco = (1...5).map { i in
            ReferenciaEditorial.Materia(
                titulo: "Matéria \(i)", veiculo: "Vogue",
                data: "2026-08-0\(i)", url: "https://exemplo/\(i)")
        }
        let r = resposta(total: 23, materias: cinco)
        XCTAssertEqual(ReferenciaEditorial.recorte(r), "Showing the 5 most recent.")
        XCTAssertNil(ReferenciaEditorial.recorte(resposta(total: 1)),
                     "lista completa não anuncia recorte")
    }

    /// O banco guarda título, veículo, data e link -- nunca o corpo. A tela
    /// tem de dizer isso, senão a ausência de resumo parece falha de produto.
    func testATelaDizOndeOTextoEstaEOndeNaoEsta() {
        XCTAssertTrue(ReferenciaEditorial.ondeEstaOTexto.contains("not the article"))
        XCTAssertTrue(ReferenciaEditorial.ondeEstaOTexto.contains("Open the source"))
    }

    /// Matéria sem veículo ou sem data continua legível: o que falta some, o
    /// que existe aparece, e nada é preenchido com valor plausível.
    func testProcedenciaSoMostraOQueExiste() {
        let semData = ReferenciaEditorial.Materia(
            titulo: "T", veiculo: "Elle", data: nil, url: "https://exemplo/x")
        XCTAssertEqual(semData.procedencia, "Elle")
        let semNada = ReferenciaEditorial.Materia(
            titulo: "T", veiculo: nil, data: nil, url: nil)
        XCTAssertEqual(semNada.procedencia, "")
        XCTAssertEqual(semNada.id, "T", "sem link, o título é a identidade")
    }
}
