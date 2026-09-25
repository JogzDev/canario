import XCTest
@testable import CanarioLogica

/// A resposta da `ler-peca` como ela chega (formato da leitura de 24/09/2026)
/// e a prova de cada frase.
final class LeituraEspecificaTests: XCTestCase {
    private let json = """
    {
      "versao": "leitura-especifica-v1",
      "nome": "saia midi plissada",
      "explicacao": "Saia de comprimento midi com pregas plissadas.",
      "perguntas": [{"pergunta": "Qual tecido?", "opcoes": ["Jeans", "Malha"]}],
      "painel_observado_em": "2026-09-23",
      "busca": {"categorias": ["saia"], "atributos": ["midi"], "sinais": ["plissada"], "vetos": [],
                "candidatas": 11, "verificadas": 11, "confirmadas": 11, "parecidas": 0},
      "frases": [
        {"texto": "Há 11 saias midi plissadas de 3 marcas no painel.", "fatos": ["total"]},
        {"texto": "Seis estão remarcadas.", "fatos": ["remarcadas", "total"]}
      ],
      "frases_recusadas": 0,
      "fatos": {
        "total": {"id": "total", "pecas": 11, "marcas": 3, "provas": [10, 11, 12]},
        "remarcadas": {"id": "remarcadas", "pecas": 6, "de_cada_100": 55, "provas": [12, 99]},
        "marcas": {"id": "marcas", "por_marca": [{"marca": "C&A", "pecas": 8}]}
      },
      "pecas": [
        {"id": 10, "titulo": "Saia Midi Pregas", "marca": "Maria Filo", "preco": 869, "preco_original": 869,
         "imagem_url": null, "url": "https://loja.test/10", "visto_em": "2026-09-23", "sinais_casados": 1, "veredito": "e_a_peca"},
        {"id": 11, "titulo": "saia midi plissada azul", "marca": "C&A", "preco": 49.99, "preco_original": 89.99,
         "imagem_url": "https://img.test/11.jpg", "url": null, "visto_em": "2026-09-23", "sinais_casados": 1, "veredito": "e_a_peca"},
        {"id": 12, "titulo": "Saia Plissada Midi Estampada", "marca": "Animale", "preco": 1199, "preco_original": 1199,
         "imagem_url": null, "url": "https://loja.test/12", "visto_em": "2026-09-23", "sinais_casados": 2, "veredito": "e_a_peca"}
      ],
      "parecidas": [],
      "modelo": "gpt-5.6-luna"
    }
    """

    func testDecodificaARespostaReal() throws {
        let leitura = try LeituraEspecifica.decodificar(Data(json.utf8))
        XCTAssertEqual(leitura.nome, "saia midi plissada")
        XCTAssertEqual(leitura.frases.count, 2)
        XCTAssertEqual(leitura.fatos["total"]?.pecas, 11)
        XCTAssertEqual(leitura.pecas.count, 3)
        XCTAssertEqual(leitura.perguntas.first?.opcoes, ["Jeans", "Malha"])
        XCTAssertEqual(leitura.busca?.confirmadas, 11)
        XCTAssertNil(leitura.pecas[0].imagemUrl)
    }

    func testProvaDaFraseSegueOsFatosSemRepetirEIgnoraIdDesconhecido() throws {
        let leitura = try LeituraEspecifica.decodificar(Data(json.utf8))
        // "remarcadas" cita 12 e 99 (99 nao veio nas pecas); "total" repete 12.
        let provas = leitura.provas(de: leitura.frases[1]).map(\.id)
        XCTAssertEqual(provas, [12, 10, 11])
    }

    func testRemarcadaSoComCincoPorCentoOuMais() throws {
        let leitura = try LeituraEspecifica.decodificar(Data(json.utf8))
        XCTAssertTrue(leitura.pecas[1].remarcada)
        XCTAssertFalse(leitura.pecas[0].remarcada)
    }

    func testRespostaDeForaDeEscopoSemListas() throws {
        let leitura = try LeituraEspecifica.decodificar(Data("""
        {"versao": "leitura-especifica-v1", "fora_de_escopo": true, "nome": "tenis", "explicacao": "Calcado."}
        """.utf8))
        XCTAssertEqual(leitura.foraDeEscopo, true)
        XCTAssertTrue(leitura.frases.isEmpty && leitura.pecas.isEmpty && leitura.fatos.isEmpty)
    }
}

