import XCTest
@testable import CanarioLogica

/// Testes do bloco de reclamações que o JP abriu em 31/07.
///
/// Cada teste aqui nasce de uma frase dele, e a frase está no comentário. É
/// proposital: quando um destes quebrar daqui a um mês, o próximo a ler precisa
/// saber que comportamento estava sendo protegido, e não só qual asserção caiu.
final class BlocoDeReclamacoesTests: XCTestCase {
    func testLeituraUsadaComoTituloComecaComMaiuscula() {
        XCTAssertEqual(Leitura.comoTitulo(1.78), "Above the usual range")
        XCTAssertEqual(Leitura.comoTitulo(-2.1), "Far below the usual range")
    }

    private func termo(_ id: String, _ rotulo: String, _ dimensao: String,
                       _ sinonimos: String? = nil, _ palavrasPt: String? = nil) -> Termo {
        Termo(id: id, rotulo: rotulo, dimensao: dimensao, exclusiva: true,
              sinonimos: sinonimos, semPernaBusca: nil,
              palavrasPt: palavrasPt, palavrasEn: nil)
    }

    private var taxonomiaMinima: [Termo] {
        [termo("vestido", "Vestido", "categoria", "vestidinho", "vestido|vestidinho"),
         termo("geometrica", "Geometrica e etnica", "estampa",
               "poa|bolinha|abstrata|etnica",
               "geometrica|geometrico|poa|bolinha|bolinhas|abstrata|etnica"),
         termo("cinza", "Cinza", "cor", "grafite|chumbo|mescla", "cinza|grafite|chumbo|mescla"),
         termo("branco_cru", "Branco e cru", "cor", "off white|areia", "branco|branca|off white|cru|areia"),
         termo("preto", "Preto", "cor", nil, "preto|preta"),
         termo("blusa_top", "Blusa e top", "categoria", "cropped|regata", "blusa|top|cropped|regata"),
         termo("reta_wide", "Reta e wide", "silhueta", "wide leg", "reta|reto|wide leg")]
    }

    // MARK: "Pesquisei vestido de bolinha e tudo que apareceu foi vestido"

    func testBolinhaEncontraAEstampa() {
        let achados = Traducao.termos(para: "vestido de bolinha", em: taxonomiaMinima)
        let ids = Set(achados.map(\.id))
        XCTAssertTrue(ids.contains("vestido"))
        XCTAssertTrue(ids.contains("geometrica"),
                      "a taxonomia tinha 'poá', que é o nome técnico, e não 'bolinha', que é o nome que o comprador usa")
    }

    func testDuasDimensoesDescrevemUmaPeca() {
        // A regra que a tela usa para oferecer a leitura do conjunto em vez de
        // uma lista de atributos soltos.
        let peca = Traducao.termos(para: "vestido de bolinha", em: taxonomiaMinima)
        XCTAssertGreaterThanOrEqual(Set(peca.map(\.dimensao)).count, 2)

        let atributoSozinho = Traducao.termos(para: "bolinha", em: taxonomiaMinima)
        XCTAssertEqual(Set(atributoSozinho.map(\.dimensao)).count, 1,
                       "um atributo isolado continua sendo um atributo, não uma peça")
    }

    func testPoaContinuaFuncionando() {
        // Acrescentar vocabulário não pode custar o que já existia: `poá` é o
        // que aparece nos títulos do catálogo ("VESTIDO CURTO POÁ P&B").
        let achados = Traducao.termos(para: "vestido curto poa p&b", em: taxonomiaMinima)
        XCTAssertTrue(Set(achados.map(\.id)).contains("geometrica"))
    }

    func testRetaNaoCasaPretaNoCaminhoDaBusca() {
        // A regressão de sempre, agora cruzando o caminho novo.
        let achados = Traducao.termos(para: "vestido preta de bolinha", em: taxonomiaMinima)
        let ids = Set(achados.map(\.id))
        XCTAssertTrue(ids.contains("preto"))
        XCTAssertFalse(ids.contains("reta_wide"), "'preta' não pode virar silhueta reta")
    }

    // MARK: "A leitura da imagem que enviei em formato de PDF não foi feita"

    func testCorDoPixelViraAtributoQuandoNaoHaTexto() {
        // Os valores de RGB são os MEDIDOS na foto que o JP mandou: uma malha
        // cinza mescla da Hering, em PDF sem uma letra dentro.
        let leituraDaCor = CorDaPeca.Leitura(termoId: CorDaPeca.termo(paraRGB: [0.72, 0.73, 0.72]),
                                             rgb: [0.72, 0.73, 0.72], cobertura: 0.94)
        let arquivo = LeitorDeArquivo.Leitura(texto: "", cor: leituraDaCor, origem: .somenteCor)
        let achado = Importacao.atributos(de: arquivo, em: taxonomiaMinima)

        XCTAssertEqual(achado.marcados, ["cinza"],
                       "arquivo sem texto tem de sair do formulário com pelo menos a cor marcada")
        XCTAssertTrue(achado.procedencia.contains { $0.contains("image color") },
                      "a procedência precisa dizer que a cor veio do pixel, que é a marcação mais frágil")
    }

