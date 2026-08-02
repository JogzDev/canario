import XCTest
@testable import CanarioLogica

/// Testes do índice do cluster (§22, K5).
///
/// O JSON abaixo é o que o servidor **realmente devolveu** em 02/08/2026 para
/// "vestido + floral + midi". Testar contra JSON de verdade, e não contra
/// structs montadas à mão, é o que faz este arquivo pegar erro de `CodingKeys`
/// — que é o tipo de defeito que compila, passa em teste inventado e só aparece
/// na tela.
///
/// A fronteira que estes testes guardam é a da §5: um número único por peça é
/// exatamente onde "score" entra sem pedir licença. Por isso a maior parte
/// deles verifica o que o texto **não** diz.
final class ClusterTests: XCTestCase {

    /// Caso real, e o mais importante: os três atributos DISCORDAM.
    /// vestido -3,10 · floral +0,29 · midi -0,47. Média -0,77, dispersão 1,28.
    private let jsonDiscordante = """
    {
      "indice": -0.7679,
      "dispersao": 1.2840,
      "atributos_efetivos": 2.83,
      "n_atributos": 3,
      "ha_direcao": false,
      "categoria_usada": "vestido",
      "unidade": "desvios-padrao da propria historia de cada atributo (§21)",
      "atributos": [
        {"termo_id":"midi","rotulo":"Midi","dimensao":"comprimento",
         "papel":"atributo","indice":-0.4707,"estado":"estavel",
         "semana":"2026-07-27","pernas":["editorial_br","editorial_intl"],
         "peso":1.2919,"peso_relativo":0.4096,"pecas_no_painel":3542,
         "pct_na_dimensao":38.2,"fora_por":null},
        {"termo_id":"floral","rotulo":"Floral","dimensao":"estampa",
         "papel":"atributo","indice":0.2887,"estado":null,
         "semana":"2026-07-13","pernas":["busca"],
         "peso":1.1686,"peso_relativo":0.3705,"pecas_no_painel":571,
         "pct_na_dimensao":45.4,"fora_por":null},
        {"termo_id":"vestido","rotulo":"Vestido","dimensao":"categoria",
         "papel":"atributo","indice":-3.1032,"estado":"em queda",
         "semana":"2026-07-27","pernas":["editorial_br","editorial_intl"],
         "peso":0.6932,"peso_relativo":0.2198,"pecas_no_painel":11579,
         "pct_na_dimensao":100.0,"fora_por":null}
      ]
    }
    """

    private func decodificar(_ s: String) throws -> Cluster.Resposta {
        try JSONDecoder().decode(Cluster.Resposta.self, from: Data(s.utf8))
    }

    // MARK: A recusa — o teste mais importante do arquivo

    func testNaoAfirmaDirecaoQuandoOsAtributosDiscordam() throws {
        let r = try decodificar(jsonDiscordante)
        XCTAssertFalse(r.haDirecao)

        let m = Cluster.manchete(r)
        XCTAssertEqual(m, "Os atributos desta peça não apontam para o mesmo lado.")

        // E não pode escorregar para nenhuma das frases de direção.
        for proibida in ["acima do normal", "abaixo do normal", "em queda", "em alta"] {
            XCTAssertFalse(m.lowercased().contains(proibida),
                           "a manchete afirmou \"\(proibida)\" com atributos discordantes")
        }
    }

    func testAExplicacaoDizPorQueSeCalou() throws {
        let r = try decodificar(jsonDiscordante)
        let e = try XCTUnwrap(Cluster.explicacao(r))
        XCTAssertTrue(e.contains("1,28"), "faltou a dispersão medida: \(e)")
        XCTAssertTrue(e.contains("não digo para que lado"))
    }

    /// A média existe e continua visível — o app não esconde o número, ele
    /// recusa a INTERPRETAÇÃO do número. São coisas diferentes.
    func testONumeroContinuaVisivelComUnidade() throws {
        let r = try decodificar(jsonDiscordante)
        let e = try XCTUnwrap(Cluster.explicacao(r))
        XCTAssertTrue(e.contains("-0,77"), "faltou o índice: \(e)")
        XCTAssertTrue(e.contains("desvios-padrão"),
                      "K6: número sem unidade é o \"1,15 o quê?\" de 31/07")
    }

