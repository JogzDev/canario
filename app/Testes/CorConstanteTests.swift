import XCTest
@testable import CanarioLogica

/// O portão que separa "cor não medida" de "cor medida e ruim".
///
/// A rota de cor constante do iOS 18 (`CapturaDeCorConstante`) é a primeira vez
/// que o app tem uma opinião do SISTEMA sobre a própria foto. Isso cria um
/// risco novo e silencioso: tratar `nil` como zero faria o app parar de sugerir
/// cor para toda foto de fototeca, arquivo e câmera comum — que é a esmagadora
/// maioria — sem nenhum erro na tela e sem ninguém entender por quê.
///
/// Estes testes existem para essa regressão não passar despercebida.
final class CorConstanteTests: XCTestCase {

    private let termos = [
        Termo(id: "vestido", rotulo: "Dress", dimensao: "categoria",
              exclusiva: true, sinonimos: nil, semPernaBusca: nil,
              palavrasPt: nil, palavrasEn: nil),
        Termo(id: "azul", rotulo: "Blue", dimensao: "cor",
              exclusiva: false, sinonimos: nil, semPernaBusca: nil,
              palavrasPt: nil, palavrasEn: nil),
    ]

    private func leitura(_ confianca: Double?) -> LeitorDeArquivo.Leitura {
        LeitorDeArquivo.Leitura(
            texto: "",
            cor: CorDaPeca.Leitura(termoId: "azul", rgb: [0.22, 0.42, 0.72],
                                   cobertura: 0.9, confiancaDaCaptura: confianca),
            origem: .somenteCor)
    }

    // MARK: - O comportamento de sempre continua

    /// Sem medida, o app sugere como sempre sugeriu. Esta é a rota de 99% das
    /// fotos e ela não pode ter mudado ao ganharmos a de cor constante.
    func testSemMedidaAContinuaSugerindoCor() {
        let cor = CorDaPeca.Leitura(termoId: "azul", rgb: [0.22, 0.42, 0.72],
                                    cobertura: 0.9)
        XCTAssertNil(cor.confiancaDaCaptura)
        XCTAssertTrue(cor.podeSugerirCor,
                      "confiança ausente não é confiança zero")

        let achado = Importacao.atributos(de: leitura(nil), em: termos)
        XCTAssertTrue(achado.marcados.contains("azul"))
    }

    /// `CorDaPeca.ler` sem o argumento novo tem de continuar produzindo uma
    /// leitura sem medida — o parâmetro é opcional justamente para nenhum
    /// chamador antigo passar a declarar uma confiança que não tem.
    func testOArgumentoNovoEhOpcionalEDefaultaParaNaoMedido() {
        let cor = CorDaPeca.Leitura(termoId: "cinza", rgb: [0.5, 0.5, 0.5],
                                    cobertura: 0.5)
        XCTAssertNil(cor.confiancaDaCaptura)
        XCTAssertTrue(cor.podeSugerirCor)
    }

    // MARK: - A medida baixa fecha o portão

    /// Medida e ruim: o app sabe que a luz enganou a foto. Regra inviolável 2 —
    /// lacuna vira ausência declarada, nunca um valor plausível pré-marcado.
    func testMedidaBaixaNaoPreMarcaACor() {
        let cor = CorDaPeca.Leitura(termoId: "azul", rgb: [0.22, 0.42, 0.72],
                                    cobertura: 0.9, confiancaDaCaptura: 0.2)
        XCTAssertFalse(cor.podeSugerirCor)

        let achado = Importacao.atributos(de: leitura(0.2), em: termos)
        XCTAssertFalse(achado.marcados.contains("azul"),
                       "cor medida com confiança baixa não pode chegar marcada")
    }

    /// E não pode sumir calada: a §28 desenhou a sugestão para custar um
    /// toque, então a ausência dela precisa dizer por que aconteceu.
    func testMedidaBaixaExplicaAAusencia() {
        let achado = Importacao.atributos(de: leitura(0.2), em: termos)
        XCTAssertTrue(
            achado.procedencia.contains { $0.contains("left unselected on purpose") },
            "a tela precisa dizer que a cor ficou de fora, e por quê")
    }

    /// Medida e boa: volta a sugerir. Sem isto o portão seria só uma forma
    /// cara de nunca mais sugerir cor nenhuma.
    func testMedidaAltaVoltaASugerir() {
        let achado = Importacao.atributos(de: leitura(0.95), em: termos)
        XCTAssertTrue(achado.marcados.contains("azul"))
    }

    // MARK: - A borda do limiar

    /// O limiar é inclusivo, e é UM: nenhuma tela conhece este número, então
    /// quando a calibração real chegar basta mudar `confiancaMinimaDaCaptura`.
    func testOLimiarEhInclusivoEViveNumLugarSo() {
        let piso = CorDaPeca.confiancaMinimaDaCaptura
        let noPiso = CorDaPeca.Leitura(termoId: "azul", rgb: [0.2, 0.4, 0.7],
                                       cobertura: 0.9, confiancaDaCaptura: piso)
        let abaixo = CorDaPeca.Leitura(termoId: "azul", rgb: [0.2, 0.4, 0.7],
                                       cobertura: 0.9,
                                       confiancaDaCaptura: piso.nextDown)
        XCTAssertTrue(noPiso.podeSugerirCor)
        XCTAssertFalse(abaixo.podeSugerirCor)
    }

    /// O texto já lido continua mandando: quando o OCR achou a cor, ela não é
    /// sobrescrita nem bloqueada pela medida da captura.
    func testCorVindaDoTextoNaoDependeDaConfiancaDaCaptura() {
        let comTexto = LeitorDeArquivo.Leitura(
            texto: "Vestido azul",
            cor: CorDaPeca.Leitura(termoId: "azul", rgb: [0.22, 0.42, 0.72],
                                   cobertura: 0.9, confiancaDaCaptura: 0.1),
            origem: .ocr)
        let achado = Importacao.atributos(de: comTexto, em: termos)
        XCTAssertTrue(achado.marcados.contains("azul"),
                      "a cor escrita no produto não depende da luz da foto")
    }
}
