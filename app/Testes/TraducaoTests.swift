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
              sinonimos: sinonimos, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
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

    func testBuscaPreservaPalavraHumanaSemMudarTaxonomia() {
        let vestido = termo("vestido", "Vestido", "categoria")
        let estampa = termo("geometrica", "Geometrica e etnica", "estampa",
                            "poa|bolinha|bolinhas|etnica")
        XCTAssertEqual(Traducao.rotuloAmigavel(estampa, na: "vestido de bolinha"),
                       "Polka dot")
        XCTAssertEqual(Traducao.rotuloAmigavel(estampa, na: "vestido de poá"),
                       "Polka dot")
        XCTAssertEqual(Traducao.descricaoAmigavel([vestido, estampa],
                                                  consulta: "vestido de bolinhas"),
                       "Dress · Polka dot")
        XCTAssertEqual(estampa.id, "geometrica",
                       "linguagem amigável não cria uma série nova nem altera o id")
    }

    func testRotulosEmInglesSemMudarIds() {
        let calca = termo("calca", "Calca", "categoria")
        let romantico = termo("romantico", "Romantico", "estetica")
        XCTAssertEqual(Traducao.rotuloExibido(calca), "Pants")
        XCTAssertEqual(Traducao.rotuloExibido(romantico), "Romantic")
        XCTAssertEqual(calca.id, "calca", "a série histórica continua no mesmo id")
    }

    func testFormularioSoPerguntaMedidasQueCabemNaCategoria() {
        let casaco = FormularioDaPeca.dimensoesPermitidas(categorias: ["casaco_jaqueta"])
        XCTAssertFalse(casaco.contains("cintura"))
        XCTAssertFalse(casaco.contains("comprimento"))
        XCTAssertFalse(casaco.contains("silhueta"))

        let calca = FormularioDaPeca.dimensoesPermitidas(categorias: ["calca"])
        XCTAssertTrue(calca.contains("cintura"))
        XCTAssertTrue(calca.contains("silhueta"))
        XCTAssertFalse(calca.contains("comprimento"))

        let vestido = FormularioDaPeca.dimensoesPermitidas(categorias: ["vestido"])
        XCTAssertTrue(vestido.contains("comprimento"))
        XCTAssertFalse(vestido.contains("cintura"))
    }

    func testSemCategoriaFormularioNaoFingeQueReconheceuUmaPeca() {
        let termos = [
            termo("vestido", "Vestido", "categoria"),
            termo("verde", "Verde", "cor"),
        ]
        XCTAssertFalse(FormularioDaPeca.temCategoria(["verde"], termos: termos))
        XCTAssertTrue(FormularioDaPeca.temCategoria(["vestido", "verde"], termos: termos))
        XCTAssertEqual(FormularioDaPeca.dimensoesPermitidas(categorias: []), ["categoria"])
    }

    func testOCRLocalPodeReconhecerMarcaSemInventarProduto() {
        XCTAssertEqual(Importacao.marcasNoTexto("PATAGONIA\nBetter Sweater"), ["Patagonia"])
        XCTAssertEqual(Importacao.marcasNoTexto("Maria Filó vestido midi"), ["Maria Filó"])
        XCTAssertEqual(Importacao.marcasNoTexto("FARM RIO"), ["Farm Rio"])
        XCTAssertTrue(Importacao.marcasNoTexto("jaqueta preta sem logotipo").isEmpty)
        XCTAssertTrue(Importacao.marcasNoTexto("farm equipment").isEmpty,
                      "Farm sem Rio é palavra comum em inglês, não prova de marca")
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
                       "based on: search + Brazilian editorial")
        XCTAssertEqual(Perna.frase([]), "no active source")
        XCTAssertEqual(Perna.frase(nil), "no active source")
    }
}

/// Casos que nasceram de falhas reais no primeiro `swift test`.
extension TraducaoTests {