    // MARK: Direção, quando ela existe

    func testAfirmaDirecaoQuandoOSinalSuperaADiscordancia() throws {
        let json = """
        {"indice": 1.8, "dispersao": 0.3, "atributos_efetivos": 1.98,
         "n_atributos": 2, "ha_direcao": true, "categoria_usada": "saia",
         "unidade": "z", "atributos": [
          {"termo_id":"a","rotulo":"A","dimensao":"cor","papel":"atributo",
           "indice":1.9,"estado":"em alta","semana":"2026-07-27","pernas":["busca"],
           "peso":2.0,"peso_relativo":0.5,"pecas_no_painel":100,
           "pct_na_dimensao":10.0,"fora_por":null},
          {"termo_id":"b","rotulo":"B","dimensao":"tecido","papel":"atributo",
           "indice":1.7,"estado":"em alta","semana":"2026-07-27","pernas":["busca"],
           "peso":2.0,"peso_relativo":0.5,"pecas_no_painel":100,
           "pct_na_dimensao":10.0,"fora_por":null}]}
        """
        let r = try decodificar(json)
        XCTAssertEqual(Cluster.manchete(r), "O conjunto está acima do normal.")
    }

    func testComUmAtributoSoDizQueNaoHaConjunto() throws {
        let json = """
        {"indice": -0.46, "dispersao": null, "atributos_efetivos": 1.00,
         "n_atributos": 1, "ha_direcao": true, "categoria_usada": "(todas)",
         "unidade": "z", "atributos": [
          {"termo_id":"jeans","rotulo":"Jeans","dimensao":"tecido","papel":"atributo",
           "indice":-0.46,"estado":"estavel","semana":"2026-07-27","pernas":["busca"],
           "peso":1.7,"peso_relativo":1.0,"pecas_no_painel":5696,
           "pct_na_dimensao":22.5,"fora_por":null}]}
        """
        let r = try decodificar(json)
        XCTAssertTrue(Cluster.manchete(r).contains("Com um atributo só"),
                      "um atributo não é conjunto, e a tela tem de dizer isso")
    }

    func testSemAtributosNaoInventaNumero() throws {
        let json = """
        {"indice": null, "dispersao": null, "atributos_efetivos": null,
         "n_atributos": 0, "ha_direcao": false, "categoria_usada": "(todas)",
         "unidade": "z", "atributos": []}
        """
        let r = try decodificar(json)
        XCTAssertEqual(Cluster.manchete(r), "Não há número do conjunto para esta peça.")
        XCTAssertNil(Cluster.explicacao(r))
    }

    // MARK: Auditoria dos pesos (regra 3)

    func testCadaAtributoDizQuantoPesouEPorQue() throws {
        let r = try decodificar(jsonDiscordante)
        let vestido = try XCTUnwrap(r.atributos.first { $0.termoId == "vestido" })
        let linha = try XCTUnwrap(Cluster.porQuePesa(vestido))
        XCTAssertTrue(linha.contains("22% do peso"), linha)
        XCTAssertTrue(linha.contains("11.579"),
                      "o N do painel tem de sair com separador de milhar: \(linha)")
    }

    /// `vestido` é 100% do próprio denominador quando condicionamos à categoria
    /// `vestido` — então ele pesa MENOS que `floral`. É o "vestido pesa pouco"
    /// da §22, obtido pelo condicionamento e não pelo IDF global.
    func testCategoriaCondicionadaRebaixaOProprioTermoDeCategoria() throws {
        let r = try decodificar(jsonDiscordante)
        let vestido = try XCTUnwrap(r.atributos.first { $0.termoId == "vestido" })
        let floral = try XCTUnwrap(r.atributos.first { $0.termoId == "floral" })
        XCTAssertLessThan(try XCTUnwrap(vestido.peso), try XCTUnwrap(floral.peso))
    }

