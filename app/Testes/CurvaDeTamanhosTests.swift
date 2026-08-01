import XCTest
@testable import CanarioLogica

/// Testes da leitura da curva de tamanhos (§24).
///
/// Os números usados são os MEDIDOS no painel em 01/08/2026, escada de letra.
/// Servem a dois propósitos: travar o texto que a tela produz, e deixar
/// registrado no código o que o painel dizia quando o método foi escrito.
final class CurvaDeTamanhosTests: XCTestCase {

    private func faixa(_ rotulo: String?, _ faixa: String,
                       emRisco: Int, quebrou: Int, taxa: Double?) -> CurvaDeTamanhos.Faixa {
        CurvaDeTamanhos.Faixa(
            termoId: nil, semana: "2026-07-27", sistema: "letra", faixa: faixa,
            rotulo: rotulo, nGrades: 37183, nEmRisco: emRisco, nQuebrou: quebrou,
            taxaQuebra: taxa, shareIndisponivel: nil)
    }

    /// O painel real de 01/08/2026.
    private var painel: [CurvaDeTamanhos.Faixa] {
        [faixa("PP", "menores", emRisco: 9284,  quebrou: 218, taxa: 2.35),
         faixa("P",  "menores", emRisco: 11135, quebrou: 398, taxa: 3.57),
         faixa("M",  "meio",    emRisco: 9540,  quebrou: 311, taxa: 3.26),
         faixa("G",  "maiores", emRisco: 11059, quebrou: 296, taxa: 2.68),
         faixa("GG", "maiores", emRisco: 8738,  quebrou: 189, taxa: 2.16)]
    }

    // MARK: Consolidação — o defeito que a tela mostrou

    func testMesmoRotuloEmFaixasDiferentesViraUmaLinhaSo() {
        // O banco guarda por (faixa, rótulo), e `M` cai em faixas diferentes
        // conforme o formato da grade: meio numa de cinco degraus, maiores numa
        // que vai de PP a M, menores numa que vai de M a XGG. A tela mostrava
        // `M` três vezes e `P` duas.
        let cru = [faixa("M", "meio",    emRisco: 9540, quebrou: 311, taxa: 3.26),
                   faixa("M", "menores", emRisco: 727,  quebrou: 31,  taxa: 4.26),
                   faixa("M", "maiores", emRisco: 604,  quebrou: 20,  taxa: 3.31)]
        let junto = CurvaDeTamanhos.consolidar(cru)
        XCTAssertEqual(junto.count, 1)
        XCTAssertEqual(junto[0].nEmRisco, 10871)
        XCTAssertEqual(junto[0].nQuebrou, 362)
        // Ponderada pelo risco, não média das taxas: 362/10871 = 3,33%.
        XCTAssertEqual(junto[0].taxaQuebra!, 3.33, accuracy: 0.01)
    }

    func testTaxaConsolidadaNaoEhMediaDasTaxas() {
        // Média simples de 3,26 / 4,26 / 3,31 daria 3,61 — peso igual para uma
        // linha de 604 e uma de 9.540.
        let cru = [faixa("M", "meio",    emRisco: 9540, quebrou: 311, taxa: 3.26),
                   faixa("M", "menores", emRisco: 727,  quebrou: 31,  taxa: 4.26),
                   faixa("M", "maiores", emRisco: 604,  quebrou: 20,  taxa: 3.31)]
        let taxa = CurvaDeTamanhos.consolidar(cru)[0].taxaQuebra!
        XCTAssertLessThan(taxa, 3.5, "média das taxas daria 3,61 e superestimaria o M")
    }

    func testTamanhoDeAmostraMinusculaNaoEntra() {
        // A tela elegeu como piso um `P` com QUATRO tamanhos em risco e 0,0%,
        // e isso zerou a manchete inteira. Amostra pequena produz taxa extrema.
        let cru = [faixa("P", "meio",    emRisco: 4,     quebrou: 0,   taxa: 0.0),
                   faixa("G", "maiores", emRisco: 1,     quebrou: 0,   taxa: 0.0),
                   faixa("PP", "menores", emRisco: 9284, quebrou: 218, taxa: 2.35)]
        let junto = CurvaDeTamanhos.consolidar(cru)
        XCTAssertEqual(junto.compactMap(\.rotulo), ["PP"])
    }

    // MARK: A manchete nomeia o tamanho, e isso não é estilo

    func testMancheteNomeiaOTamanhoDePico() {
        let frase = CurvaDeTamanhos.manchete(porRotulo: painel)
        XCTAssertNotNil(frase)
        XCTAssertTrue(frase!.contains("tamanho P é"),
                      "o pico do painel é P, e é ele que tem de ser nomeado")
        XCTAssertTrue(frase!.contains("3,6%"))
        XCTAssertTrue(frase!.contains("2,2%"), "o vale entra junto, senão a taxa não tem contra o quê")
    }

    func testMancheteNaoDizQueOsMenoresQuebramMais() {
        // A armadilha desta tela. No painel, PP é o SEGUNDO que menos quebra
        // (2,35%), atrás só do GG. Um comprador que lesse "os menores quebram
        // mais" e reforçasse PP estaria agindo sobre uma leitura errada.
        let frase = CurvaDeTamanhos.manchete(porRotulo: painel) ?? ""
        XCTAssertFalse(frase.lowercased().contains("menores"),
                       "a manchete tem de nomear o tamanho, não generalizar a ponta da grade")
    }

