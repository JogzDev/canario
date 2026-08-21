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

    // MARK: A margem de erro, que a tela me obrigou a respeitar

    /// O painel depois da limpeza dos atributos (01/08, à tarde): M e P estão
    /// separados por um décimo de ponto, em onze mil amostras cada.
    private var painelComEmpate: [CurvaDeTamanhos.Faixa] {
        [faixa("PP", "menores", emRisco: 9392,  quebrou: 360, taxa: 3.83),
         faixa("P",  "menores", emRisco: 11327, quebrou: 597, taxa: 5.27),
         faixa("M",  "meio",    emRisco: 11058, quebrou: 598, taxa: 5.41),
         faixa("G",  "maiores", emRisco: 11279, quebrou: 458, taxa: 4.06),
         faixa("GG", "maiores", emRisco: 8915,  quebrou: 329, taxa: 3.69)]
    }

    func testDiferencaDentroDaMargemNaoEleceVencedor() {
        // A primeira versão declarava "o tamanho M é o que mais sai" com 5,4%
        // contra 5,3% do P. Dois erros-padrão da diferença somam ~0,6 ponto:
        // a diferença de 0,14 cabe inteira dentro do ruído.
        let m = painelComEmpate[2], p = painelComEmpate[1]
        XCTAssertTrue(CurvaDeTamanhos.empatados(m, p))

        let frase = CurvaDeTamanhos.manchete(porRotulo: painelComEmpate) ?? ""
        XCTAssertTrue(frase.contains("P and M") || frase.contains("M and P"),
                      "empate tem de nomear os dois, não coroar um")
        XCTAssertTrue(frase.contains("same pace"))
    }

    func testDiferencaRealContinuaSendoDeclarada() {
        let m = painelComEmpate[2], gg = painelComEmpate[4]
        XCTAssertFalse(CurvaDeTamanhos.empatados(m, gg),
                       "5,4% contra 3,7% é diferença de verdade, e some se a margem for frouxa")
    }

    // MARK: A manchete nomeia o tamanho, e isso não é estilo

    func testMancheteNomeiaOTamanhoDePico() {
        // Com o painel de 01/08 pela manhã, P (3,57%) e M (3,26%) também
        // empatam: a margem da diferença é 0,51 ponto e a distância é 0,31.
        //
        // Registrado assim de propósito. A manchete que escrevi de manhã dizia
        // "o tamanho P é o que mais sai de linha", e essa afirmação nunca se
        // sustentou — faltava a margem, não o dado. Quando ela entrou, o
        // próprio teste antigo quebrou e apontou o exagero.
        let frase = CurvaDeTamanhos.manchete(porRotulo: painel)
        XCTAssertNotNil(frase)
        XCTAssertTrue(frase!.contains("P and M") || frase!.contains("M and P"),
                      "P e M empatam dentro da margem; nomear só um exagera o achado")
        XCTAssertTrue(frase!.contains("2,2%"), "o vale entra junto, senão a taxa não tem contra o quê")
    }

    func testAsPontasDaGradeSaemMenos() {
        // O que o dado sustenta em TODAS as versões medidas até agora, e que é
        // o achado de verdade: PP e GG são os mais lentos da grade.
        for conjunto in [painel, painelComEmpate] {
            let ordenado = conjunto.sorted { ($0.taxaQuebra ?? 0) > ($1.taxaQuebra ?? 0) }
            let doisUltimos = Set(ordenado.suffix(2).compactMap(\.rotulo))
            XCTAssertEqual(doisUltimos, ["PP", "GG"],
                           "as pontas da grade são as mais lentas, e é isso que se pode afirmar")
        }
    }

    func testMancheteNaoDizQueOsMenoresQuebramMais() {
        // A armadilha desta tela. No painel, PP é o SEGUNDO que menos quebra,
        // atrás só do GG. Um comprador que lesse "os menores quebram mais" e
        // reforçasse PP estaria agindo sobre uma leitura errada.
        let frase = CurvaDeTamanhos.manchete(porRotulo: painel) ?? ""
        XCTAssertFalse(frase.lowercased().contains("smaller sizes"),
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
        XCTAssertTrue(frase!.contains("smaller sizes"))
        XCTAssertTrue(frase!.contains("1,18"))
    }

    func testFormatoDeclaraEmpateEmVezDeInventarDirecao() {
        let menores = faixa(nil, "menores", emRisco: 1000, quebrou: 30, taxa: 3.00)
        let maiores = faixa(nil, "maiores", emRisco: 1000, quebrou: 29, taxa: 2.90)
        let frase = CurvaDeTamanhos.formato(menores: menores, maiores: maiores) ?? ""
        XCTAssertTrue(frase.contains("similar pace"),
                      "diferença de 3% não é formato; declarar empate é a leitura honesta")
    }

    func testFormatoInverteQuandoOsMaioresSaemMais() {
        let menores = faixa(nil, "menores", emRisco: 1000, quebrou: 20, taxa: 2.0)
        let maiores = faixa(nil, "maiores", emRisco: 1000, quebrou: 40, taxa: 4.0)
        let frase = CurvaDeTamanhos.formato(menores: menores, maiores: maiores) ?? ""
        XCTAssertTrue(frase.contains("larger sizes"))
        XCTAssertTrue(frase.contains("2,00"))
    }

    func testRessalvasCarregamOConfundidorDeProfundidade() {
        let todas = CurvaDeTamanhos.ressalvas.joined(separator: " ").lowercased()
        XCTAssertTrue(todas.contains("inventory quantities are not visible"),
                      "sem esta ressalva a taxa parece medir demanda, e ela mede saída do ar")
        XCTAssertTrue(todas.contains("panel's average audience"),
                      "ressalva obrigatória da §24")
        XCTAssertTrue(todas.contains("not a sales measure"))
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
        XCTAssertTrue(texto.contains("49756 sizes at risk"))
        XCTAssertTrue(texto.contains("27/07/2026"), "data em dd/mm/aaaa, como todo o resto")
        XCTAssertTrue(texto.contains("14-day"))
    }

    func testMinimoDeCoberturaExiste() {
        // §8 aplicada à curva. O número é de tamanhos em risco, não de peças.
        XCTAssertEqual(CurvaDeTamanhos.minimoEmRisco, 300)
    }
}
