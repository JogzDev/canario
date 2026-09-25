import Foundation

// MARK: - Cache instantâneo de Esta semana

struct SnapshotDaSemana: Codable {
    let todos: [IndiceSemanal]
    let termos: [Termo]
    let series: [String: [PontoSerie]]
    let pulsoBusca: [PontoSerie]
    let pulsoEditorial: [PontoSerie]
    let resumos: [String: ResumoDeEventos.Resposta]
    let salvoEm: Date
}

actor CacheDaSemana {
    static let shared = CacheDaSemana()
    private var memoria: SnapshotDaSemana?

    private var arquivo: URL {
        FileManager.default.urls(for: .cachesDirectory,
                                 in: .userDomainMask)[0]
            // v4 desde 18/09: os movimentos deixaram de ser uma lista de
            // eventos e passaram a ser a agregação por marca. Um arquivo v3
            // não decodifica na forma nova, e reaproveitar o nome faria a aba
            // abrir vazia uma vez sem que nada explicasse por quê.
            .appendingPathComponent("canario-explorar-v4.json")
    }

    func carregar() -> SnapshotDaSemana? {
        if let memoria { return memoria }
        guard let dados = try? Data(contentsOf: arquivo),
              let salvo = try? JSONDecoder().decode(
                SnapshotDaSemana.self, from: dados) else { return nil }
        memoria = salvo
        return salvo
    }

    func salvar(_ snapshot: SnapshotDaSemana) {
        memoria = snapshot
        guard let dados = try? JSONEncoder().encode(snapshot) else { return }
        try? dados.write(to: arquivo, options: .atomic)
    }
}