    func testTextoGanhaDoPixelQuandoOsDoisFalamDeCor() {
        // O título diz off white; o pixel, sob luz de estúdio, mede cinza.
        // Marcar as duas cores poria uma contradição na cara do usuário.
        let cor = CorDaPeca.Leitura(termoId: "cinza", rgb: [0.72, 0.73, 0.72], cobertura: 0.9)
        let arquivo = LeitorDeArquivo.Leitura(texto: "Blusa off white", cor: cor, origem: .ocr)
        let achado = Importacao.atributos(de: arquivo, em: taxonomiaMinima)

        XCTAssertTrue(achado.marcados.contains("branco_cru"))
        XCTAssertFalse(achado.marcados.contains("cinza"),
                       "a cor declarada no título vale mais que a cor capturada na foto")
    }

    // MARK: Calibração da cor, com os valores que foram realmente medidos

    func testCoresMedidasEmFotosReais() {
        // Cada caso é uma foto que passou pelo extrator, com a cor conhecida
        // pelo título do produto. Amostra pequena e declarada como tal — a
        // calibração definitiva sai do catálogo, quando o runner residencial
        // puder baixar as imagens.
        let casos: [(String, [Double], String)] = [
            ("malha cinza mescla (foto do JP)", [0.72, 0.73, 0.72], "cinza"),
            ("regata off white",                [0.94, 0.94, 0.93], "branco_cru"),
            ("suéter off white",                [0.94, 0.92, 0.90], "branco_cru"),
            ("blusa preta",                     [0.07, 0.06, 0.05], "preto"),
            ("camisa rosa",                     [0.94, 0.68, 0.72], "vermelho_rosa"),
        ]
        for (nome, rgb, esperado) in casos {
            XCTAssertEqual(CorDaPeca.termo(paraRGB: rgb), esperado, "\(nome)")
        }
    }

    func testOffWhiteNaoEhLidoComoAmarelo() {
        // O erro real, e ele apareceu duas vezes por dois motivos diferentes.
        //
        // Na primeira versão, o corte de saturação em 0,12 deixava um suéter off
        // white passar por colorido. Subi o corte para 0,22 e o suéter passou —
        // mas só porque eu estava olhando o RGB arredondado. Com o valor cheio,
        // a saturação HSL do off white é 0,25, e ele voltou a sair amarelo.
        //
        // A causa é estrutural: perto do branco, o denominador da saturação HSL
        // tende a zero e o número perde sentido. Quem decide agora é o croma.
        XCTAssertEqual(CorDaPeca.termo(paraRGB: [0.94, 0.92, 0.90]), "branco_cru")
        XCTAssertEqual(CorDaPeca.termo(paraRGB: [0.94, 0.94, 0.93]), "branco_cru")
    }

    func testPeleEhDescartada() {
        // Sem isto, o braço da modelo puxa toda peça clara para "terrosos".
        XCTAssertTrue(CorDaPeca.ehPele(0.85, 0.68, 0.55))
        XCTAssertTrue(CorDaPeca.ehPele(0.55, 0.42, 0.34))
        XCTAssertFalse(CorDaPeca.ehPele(0.72, 0.73, 0.72), "cinza mescla não é pele")
        XCTAssertFalse(CorDaPeca.ehPele(0.07, 0.06, 0.05), "preto não é pele")
    }

    func testTransparenciaDoRecorteNaoViraRoupaPreta() throws {
        // Três quartos do PNG não têm fundo; o quarto opaco é uma roupa azul.
        // A implementação antiga incluía RGB 0/0/0 dos pixels transparentes e
        // devolvia preto, exatamente o viés observado pelo JP no device.
        let transparente: [UInt8] = [0, 0, 0, 0]
        let azul: [UInt8] = [30, 80, 210, 255]
        let bytes = Array(repeating: transparente, count: 3).flatMap { $0 } + azul
        let amostra = try XCTUnwrap(
            CorDaPeca.medianaRGBA(bytes, numeroDePixels: 4))
        XCTAssertEqual(amostra.cobertura, 0.25, accuracy: 0.0001)
        XCTAssertEqual(CorDaPeca.termo(paraRGB: amostra.rgb), "azul")
    }

    // MARK: O número continua rastreável sem protagonizar o jargão

