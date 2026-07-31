import XCTest
@testable import CanarioLogica

/// Testes da tradução da busca (§11) e do vocabulário de estado (§22).
///
/// A regressão obrigatória é a mesma do lado do coletor: `reta` não pode casar
/// `preta`. Ela vive aqui também porque o app faz o casamento por conta
/// própria, e um bug aqui produziria a mesma leitura errada na tela.
final class TraducaoTests: XCTestCase {

    private func termo(_ id: String, _ rotulo: String, _ dimensao: String,
                       _ sinonimos: String? = nil) -> Termo {
        Termo(id: id, rotulo: rotulo, dimensao: dimensao, exclusiva: true,
              sinonimos: sinonimos, semPernaBusca: nil)
    }

    // MARK: A regressão crítica

    func testRetaNaoCasaPreta() {
        let reta = termo("reta_wide", "Reta e wide", "silhueta", "wide leg|pantalona reta")
        XCTAssertFalse(Traducao.casa("vestido preta", reta),
                       "peça preta não pode casar com silhueta reta")
        XCTAssertFalse(Traducao.casa("preta", reta))
    }

    func testCasaPalavraInteira() {
        let casaco = termo("casaco_jaqueta", "Casaco e jaqueta", "categoria", "blazer")
        XCTAssertTrue(Traducao.casa("casaco de linho", casaco))
        let cor = termo("branco_cru", "Branco e cru", "cor", "off white|areia")
        // "cru" não pode ser encontrado dentro de "cruzado".
        XCTAssertFalse(Traducao.casa("vestido cruzado", cor))
    }

    // MARK: Comportamento esperado da busca

    func testCasaPorRotulo() {
        let floral = termo("floral", "Floral", "estampa", "estampa floral|florido")
        XCTAssertTrue(Traducao.casa("floral", floral))
        XCTAssertTrue(Traducao.casa("Vestido FLORAL midi", floral), "sem acento e sem caixa")
    }

    func testCasaPorSinonimo() {
        let floral = termo("floral", "Floral", "estampa", "estampa floral|florido|flores")
        XCTAssertTrue(Traducao.casa("quero florido", floral))
        XCTAssertTrue(Traducao.casa("com flores", floral))
    }

    func testCasaPorId() {
        let t = termo("blusa_top", "Blusa e top", "categoria")
        XCTAssertTrue(Traducao.casa("blusa", t), "o id vira 'blusa top' e casa por palavra")
    }

    func testExpressaoDeVariasPalavrasExigeTodas() {
        // O termo é escolhido de propósito: o rótulo "Romântico" NÃO contém
        // "manga" nem "bufante", então a única via de casamento é a expressão
        // inteira. Usar um termo cujo rótulo já traz a palavra solta testaria
        // outra coisa — foi o erro da primeira versão deste teste.
        let romantico = termo("romantico", "Romântico", "estetica", "manga bufante|renda")
        XCTAssertTrue(Traducao.casa("blusa manga bufante", romantico))
        XCTAssertFalse(Traducao.casa("blusa manga curta", romantico),
                       "só metade da expressão não basta")
        XCTAssertFalse(Traducao.casa("bufante", romantico))
    }

    func testConsultaVaziaNaoCasaNada() {
        let t = termo("vestido", "Vestido", "categoria")
        XCTAssertFalse(Traducao.casa("", t))
        XCTAssertFalse(Traducao.casa("   ", t))
    }

    func testTermoForaDaTaxonomiaNaoInventaResultado() {
        let todos = [termo("vestido", "Vestido", "categoria"),
                     termo("floral", "Floral", "estampa")]
        // §11: o que não casa gera resposta honesta, não um resultado plausível.
        XCTAssertTrue(Traducao.termos(para: "neoprene holográfico", em: todos).isEmpty)
    }
}

/// O vocabulário de estado é onde a regra 2 pode ser violada em silêncio.
final class EstadoTests: XCTestCase {