final class DescricaoDaPecaTests: XCTestCase {
    private func termo(_ id: String, _ dimensao: String) -> Termo {
        Termo(id: id, rotulo: id, dimensao: dimensao, exclusiva: false,
              sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    func testTermosDaPecaViramAAnaliseQueALeituraEntende() {
        let termos = [termo("saia", "categoria"), termo("midi", "comprimento"), termo("preto", "cor"),
                      termo("verde", "cor"), termo("jeans", "tecido"), termo("romantico", "estetica")]
        let d = DescricaoDaPeca.dosTermos(["saia", "midi", "preto", "verde", "jeans", "romantico", "desconhecido"],
                                          em: termos)
        XCTAssertEqual(d.categoria, "saia")
        XCTAssertEqual(d.comprimento, "midi")
        XCTAssertEqual(d.cores, ["preto", "verde"])
        XCTAssertEqual(d.tecidos, ["jeans"])
        XCTAssertEqual(d.comoAnalise["pattern"] as? String, "not_visible")
        XCTAssertEqual(d.comoAnalise["colors"] as? [String], ["preto", "verde"])
        XCTAssertFalse(d.vazia)
        XCTAssertTrue(DescricaoDaPeca.dosTermos([], em: termos).vazia)
    }

    private var analiseDaFoto: AnaliseVisualRemota {
        get throws {
            try JSONDecoder().decode(AnaliseVisualRemota.self, from: Data("""
            {"target_clarity":"single_clear_target","garment_structure":"upper_other",
             "category":"blusa_top","decision_evidence":[],"pattern":"not_visible",
             "fabrics":[],"length":"not_visible","silhouette":"not_visible",
             "waist":"not_visible","aesthetics":[],"colors":["azul"],
             "additional_visual_attributes":["  abotoamento   duplo  ", "not_visible", "",
               "lapela larga", "ABOTOAMENTO DUPLO", "manga bufante", "forro claro",
               "textura canelada", "costura aparente", "um detalhe adicional",
               "peça com descrição visual longa, maior que sessenta caracteres para cortar"],
             "model":"teste","prompt_version":"teste"}
            """.utf8))
        }
    }

    func testFotoRespeitaOsAtributosConfirmadosELevaSoDetalhesValidos() throws {
        let termos = [termo("camisa", "categoria"), termo("blusa_top", "categoria"),
                      termo("preto", "cor"), termo("azul", "cor")]
        let descricao = DescricaoDaPeca.daFoto(try analiseDaFoto,
                                               confirmados: ["camisa", "preto"], em: termos)
        XCTAssertEqual(descricao.categoria, "camisa")
        XCTAssertEqual(descricao.cores, ["preto"])
        XCTAssertEqual(descricao.estampa, nil)
        XCTAssertEqual(descricao.comoAnalise["category"] as? String, "camisa")
        XCTAssertEqual(descricao.comoAnalise["colors"] as? [String], ["preto"])
        XCTAssertEqual(descricao.comoAnalise["pattern"] as? String, "not_visible")
        XCTAssertEqual(descricao.detalhes.count, 6)
        XCTAssertEqual(descricao.detalhes.first, "abotoamento duplo")
        XCTAssertFalse(descricao.detalhes.contains("not_visible"))
        XCTAssertTrue(descricao.detalhes.allSatisfy { $0.count <= 60 })
        XCTAssertEqual(descricao.comoAnalise["additional_visual_attributes"] as? [String],
                       descricao.detalhes)
    }

    func testDetalhesLongosSaoCortadosEApenasDetalhesTambemContam() {
        let longo = String(repeating: "x", count: 75)
        XCTAssertEqual(DescricaoDaPeca.limparDetalhes([longo]),
                       [String(repeating: "x", count: 60)])
        var descricao = DescricaoDaPeca()
        XCTAssertTrue(descricao.vazia)
        descricao.detalhes = ["abotoamento duplo"]
        XCTAssertFalse(descricao.vazia)
    }

    func testPecaSalvaNoFormatoAntigoContinuaAbrindoSemDetalhes() throws {
        let dados = Data("""
        {"id":"61F00B3B-CE42-49A0-A493-5178BDEB1D1E","apelido":"Camisa antiga",
         "termoIds":["camisa"],"criadaEm":0}
        """.utf8)
        let antiga = try JSONDecoder().decode(PecaSalva.self, from: dados)
        XCTAssertNil(antiga.detalhesVisuais)
        XCTAssertEqual(antiga.termoIds, ["camisa"])
    }
}