    func testNumeroTemEscalaDeclaradaNaLinhaDeApoio() {
        XCTAssertEqual(Explicacao.numeroComUnidade(1.15), "+1,15")
        XCTAssertEqual(Explicacao.numeroComUnidade(-3.73), "-3,73")
        XCTAssertEqual(Explicacao.numeroComUnidade(nil), "no index")
        XCTAssertTrue(Explicacao.unidadeDoIndice.contains("12 weeks"),
                      "a linha de apoio tem de dizer contra o que a escala é medida")
    }

    func testNumeroUsaVirgulaDecimal() {
        // Mesma família da regra de data em dd/mm/aaaa: a tela mostrava
        // "-2.18" e "2.2 desvios", que é notação de código, não de português.
        XCTAssertEqual(Leitura.numero(-2.18, casas: 2), "-2,18")
        XCTAssertEqual(Leitura.numero(1.15, casas: 2, sinal: true), "+1,15")
        XCTAssertEqual(Leitura.numero(11.9485, casas: 1), "11,9")
        XCTAssertTrue(Leitura.explicacao(-2.18).contains("below this attribute's usual behavior"))
    }

    /// Visto em aparelho em 19/08/2026: o selo dizia "within the usual range" e
    /// a linha logo abaixo dizia "0,0 on the statistical scale, **above** this
    /// attribute's usual behavior". Duas frases sobre o mesmo número, uma
    /// contradizendo a outra.
    ///
    /// A causa era a direção sair do valor BRUTO (`z >= 0`) enquanto o número
    /// mostrado é o arredondado. Um z de 0,04 exibe 0,0 e não sustenta direção
    /// nenhuma — afirmar "acima" ali é afirmar mais do que o dado permite.
    func testNumeroQueExibeZeroNaoAfirmaDirecao() {
        for z in [0.0, 0.04, -0.04, 0.049, -0.049] {
            let texto = Leitura.explicacao(z)
            XCTAssertTrue(texto.contains("0,0 on the statistical scale"),
                          "esperava exibir 0,0 para z=\(z): \(texto)")
            XCTAssertTrue(texto.contains("level with"),
                          "z=\(z) exibe 0,0 e não pode afirmar direção: \(texto)")
            XCTAssertFalse(texto.contains("above"), "z=\(z): \(texto)")
            XCTAssertFalse(texto.contains("below"), "z=\(z): \(texto)")
        }
    }

    /// E o que tem direção continua dizendo a direção, dos dois lados.
    func testNumeroComDirecaoContinuaDizendoOLado() {
        XCTAssertTrue(Leitura.explicacao(0.6).contains("above"))
        XCTAssertTrue(Leitura.explicacao(-0.6).contains("below"))
        // 0,05 arredonda para 0,1: já sustenta direção.
        XCTAssertTrue(Leitura.explicacao(0.05).contains("above"))
    }

    func testCadaPernaTemUnidadePropria() {
        XCTAssertTrue(Explicacao.unidade(daFonte: "editorial_br").contains("articles"))
        XCTAssertTrue(Explicacao.unidade(daFonte: "varejo").contains("%"))
        XCTAssertTrue(Explicacao.unidade(daFonte: "busca").contains("Google Trends"))
    }

    // MARK: "Por que isso é considerado pico? Não é pra mim, é pro usuário"

    private func indice(_ estado: String?, nPernas: Int = 2) -> IndiceSemanal {
        IndiceSemanal(id: 1, termoId: "preto", segmento: "feminino_casual_br",
                      semana: "2026-07-27", indice: 1.15, estado: estado,
                      pernasAtivas: ["editorial_br", "editorial_intl"], nPernas: nPernas,
                      meta: .init(indiceSemanaAnterior: 0.2, pernasAcimaDe1: 1, pernasAbaixoDe1: 0),
                      computadoEm: nil)
    }

    private func serieEditorial(z: Double) -> PontoSerie {
        PontoSerie(id: 1, termoId: "preto", fonte: "editorial_br", semana: "2026-07-27",
                   valorBruto: 2.25, z: z, nAmostra: 9,
                   meta: .init(unidade: "materias que citaram o termo",
                               veiculos: ["Elle Brasil": 4, "Vogue Brasil": 2],
                               exemplos: nil, contagemSemanaCrua: 7,
                               metrica: nil, nTotalSortimento: nil))
    }

    func testPicoExplicaQueNenhumaOutraFonteAcompanhou() {
        let texto = Explicacao.porQue(estado: "pico", indice: indice("pico"),
                                      series: [serieEditorial(z: 3.98)])
        XCTAssertTrue(texto.contains("3,9") || texto.contains("4,0"),
                      "o desvio do editorial tem de aparecer no texto")
        XCTAssertTrue(texto.lowercased().contains("no other source"),
                      "é a condição que separa pico de alta, e o usuário precisa dela para decidir se segue")
    }