    func testMancheteExigeTresTamanhos() {
        let magro = Array(painel.prefix(2))
        XCTAssertNil(CurvaDeTamanhos.manchete(porRotulo: magro),
                     "com dois tamanhos não há curva, há um par")
    }

    // MARK: Formato da quebra

    func testFormatoPendeParaOsMenores() {
        let menores = faixa(nil, "menores", emRisco: 26200, quebrou: 816, taxa: 3.11)
        let maiores = faixa(nil, "maiores", emRisco: 24276, quebrou: 641, taxa: 2.64)
        let frase = CurvaDeTamanhos.formato(menores: menores, maiores: maiores)
        XCTAssertNotNil(frase)
        XCTAssertTrue(frase!.contains("menores"))
        XCTAssertTrue(frase!.contains("1,18"))
    }

    func testFormatoDeclaraEmpateEmVezDeInventarDirecao() {
        let menores = faixa(nil, "menores", emRisco: 1000, quebrou: 30, taxa: 3.00)
        let maiores = faixa(nil, "maiores", emRisco: 1000, quebrou: 29, taxa: 2.90)
        let frase = CurvaDeTamanhos.formato(menores: menores, maiores: maiores) ?? ""
        XCTAssertTrue(frase.contains("ritmo parecido"),
                      "diferença de 3% não é formato; declarar empate é a leitura honesta")
    }

    func testFormatoInverteQuandoOsMaioresSaemMais() {
        let menores = faixa(nil, "menores", emRisco: 1000, quebrou: 20, taxa: 2.0)
        let maiores = faixa(nil, "maiores", emRisco: 1000, quebrou: 40, taxa: 4.0)
        let frase = CurvaDeTamanhos.formato(menores: menores, maiores: maiores) ?? ""
        XCTAssertTrue(frase.contains("maiores"))
        XCTAssertTrue(frase.contains("2,00"))
    }

    // MARK: A fronteira da regra 1

    func testComposicaoFalaDeProporcaoENuncaDeVolume() {
        let frase = CurvaDeTamanhos.composicao(porRotulo: painel) ?? ""
        XCTAssertFalse(frase.isEmpty)
        // §24 autoriza composição de grade (soma zero) e proíbe volume.
        XCTAssertTrue(frase.contains("sem mexer no total de peças"),
                      "a soma zero é o que mantém a frase do lado permitido")
        XCTAssertTrue(frase.contains("deslocar participação"))
        for proibido in ["compre", "produza", "aumente a quantidade", "peças a mais"] {
            XCTAssertFalse(frase.lowercased().contains(proibido),
                           "recomendação de volume é proibida pela regra 1: \(proibido)")
        }
    }

    func testComposicaoEhCondicional() {
        let frase = CurvaDeTamanhos.composicao(porRotulo: painel) ?? ""
        XCTAssertTrue(frase.hasPrefix("Se a sua grade"),
                      "§24 exige linguagem condicional: o público do usuário não é o do painel")
        XCTAssertTrue(frase.contains("seu custo"))
    }

    func testRessalvasCarregamOConfundidorDeProfundidade() {
        let todas = CurvaDeTamanhos.ressalvas.joined(separator: " ").lowercased()
        XCTAssertTrue(todas.contains("não vemos quantidade em estoque"),
                      "sem esta ressalva a taxa parece medir demanda, e ela mede saída do ar")
        XCTAssertTrue(todas.contains("público médio do painel"),
                      "ressalva obrigatória da §24")
        XCTAssertTrue(todas.contains("não é venda"))
    }

    // MARK: Ordem da escada

    func testOrdemDaEscadaVaiDoMenorAoMaior() {
        let ordenado = CurvaDeTamanhos.emOrdem(painel).compactMap(\.rotulo)
        XCTAssertEqual(ordenado, ["PP", "P", "M", "G", "GG"])
    }

    func testOrdemFuncionaNaEscadaNumerica() {
        let numerica = [faixa("42", "maiores", emRisco: 100, quebrou: 3, taxa: 3),
                        faixa("36", "menores", emRisco: 100, quebrou: 5, taxa: 5),
                        faixa("38", "meio", emRisco: 100, quebrou: 4, taxa: 4)]
        XCTAssertEqual(CurvaDeTamanhos.emOrdem(numerica).compactMap(\.rotulo),
                       ["36", "38", "42"])
    }

    // MARK: Cobertura

    func testInsumoDeclaraOQueSustentaONumero() {
        let texto = CurvaDeTamanhos.insumo(painel)
        XCTAssertTrue(texto.contains("49756 tamanhos em risco"))
        XCTAssertTrue(texto.contains("27/07/2026"), "data em dd/mm/aaaa, como todo o resto")
        XCTAssertTrue(texto.contains("14 dias"))
    }

    func testMinimoDeCoberturaExiste() {
        // §8 aplicada à curva. O número é de tamanhos em risco, não de peças.
        XCTAssertEqual(CurvaDeTamanhos.minimoEmRisco, 300)
    }
}
