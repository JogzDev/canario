import Foundation
import XCTest
@testable import CanarioLogica

final class ModelosTests: XCTestCase {
    func testTermoDecodificaCamposDoBancoEAmpliaBusca() throws {
        let json = #"{"id":"preto","rotulo":"Black","dimensao":"cor","exclusiva":true,"sinonimos":"negro|black","sem_perna_busca":null,"palavras_pt":"preto|preta","palavras_en":"black"}"#
        let termo = try JSONDecoder().decode(Termo.self, from: Data(json.utf8))

        XCTAssertEqual(termo.id, "preto")
        XCTAssertTrue(termo.termosDeBusca.contains("preta"))
        XCTAssertTrue(termo.termosDeBusca.contains("black"))
    }

    func testIndicePreservaMetaComChaveNegativaDoContrato() throws {
        let json = #"{"id":1,"termo_id":"floral","segmento":"feminino_casual_br","semana":"2026-08-17","indice":1.2,"estado":"em alta","pernas_ativas":["varejo","busca"],"n_pernas":2,"meta":{"indice_semana_anterior":0.8,"pernas_acima_de_1":2,"pernas_abaixo_de_-1":0},"computado_em":"2026-08-21T00:00:00Z"}"#
        let indice = try JSONDecoder().decode(IndiceSemanal.self, from: Data(json.utf8))

        XCTAssertEqual(indice.termoId, "floral")
        XCTAssertEqual(indice.meta?.pernasAcimaDe1, 2)
        XCTAssertEqual(indice.meta?.pernasAbaixoDe1, 0)
        XCTAssertEqual(Estado(rawValue: indice.estado ?? "")?.icone,
                       "arrow.up.right")
    }

    func testPontoSerieNomeiaVeiculosEmOrdemDeContagem() throws {
        let json = #"{"id":2,"termo_id":"midi","fonte":"editorial_br","semana":"2026-08-17","valor_bruto":6,"z":0.5,"n_amostra":6,"meta":{"unidade":"materias","veiculos":{"Vogue Brasil":2,"Elle Brasil":4},"exemplos":[],"contagem_semana_crua":6,"metrica":"mencoes","n_total_sortimento":null}}"#
        let ponto = try JSONDecoder().decode(PontoSerie.self, from: Data(json.utf8))

        XCTAssertEqual(ponto.meta?.veiculosEmTexto,
                       "Elle Brasil (4), Vogue Brasil (2)")
        XCTAssertEqual(Perna.baseadoEm(["editorial_br", "varejo"]),
                       "based on: Brazilian editorial + retail")
    }

    func testSeteFaixasVisuaisCobremOsLimiaresSemBuracos() {
        XCTAssertEqual(Leitura.faixa(2), .muitoAcima)
        XCTAssertEqual(Leitura.faixa(1), .acima)
        XCTAssertEqual(Leitura.faixa(0.35), .poucoAcima)
        XCTAssertEqual(Leitura.faixa(0), .habitual)
        XCTAssertEqual(Leitura.faixa(-0.35), .poucoAbaixo)
        XCTAssertEqual(Leitura.faixa(-1), .abaixo)
        XCTAssertEqual(Leitura.faixa(-2), .muitoAbaixo)
        XCTAssertEqual(Set(Leitura.Faixa.allCases.map(\.rotulo)).count, 7)
    }
}