    func testEstadoAusenteDizQuantasPernasFaltam() {
        let texto = Explicacao.porQue(estado: nil, indice: indice(nil, nPernas: 1), series: [])
        XCTAssertTrue(texto.contains("Two sources"))
        XCTAssertTrue(texto.contains("1"), "dizer quantas pernas há hoje é o que torna a recusa verificável")
    }

    func testEstavelEhResultadoMedidoENaoFaltaDeDado() {
        let texto = Explicacao.porQue(estado: "estavel", indice: indice("estavel"), series: [])
        XCTAssertTrue(texto.lowercased().contains("measured result"))
    }

    // MARK: "Quero o nome dos sites que fizeram o bot chegar a essa conclusão"

    func testOrigemNomeiaOsVeiculos() {
        let linhas = Explicacao.origens([serieEditorial(z: 3.98)])
        XCTAssertEqual(linhas.count, 1)
        XCTAssertTrue(linhas[0].contains("Elle Brasil (4)"))
        XCTAssertTrue(linhas[0].contains("Vogue Brasil (2)"))
        XCTAssertTrue(linhas[0].contains("9 published articles"), "a contagem vem com a unidade colada")
    }

    func testBuscaNaoHerdaAJanelaDoEditorial() {
        // Só a perna editorial trabalha em janela de 4 semanas (§18). A linha
        // da busca vinha dizendo "— índice de interesse do Google Trends em 4
        // semanas", que cola a janela de uma perna no número de outra e ainda
        // exibe um travessão no lugar do valor.
        let busca = PontoSerie(id: 3, termoId: "azul", fonte: "busca", semana: "2026-06-08",
                               valorBruto: 62, z: -1.2, nAmostra: nil, meta: nil)
        let linha = Explicacao.origens([busca])[0]
        XCTAssertTrue(linha.contains("62 out of 100"))
        XCTAssertFalse(linha.contains("4 weeks"))
        XCTAssertFalse(linha.contains("—"), "não pode sair travessão onde há valor")
    }

    func testVarejoMostraShareENumeroDePecas() {
        let varejo = PontoSerie(id: 2, termoId: "preto", fonte: "varejo", semana: "2026-07-27",
                                valorBruto: 11.9485, z: nil, nAmostra: 7217,
                                meta: .init(unidade: nil, veiculos: nil, exemplos: nil,
                                            contagemSemanaCrua: nil,
                                            metrica: "share do atributo no sortimento do painel (%)",
                                            nTotalSortimento: 60401))
        let linhas = Explicacao.origens([varejo])
        XCTAssertTrue(linhas[0].contains("11,9%"))
        XCTAssertTrue(linhas[0].contains("7217 panel items"))
    }

    // MARK: "*3ª reposição dos tamanhos PP/P em menos de 2 meses"

    private func evento(ordinal: Int?, dias: Int?, tamanhos: [String]?) -> EventoVarejo {
        EventoVarejo(id: 1, tipo: "reposicao", data: "2026-07-30", semana: "2026-07-27",
                     marca: "PatBo", peca: "Vestido longo", urlDaPeca: nil,
                     imagem: nil,
                     detalhe: .init(tamanhos: tamanhos, quedaPct: nil, precoDe: nil, precoPara: nil),
                     ordinal: ordinal, diasDesdeAPrimeira: dias)
    }

    func testTerceiraReposicaoTrazTamanhoEPeriodo() {
        let frase = evento(ordinal: 3, dias: 54, tamanhos: ["PP", "P"])
            .repeticao(desde: "2026-07-24")
        XCTAssertEqual(frase, "3rd restock for size PP/P in under 2 months")
    }

    func testPrimeiraReposicaoVemAncoradaNaDataDeInicio() {
        // Dizer "1ª reposição" com oito dias de coleta afirmaria que nunca
        // houve outra antes — e isso não foi medido (regra 2).
        let frase = evento(ordinal: 1, dias: nil, tamanhos: ["M"])
            .repeticao(desde: "2026-07-24")
        XCTAssertEqual(frase, "First restock since 24/07/2026")
    }

    func testPeriodoEmLinguagemDeCompra() {
        XCTAssertEqual(Formato.periodo(dias: 3), "3 days")
        XCTAssertEqual(Formato.periodo(dias: 21), "3 weeks")
        XCTAssertEqual(Formato.periodo(dias: 54), "under 2 months")
        XCTAssertEqual(Formato.periodo(dias: 95), "under 4 months")
    }

    // MARK: Datas continuam em dd/mm/aaaa

    func testDataDoEventoNaoEscorregaUmDia() {
        XCTAssertEqual(Formato.data("2026-01-05"), "05/01/2026")
        XCTAssertEqual(Formato.data("2026-07-30"), "30/07/2026")
    }
}