    func testDenominadorDeclaraQueNaoTemRaridadePropria() throws {
        let json = """
        {"indice": -1.33, "dispersao": null, "atributos_efetivos": 1.63,
         "n_atributos": 2, "ha_direcao": true, "categoria_usada": "vestido",
         "unidade": "z", "atributos": [
          {"termo_id":"liso","rotulo":"Liso","dimensao":"estampa",
           "papel":"denominador","indice":-0.71,"estado":null,
           "semana":"2026-07-27","pernas":["busca"],
           "peso":1.9723,"peso_relativo":0.74,"pecas_no_painel":61,
           "pct_na_dimensao":null,"fora_por":null}]}
        """
        let r = try decodificar(json)
        let liso = try XCTUnwrap(r.atributos.first { $0.termoId == "liso" })
        let linha = try XCTUnwrap(Cluster.porQuePesa(liso))
        XCTAssertTrue(linha.contains("não tem raridade própria"), linha)
        XCTAssertFalse(linha.contains("das peças com essa dimensão"),
                       "denominador não pode anunciar uma fatia que não é medição")
    }

    // MARK: Concentração (Kish)

    func testAvisaQuandoUmAtributoCarregaQuaseTudo() throws {
        let json = """
        {"indice": 1.5, "dispersao": 0.1, "atributos_efetivos": 1.2,
         "n_atributos": 3, "ha_direcao": true, "categoria_usada": "vestido",
         "unidade": "z", "atributos": []}
        """
        let r = try decodificar(json)
        let c = try XCTUnwrap(Cluster.concentracao(r))
        XCTAssertTrue(c.contains("1,2"), c)
    }

    func testNaoAvisaQuandoOsPesosSaoParelhos() throws {
        let r = try decodificar(jsonDiscordante)   // 2,83 de 3
        XCTAssertNil(Cluster.concentracao(r),
                     "aviso de concentração com pesos parelhos é ruído")
    }

    // MARK: Ressalvas

    func testAvisaQuandoOsAtributosSaoDeSemanasDiferentes() throws {
        let r = try decodificar(jsonDiscordante)   // 13/07 e 27/07
        let s = try XCTUnwrap(Cluster.ressalvaDeSemana(r))
        XCTAssertTrue(s.contains("13/07/2026"), s)
        XCTAssertTrue(s.contains("27/07/2026"), s)
    }

    func testFicaCaladoQuandoTodosSaoDaMesmaSemana() throws {
        let json = """
        {"indice": 1.0, "dispersao": 0.1, "atributos_efetivos": 2.0,
         "n_atributos": 2, "ha_direcao": true, "categoria_usada": "saia",
         "unidade": "z", "atributos": [
          {"termo_id":"a","rotulo":"A","dimensao":"cor","papel":"atributo",
           "indice":1.0,"estado":null,"semana":"2026-07-27","pernas":["busca"],
           "peso":2.0,"peso_relativo":0.5,"pecas_no_painel":10,
           "pct_na_dimensao":10.0,"fora_por":null},
          {"termo_id":"b","rotulo":"B","dimensao":"cor","papel":"atributo",
           "indice":1.0,"estado":null,"semana":"2026-07-27","pernas":["busca"],
           "peso":2.0,"peso_relativo":0.5,"pecas_no_painel":10,
           "pct_na_dimensao":10.0,"fora_por":null}]}
        """
        XCTAssertNil(Cluster.ressalvaDeSemana(try decodificar(json)))
    }

    // MARK: Regra 6 — o que ficou de fora