    func testEstadoNuloNaoViraEstavel() {
        // A §22 exige duas fontes concordando. Sem estado declarado, o app não
        // pode inventar "estável" — precisa dizer que não sabe.
        XCTAssertNil(Estado(rawValue: ""))
        XCTAssertNil(Estado(rawValue: "indefinido"))
    }

    func testRotulosNaoCarregamDuracao() {
        // §27: estados sem duração no título; janela vai para a letra miúda.
        for e in [Estado.emAlta, .emQueda, .pico, .estavel] {
            XCTAssertFalse(e.rotulo.lowercased().contains("semana"))
            XCTAssertFalse(e.rotulo.lowercased().contains("dia"))
            XCTAssertFalse(e.icone.isEmpty, "§32: estado nunca só por cor")
        }
    }

    func testFraseDePernasDeclaraOrigem() {
        // §8: a interface declara quais pernas sustentam o número.
        XCTAssertEqual(Perna.frase(["busca", "editorial_br"]),
                       "baseado em: busca + editorial BR")
        XCTAssertEqual(Perna.frase([]), "sem perna ativa")
        XCTAssertEqual(Perna.frase(nil), "sem perna ativa")
    }
}

/// Casos que nasceram de falhas reais no primeiro `swift test`.
extension TraducaoTests {

    private func t(_ id: String, _ rotulo: String, _ sin: String? = nil) -> Termo {
        Termo(id: id, rotulo: rotulo, dimensao: "categoria", exclusiva: true,
              sinonimos: sin, semPernaBusca: nil)
    }

    /// Rótulo enumerado: cada lado do "e" vale sozinho.
    func testEnumeracaoCasaCadaLadoSozinho() {
        let casaco = t("casaco_jaqueta", "Casaco e jaqueta", "blazer|cardigan")
        XCTAssertTrue(Traducao.casa("casaco de linho", casaco))
        XCTAssertTrue(Traducao.casa("jaqueta jeans", casaco))
        XCTAssertTrue(Traducao.casa("blazer", casaco), "sinônimo também")

        let blusa = t("blusa_top", "Blusa e top", "cropped|regata")
        XCTAssertTrue(Traducao.casa("blusa", blusa))
        XCTAssertTrue(Traducao.casa("cropped preto", blusa))

        let branco = t("branco_cru", "Branco e cru", "off white|areia")
        XCTAssertTrue(Traducao.casa("vestido branco", branco))
    }

    /// Expressão continua exigindo as palavras juntas — a enumeração não pode
    /// afrouxar isso, senão "wide" sozinho casaria a silhueta.
    func testExpressaoNaoAfrouxouComAEnumeracao() {
        let wide = t("reta_wide", "Reta e wide", "wide leg|pantalona reta")
        XCTAssertTrue(Traducao.casa("calca wide leg", wide))
        // "wide" sozinho CASA, e está certo: o rótulo é "Reta e wide", ou seja,
        // a própria taxonomia declara "wide" como nome deste termo. A primeira
        // versão deste teste afirmava o contrário e estava errada.
        XCTAssertTrue(Traducao.casa("calca wide", wide))
        // O que não pode afrouxar é a expressão de um termo cujo rótulo não
        // traz a palavra solta.
        let romantico = t("romantico", "Romântico", "manga bufante")
        XCTAssertFalse(Traducao.casa("manga longa", romantico))
        // E a regressão crítica continua de pé depois da mudança.
        XCTAssertFalse(Traducao.casa("vestido preta", wide))
    }
}

/// Construção de URL de consulta.
///
/// Nasceu de um CRASH real: a consulta de Explorar tinha
/// `estado=in.("em alta","em queda",pico)` com espaços literais. A URL ficava
/// inválida, `URLComponents.url` devolvia nil e o app morria com SIGTRAP num
/// force-unwrap — fechava na cara do usuário ao tocar na aba.
final class ConsultaTests: XCTestCase {

