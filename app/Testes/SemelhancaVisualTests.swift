import XCTest
@testable import CanarioLogica

/// Testes da sugestão visual (§28).
///
/// O que este arquivo guarda é uma fronteira, não uma acurácia: a §28 diz que a
/// visão só pode **pré-preencher** com concordância ≥ 80% contra etiquetagem
/// humana. Enquanto o artefato não declarar que passou, nenhuma sugestão sai —
/// e a maior parte dos testes abaixo verifica justamente o que o app **não**
/// oferece.
///
/// A conta é testada sem Vision e sem imagem de propósito: o que a Vision faz é
/// produzir o vetor; a decisão do que vira sugestão é nossa, e decisão precisa
/// de teste.
final class SemelhancaVisualTests: XCTestCase {

    // MARK: - Fábricas

    private func centroide(_ id: String, _ dim: String, _ v: [Double],
                           n: Int = 500) -> SemelhancaVisual.Centroide {
        SemelhancaVisual.Centroide(termoId: id, dimensao: dim, nImagens: n, vetor: v)
    }

    private func painel(_ cs: [SemelhancaVisual.Centroide],
                        passou: Bool = true,
                        dimensoes: Int = 3) -> SemelhancaVisual.Painel {
        SemelhancaVisual.Painel(
            versao: 1, geradoEm: "2026-08-06", dimensoes: dimensoes,
            portao: SemelhancaVisual.Portao(
                concordanciaCategoria: passou ? 0.84 : 0.41,
                concordanciaCor: passou ? 0.88 : 0.52,
                nPecasAvaliadas: 100, passou: passou),
            centroides: cs)
    }

    // MARK: - O portão da §28

    func testPortaoFechadoNaoSugereNada() {
        let p = painel([centroide("vestido", "peca", [1, 0, 0])], passou: false)
        // O vetor é IDÊNTICO ao centroide: cosseno 1, o caso mais favorável
        // possível. Ainda assim não sai sugestão, porque a §28 não é sobre a
        // confiança de um caso, é sobre a medição do conjunto.
        XCTAssertEqual(
            SemelhancaVisual.ranquear(vetorDaFoto: [1, 0, 0], painel: p), [],
            "portão da §28 fechado tem que calar mesmo com casamento perfeito")
    }

    func testPortaoAbertoSugere() {
        let p = painel([centroide("vestido", "peca", [1, 0, 0])])
        XCTAssertEqual(
            SemelhancaVisual.ranquear(vetorDaFoto: [1, 0, 0], painel: p).first?.termoId,
            "vestido")
    }

    // MARK: - Cortes

    func testCentroideDePoucasImagensNaoSugere() {
        // A média de meia dúzia de fotos descreve aquelas fotos, não o termo.
        let p = painel([centroide("boho_artesanal", "estilo", [1, 0, 0], n: 12)])
        XCTAssertEqual(SemelhancaVisual.ranquear(vetorDaFoto: [1, 0, 0], painel: p), [])
    }

    func testAbaixoDoCorteDeSemelhancaNaoSugere() {
        let p = painel([centroide("vestido", "peca", [1, 0, 0])])
        // Ortogonal: cosseno 0.
        XCTAssertEqual(SemelhancaVisual.ranquear(vetorDaFoto: [0, 1, 0], painel: p), [])
    }

    func testNoMaximoDuasPorDimensao() {
        let p = painel([
            centroide("a", "cor", [1.0, 0.0, 0.0]),
            centroide("b", "cor", [0.99, 0.14, 0.0]),
            centroide("c", "cor", [0.97, 0.24, 0.0]),
            centroide("d", "cor", [0.95, 0.31, 0.0]),
        ])
        let r = SemelhancaVisual.ranquear(vetorDaFoto: [1, 0, 0], painel: p)
        XCTAssertEqual(r.count, 2, "quatro sugestões de cor não é sugestão, é lista")
        XCTAssertEqual(r.map(\.termoId), ["a", "b"])
    }

    func testDimensoesDiferentesNaoCompetemEntreSi() {
        let p = painel([
            centroide("vestido", "peca", [1.0, 0.0, 0.0]),
            centroide("azul", "cor", [0.99, 0.14, 0.0]),
            centroide("floral", "estampa", [0.97, 0.24, 0.0]),
        ])
        let r = SemelhancaVisual.ranquear(vetorDaFoto: [1, 0, 0], painel: p)
        XCTAssertEqual(Set(r.map(\.dimensao)), ["peca", "cor", "estampa"],
                       "peça, cor e estampa são perguntas separadas")
    }

    // MARK: - Determinismo

    func testOrdemEstavelComEmpate() {
        let p = painel([
            centroide("zebra", "peca", [1, 0, 0]),
            centroide("alfa", "peca", [1, 0, 0]),
        ])
        let a = SemelhancaVisual.ranquear(vetorDaFoto: [1, 0, 0], painel: p)
        let b = SemelhancaVisual.ranquear(vetorDaFoto: [1, 0, 0], painel: p)
        XCTAssertEqual(a.map(\.termoId), b.map(\.termoId),
                       "tela que troca de ordem a cada leitura parece quebrada")
    }

    // MARK: - Cosseno

    func testCossenoDeVetoresIdenticosEUm() {
        XCTAssertEqual(SemelhancaVisual.cosseno([1, 2, 3], [1, 2, 3])!, 1.0, accuracy: 1e-12)
    }

    func testCossenoIgnoraEscala() {
        // O feature print não vem normalizado; dobrar o vetor não pode mudar a
        // semelhança.
        XCTAssertEqual(SemelhancaVisual.cosseno([1, 2, 3], [2, 4, 6])!, 1.0, accuracy: 1e-12)
    }

    func testCossenoDeFormasDiferentesENulo() {
        XCTAssertNil(SemelhancaVisual.cosseno([1, 2, 3], [1, 2]))
    }

    func testCossenoDeVetorNuloENulo() {
        // Imagem que produz vetor zerado não "se parece com tudo": não se sabe.
        XCTAssertNil(SemelhancaVisual.cosseno([0, 0, 0], [1, 2, 3]))
    }

    // MARK: - Formato do artefato

    func testDecodificaOArtefatoRealDoGerador() throws {
        // Formato exato que `gerar_centroides.swift` escreve. Testar contra o
        // JSON, e não contra a struct, é o que pega erro de `CodingKeys`.
        let json = """
        {
          "versao": 1,
          "gerado_em": "2026-08-06",
          "dimensoes": 768,
          "portao_28": {
            "concordancia_categoria": 0.0,
            "concordancia_cor": 0.0,
            "n_pecas_avaliadas": 0,
            "passou": false
          },
          "centroides": [
            {"termo_id": "vestido", "dimensao": "peca", "n_imagens": 1243,
             "vetor": [0.1, 0.2, 0.3]}
          ]
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(SemelhancaVisual.Painel.self, from: json)
        XCTAssertEqual(p.centroides.first?.termoId, "vestido")
        XCTAssertEqual(p.centroides.first?.nImagens, 1243)
        XCTAssertFalse(p.portao.passou,
                       "artefato recém-gerado nasce com o portão FECHADO")
        XCTAssertEqual(SemelhancaVisual.ranquear(vetorDaFoto: [0.1, 0.2, 0.3], painel: p), [],
                       "e por isso não sugere nada até alguém medir")
    }
}