    func testOQueFicouDeForaApareceComMotivo() throws {
        let json = """
        {"indice": 1.0, "dispersao": null, "atributos_efetivos": 1.0,
         "n_atributos": 1, "ha_direcao": true, "categoria_usada": "vestido",
         "unidade": "z", "atributos": [
          {"termo_id":"a","rotulo":"A","dimensao":"cor","papel":"atributo",
           "indice":1.0,"estado":null,"semana":"2026-07-27","pernas":["busca"],
           "peso":2.0,"peso_relativo":1.0,"pecas_no_painel":10,
           "pct_na_dimensao":10.0,"fora_por":null},
          {"termo_id":"b","rotulo":"B","dimensao":"estampa","papel":"atributo",
           "indice":null,"estado":null,"semana":null,"pernas":null,
           "peso":2.0,"peso_relativo":null,"pecas_no_painel":10,
           "pct_na_dimensao":10.0,"fora_por":"sem leitura neste recorte"}]}
        """
        let r = try decodificar(json)
        XCTAssertEqual(Cluster.dentro(r).count, 1)
        let fora = Cluster.deFora(r)
        XCTAssertEqual(fora.count, 1)
        XCTAssertEqual(fora.first?.foraPor, "sem leitura neste recorte")
    }

    // MARK: A fronteira da §5

    /// Um número único por peça é o lugar mais fácil do app para virar score.
    /// Este teste varre TODO o texto que o bloco produz.
    func testNenhumTextoDoClusterSugerePrevisaoOuVeredito() throws {
        let r = try decodificar(jsonDiscordante)
        var textos = [Cluster.manchete(r), Cluster.criterioDaRaridade(r)]
        textos.append(contentsOf: [Cluster.explicacao(r),
                                   Cluster.concentracao(r),
                                   Cluster.ressalvaDeSemana(r)].compactMap { $0 })
        textos.append(contentsOf: r.atributos.compactMap { Cluster.porQuePesa($0) })

        let proibidas = ["vai vender", "vão vender", "probabilidade", "previsão",
                         "chance", "sucesso", "score", "nota", "recomendo",
                         "aposte", "produza", "potencial"]
        for texto in textos {
            let t = texto.lowercased()
            for p in proibidas {
                XCTAssertFalse(t.contains(p),
                               "§5: \"\(p)\" apareceu em \"\(texto)\"")
            }
        }
    }

    /// Pontuação. Trivial, e por isso mesmo escapou dos testes e apareceu na
    /// tela: a explicação saía terminada em "para que lado..", porque a frase
    /// já trazia ponto e o `joined` acrescentava outro. Teste de família, não
    /// de caso: vale para todo texto que este arquivo produz.
    func testNenhumTextoTemPontuacaoDuplicada() throws {
        let r = try decodificar(jsonDiscordante)
        var textos = [Cluster.manchete(r), Cluster.criterioDaRaridade(r)]
        textos.append(contentsOf: [Cluster.explicacao(r),
                                   Cluster.concentracao(r),
                                   Cluster.ressalvaDeSemana(r)].compactMap { $0 })
        textos.append(contentsOf: r.atributos.compactMap { Cluster.porQuePesa($0) })
        for t in textos {
            XCTAssertFalse(t.contains(".."), "pontuação duplicada em \"\(t)\"")
            XCTAssertFalse(t.contains(" ,"), "vírgula solta em \"\(t)\"")
            XCTAssertFalse(t.contains("  "), "espaço duplo em \"\(t)\"")
        }
    }

    /// O critério tem de ser explicável em uma frase — regra 3, caminho até a
    /// origem. E tem de dizer QUAL recorte, porque a raridade muda com ele.
    func testOCriterioDaRaridadeDizOndeAConteFoiFeita() throws {
        let r = try decodificar(jsonDiscordante)
        let c = Cluster.criterioDaRaridade(r)
        XCTAssertTrue(c.contains("peças de vestido"), c)
        XCTAssertTrue(c.contains("dentro da própria dimensão"), c)
    }

    func testSemCategoriaUnicaOCriterioAvisaQueUsouOPainelInteiro() throws {
        let json = """
        {"indice": -0.9, "dispersao": 1.1, "atributos_efetivos": 2.88,
         "n_atributos": 3, "ha_direcao": false, "categoria_usada": "(todas)",
         "unidade": "z", "atributos": []}
        """
        let c = Cluster.criterioDaRaridade(try decodificar(json))
        XCTAssertTrue(c.contains("painel inteiro"), c)
        XCTAssertTrue(c.contains("não há uma categoria única"), c)
    }
}