    /// Espaço e aspas precisam sair codificados, senão a URL é inválida.
    func testEspacoEAspasSaoCodificados() {
        let cru = "select=*&estado=in.(\"em alta\",\"em queda\",pico)&limit=20"
        let codificado = Supabase.codificar(cru)
        XCTAssertFalse(codificado.contains(" "), "espaço literal invalida a URL")
        XCTAssertFalse(codificado.contains("\""), "aspas literais invalidam a URL")
        XCTAssertTrue(codificado.contains("%20"))
    }

    /// A sintaxe do PostgREST não pode ser escapada, senão o servidor não
    /// entende o filtro e devolve a tabela inteira — ou nada.
    func testSintaxeDoPostgRESTSobrevive() {
        let codificado = Supabase.codificar("select=*&termo_id=eq.floral&order=semana.desc")
        XCTAssertTrue(codificado.contains("select=*"))
        XCTAssertTrue(codificado.contains("termo_id=eq.floral"))
        XCTAssertTrue(codificado.contains("order=semana.desc"))
        XCTAssertTrue(codificado.contains("&"))
    }

    /// A URL final tem de ser construível para toda consulta que o app usa.
    /// Este é o teste que teria evitado o crash.
    func testTodaConsultaDoAppProduzURLValida() {
        let consultas = [
            "select=id,rotulo,dimensao,exclusiva,sinonimos,sem_perna_busca&order=dimensao,id",
            "select=*&order=semana.desc&limit=400",
            "select=*&estado=in.(\"em alta\",\"em queda\",pico)&order=semana.desc&limit=20",
            "select=*&termo_id=eq.branco_cru&order=semana.desc&limit=600",
        ]
        for consulta in consultas {
            var c = URLComponents(string: "https://exemplo.supabase.co/rest/v1/tabela")!
            c.percentEncodedQuery = Supabase.codificar(consulta)
            XCTAssertNotNil(c.url, "consulta produziu URL inválida: \(consulta)")
        }
    }
}

/// Formato de data e hora (regra do JP, 30/07): data sempre em dd/MM/aaaa e
/// horário sempre de Brasília, no app e no código.
final class FormatoTests: XCTestCase {

    func testDataSaiNoFormatoBrasileiro() {
        XCTAssertEqual(Formato.data("2026-07-27"), "27/07/2026")
        XCTAssertEqual(Formato.data("2026-01-05"), "05/01/2026")
        // A entrada pode vir com hora junto; só a parte da data importa aqui.
        XCTAssertEqual(Formato.data("2026-12-31T23:00:00Z"), "31/12/2026")
    }

    func testNenhumaDataISOVazaParaATela() {
        // Uma data ISO na tela é o sintoma que este teste existe para pegar.
        let saida = Formato.data("2026-07-27")
        XCTAssertFalse(saida.contains("-"), "ISO não pode chegar à interface")
    }

    func testEntradaMalformadaNaoViraTraco() {
        // Esconder dado ruim atrás de "—" é pior que mostrá-lo: some o sintoma.
        XCTAssertEqual(Formato.data("sem data"), "sem data")
    }

    func testHoraEmBrasiliaNaoEmUTC() {
        // O servidor grava UTC (cron em UTC, Postgres em UTC). Sem conversão, a
        // "última coleta" apareceria três horas adiantada.
        let saida = Formato.dataEHora("2026-07-27T23:30:00Z")
        XCTAssertTrue(saida.hasPrefix("27/07/2026"), "23:30 UTC ainda é dia 27 em Brasília")
        XCTAssertTrue(saida.contains("20:30"), "UTC-3: 23:30 UTC = 20:30 em Brasília")
    }

    func testFusoEDeBrasiliaNaoDoAparelho() {
        XCTAssertEqual(Formato.brasilia.identifier, "America/Sao_Paulo")
    }
}