    private func t(_ id: String, _ rotulo: String, _ sin: String? = nil) -> Termo {
        Termo(id: id, rotulo: rotulo, dimensao: "categoria", exclusiva: true,
              sinonimos: sin, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
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

    func testIdadeDaAtualizacaoUsaDataDeCalendario() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        // Meio-dia UTC ainda é dia 13 em Brasília; meia-noite UTC seria 21h
        // do dia 12 e não representaria o "hoje" declarado pelo teste.
        let hoje = f.date(from: "2026-08-13 12:00")!
        XCTAssertEqual(Formato.diasDesde("2026-08-10", hoje: hoje), 3)
        XCTAssertEqual(Formato.diasDesde("2026-06-29", hoje: hoje), 45)
        XCTAssertEqual(Formato.diasDesde("2026-08-14", hoje: hoje), 0)
        XCTAssertEqual(Formato.diasDesde("sem data", hoje: hoje), 0)
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

/// Entrada por arquivo (§28): o texto lido do print vira atributo pelo MESMO
/// tradutor que converte título de produto. Estes casos usam títulos reais do
/// banco, como o OCR os entregaria.
final class ImportacaoTests: XCTestCase {

    private var taxonomia: [Termo] {
        [t("vestido", "Vestido", "categoria", "vestidinho"),
         t("midi", "Midi", "comprimento"),
         t("longo", "Longo", "comprimento", "maxi"),
         t("floral", "Floral", "estampa", "estampa floral|florido|flores"),
         t("branco_cru", "Branco e cru", "cor", "off white|areia|bege claro"),
         t("preto", "Preto", "cor", "preta"),
         t("reta_wide", "Reta e wide", "silhueta", "wide leg|pantalona reta"),
         t("calca", "Calca", "categoria", "pantalona"),
         t("alfaiataria", "Alfaiataria", "estetica", "tailoring|social"),
         t("cintura_alta", "Cintura alta", "cintura", "cos alto")]
    }

    private func t(_ id: String, _ rotulo: String, _ dim: String,
                   _ sin: String? = nil) -> Termo {
        Termo(id: id, rotulo: rotulo, dimensao: dim, exclusiva: true,
              sinonimos: sin, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    /// Print de página de produto: o OCR entrega o título junto de preço e
    /// navegação. O ruído em volta não pode virar atributo.
    func testPrintDePaginaDeProduto() {
        let ocr = """
        Início / Vestidos / Midi
        VESTIDO MIDI FLORAL OFF WHITE
        R$ 799,00 em até 6x sem juros
        Adicionar à sacola
        """
        let ids = Set(Traducao.termos(para: ocr, em: taxonomia).map(\.id))
        XCTAssertTrue(ids.contains("vestido"))
        XCTAssertTrue(ids.contains("midi"))
        XCTAssertTrue(ids.contains("floral"))
        XCTAssertTrue(ids.contains("branco_cru"), "'off white' é sinônimo de branco e cru")
        XCTAssertFalse(ids.contains("longo"), "midi não é longo")
        XCTAssertFalse(ids.contains("preto"))
    }

    func testFichaEmPDF() {
        let pdf = """
        FICHA TÉCNICA
        Referência: 5CMVLNNEN
        Descrição: Calça Wide Leg Alfaiataria Cintura Alta Preta
        Composição: 63% poliéster
        """
        let ids = Set(Traducao.termos(para: pdf, em: taxonomia).map(\.id))
        XCTAssertTrue(ids.contains("calca"))
        XCTAssertTrue(ids.contains("reta_wide"))
        XCTAssertTrue(ids.contains("alfaiataria"))
        XCTAssertTrue(ids.contains("cintura_alta"))
        XCTAssertTrue(ids.contains("preto"))
    }

    /// A regressão crítica atravessa a entrada por arquivo também: um print de
    /// peça preta não pode marcar a silhueta reta.
    func testRegressaoRetaPretaNoTextoLido() {
        let ocr = "VESTIDO LONGO PRETO\nR$ 459,00"
        let ids = Set(Traducao.termos(para: ocr, em: taxonomia).map(\.id))
        XCTAssertTrue(ids.contains("preto"))
        XCTAssertFalse(ids.contains("reta_wide"), "'preta' não pode virar silhueta reta")
    }

    /// Arquivo sem nenhum termo: a tela precisa saber que não achou nada, para
    /// dizer isso em vez de abrir um formulário vazio sem explicação.
    func testArquivoSemTermoDaTaxonomia() {
        let ocr = "Recibo de pagamento\nValor total: R$ 1.200,00"
        XCTAssertTrue(Traducao.termos(para: ocr, em: taxonomia).isEmpty)
    }
}
