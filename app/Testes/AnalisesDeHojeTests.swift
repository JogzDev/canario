import XCTest
@testable import CanarioLogica

/// O JP pediu um indicador de quantas consultas restam no dia. A conta que ele
/// imaginou — 12 menos o que você usou — o app **não tem como fazer**: o teto do
/// servidor é por IP, então duas pessoas no mesmo Wi-Fi dividem as 12.
///
/// Estes testes travam a diferença entre o que o app sabe (quantas ELE pediu) e
/// o que ele não sabe (quantas sobraram).
final class AnalisesDeHojeTests: XCTestCase {

    private func emSaoPaulo(_ texto: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: texto)!
    }

    // MARK: O que o app não pode prometer

    /// Nenhuma subtração, em nenhum caso. "Você tem 3 restantes" seria promessa
    /// de saldo que pode não existir, e a mentira apareceria justamente no
    /// momento do bloqueio.
    func testNuncaAfirmaQuantasRestam() {
        for usadas in ContadorDeAnalises.avisarAPartirDe...20 {
            let texto = ContadorDeAnalises.aviso(
                AnalisesDeHoje(dia: ContadorDeAnalises.dia(), quantidade: usadas))
            let t = try! XCTUnwrap(texto).lowercased()
            XCTAssertFalse(t.contains("remaining"), t)
            XCTAssertFalse(t.contains("left"), t)
            XCTAssertFalse(t.contains("you have"), t)
        }
    }

    /// E diz que o teto é compartilhado, que é o fato que explica por que a
    /// conta não fecha.
    func testDizQueOTetoEDaRedeENaoDoAparelho() {
        let texto = ContadorDeAnalises.aviso(
            AnalisesDeHoje(dia: ContadorDeAnalises.dia(), quantidade: 10))
        let t = try! XCTUnwrap(texto)
        XCTAssertTrue(t.contains("network"), t)
        XCTAssertTrue(t.contains("\(ContadorDeAnalises.tetoPorRede)"), t)
    }

    // MARK: Quando fala e quando cala

    /// Doze análises num dia é muito para quase todo mundo. Contador permanente
    /// seria peso visual constante para evento raro.
    func testFicaCaladoLongeDoTeto() {
        let hoje = ContadorDeAnalises.dia()
        for usadas in 0..<ContadorDeAnalises.avisarAPartirDe {
            XCTAssertNil(
                ContadorDeAnalises.aviso(AnalisesDeHoje(dia: hoje, quantidade: usadas)),
                "avisou com \(usadas) de \(ContadorDeAnalises.tetoPorRede)")
        }
        XCTAssertNotNil(ContadorDeAnalises.aviso(
            AnalisesDeHoje(dia: hoje, quantidade: ContadorDeAnalises.avisarAPartirDe)))
    }

    /// Aviso de ontem não vale hoje.
    func testContagemDeOutroDiaNaoAvisa() {
        XCTAssertNil(ContadorDeAnalises.aviso(
            AnalisesDeHoje(dia: "2020-01-01", quantidade: 99)))
        XCTAssertNil(ContadorDeAnalises.aviso(nil))
    }

    // MARK: A virada do dia

    /// O teto do servidor vira à meia-noite de São Paulo. Contar no fuso do
    /// aparelho faria o app zerar em hora diferente do teto que ele descreve.
    func testDiaSegueSaoPauloENaoOFusoDoAparelho() {
        // 20/08 às 02:00 UTC ainda é 19/08 em São Paulo.
        XCTAssertEqual(
            ContadorDeAnalises.dia(emSaoPaulo("2026-08-20T02:00:00Z")), "2026-08-19")
        // 20/08 às 04:00 UTC já é 20/08 em São Paulo.
        XCTAssertEqual(
            ContadorDeAnalises.dia(emSaoPaulo("2026-08-20T04:00:00Z")), "2026-08-20")
    }

    func testViradaDoDiaZeraAContagem() {
        let ontem = AnalisesDeHoje(dia: "2026-08-19", quantidade: 11)
        let depois = ContadorDeAnalises.registrar(
            ontem, agora: emSaoPaulo("2026-08-20T04:00:00Z"))
        XCTAssertEqual(depois.dia, "2026-08-20")
        XCTAssertEqual(depois.quantidade, 1)
    }

    func testRegistrarSomaDentroDoMesmoDia() {
        let agora = emSaoPaulo("2026-08-20T15:00:00Z")
        var estado = ContadorDeAnalises.registrar(nil, agora: agora)
        XCTAssertEqual(estado.quantidade, 1)
        for esperado in 2...5 {
            estado = ContadorDeAnalises.registrar(estado, agora: agora)
            XCTAssertEqual(estado.quantidade, esperado)
        }
        XCTAssertEqual(estado.dia, "2026-08-20")
    }

    /// O 12 daqui é o mesmo de `_reservar_analise_visual`. Se um mudar sem o
    /// outro, o app passa a descrever um teto que não existe.
    func testTetoBateComOServidor() {
        XCTAssertEqual(ContadorDeAnalises.tetoPorRede, 12)
        XCTAssertLessThan(ContadorDeAnalises.avisarAPartirDe,
                          ContadorDeAnalises.tetoPorRede)
    }
}
