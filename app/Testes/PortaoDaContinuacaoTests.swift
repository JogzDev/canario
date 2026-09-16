import Dispatch
import Foundation
import XCTest
@testable import CanarioLogica

final class PortaoDaContinuacaoTests: XCTestCase {
    func testSomenteUmCaminhoPodeConcluirMesmoSobConcorrencia() {
        let portao = LeitorDeArquivo.PortaoDaContinuacao()
        let grupo = DispatchGroup()
        let fila = DispatchQueue(label: "portao-continuacao", attributes: .concurrent)
        let trava = NSLock()
        var vencedores = 0

        for _ in 0..<1_000 {
            grupo.enter()
            fila.async {
                if portao.assumir() {
                    trava.lock()
                    vencedores += 1
                    trava.unlock()
                }
                grupo.leave()
            }
        }

        XCTAssertEqual(grupo.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(vencedores, 1)
        XCTAssertFalse(portao.assumir())
    }
}
