import XCTest
@testable import CanarioLogica

/// Quando o teto diário de análise visual estourava, a pessoa via
/// **"The server returned 429."** — um código HTTP na cara de quem só queria
/// ler uma peça. O motivo exato já vinha no corpo da resposta e era descartado.
final class RecusaDaAnaliseTests: XCTestCase {

    private func mensagem(_ codigo: Int, _ erro: String) -> String {
        Supabase.Falha.mensagem(codigo: codigo,
                                corpo: #"{"error":"\#(erro)"}"#)
    }

    /// O caso mais provável, e o que mais precisa de clareza.
    func testTetoDaRedeExplicaOQueAconteceuEQuandoVolta() {
        let texto = mensagem(429, "daily_origin_limit")
        XCTAssertTrue(texto.contains("12"), "diz qual é o teto: \(texto)")
        XCTAssertTrue(texto.contains("midnight"), "diz quando volta: \(texto)")
        XCTAssertFalse(texto.contains("429"), "não joga o código na cara")
    }

    /// O teto é contado por IP. Chamar de "seu limite" seria mentira para duas
    /// pessoas no mesmo Wi-Fi, e mentira sobre limite é pior que silêncio.
    func testNaoChamaOTetoDeRedeDeLimitePessoal() {
        let texto = mensagem(429, "daily_origin_limit")
        XCTAssertTrue(texto.lowercased().contains("network"),
                      "o teto é por rede, e o texto tem de dizer isso: \(texto)")
        XCTAssertFalse(texto.lowercased().contains("your limit"))
        XCTAssertFalse(texto.lowercased().contains("you have"))
    }

    /// Teto do projeto e teto da rede são situações diferentes: uma a pessoa
    /// causou, a outra não. Dizer a mesma frase nas duas esconde qual é qual.
    func testTetoDoProjetoNaoSeConfundeComODaRede() {
        let rede = mensagem(429, "daily_origin_limit")
        let projeto = mensagem(429, "daily_project_limit")
        XCTAssertNotEqual(rede, projeto)
        XCTAssertTrue(projeto.contains("DataDrobe"), projeto)
    }

    /// Nenhuma dessas falhas impede adicionar a peça. Toda recusa lembra disso,
    /// para a pessoa não achar que o fluxo acabou ali.
    func testTodaRecusaOfereceOCaminhoManual() {
        for erro in ["daily_origin_limit", "daily_project_limit", "rate_limited",
                     "rate_limit_unavailable", "analysis_not_configured",
                     "analysis_contract_failed", "BOOT_ERROR", "coisa_nova"] {
            let texto = mensagem(429, erro)
            XCTAssertTrue(texto.contains("choose its attributes yourself"),
                          "\(erro) não oferece o caminho manual: \(texto)")
        }
    }

    /// Erro sobre a imagem é do arquivo, não do fluxo: ali o caminho manual não
    /// é a resposta, trocar a foto é.
    func testErroDeImagemPedeOutraFoto() {
        let texto = mensagem(400, "invalid_image")
        XCTAssertTrue(texto.contains("another photo"), texto)
        XCTAssertFalse(texto.contains("choose its attributes yourself"))
    }

    /// Código que eu não conheço continua aparecendo. Escondê-lo esconderia um
    /// caso novo justamente de quem pode consertar.
    func testCodigoDesconhecidoNaoDesaparece() {
        let texto = mensagem(503, "algo_que_ainda_nao_existe")
        XCTAssertTrue(texto.contains("503"), texto)
    }

    /// Corpo que não é JSON não pode derrubar a mensagem de erro.
    func testCorpoIlegivelNaoQuebra() {
        for corpo in ["", "<html>502 Bad Gateway</html>", "{", "null"] {
            let texto = Supabase.Falha.mensagem(codigo: 502, corpo: corpo)
            XCTAssertFalse(texto.isEmpty)
            XCTAssertTrue(texto.contains("502"), texto)
        }
    }

    func testCodigoDoCorpoAceitaAsDuasChaves() {
        XCTAssertEqual(
            Supabase.Falha.codigoDoCorpo(#"{"error":"invalid_image"}"#),
            "invalid_image")
        XCTAssertEqual(
            Supabase.Falha.codigoDoCorpo(#"{"code":"BOOT_ERROR"}"#),
            "BOOT_ERROR")
        XCTAssertNil(Supabase.Falha.codigoDoCorpo("nada disso"))
    }
}
