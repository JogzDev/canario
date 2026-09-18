import Foundation

/// Respostas de mentira para o bloco "In the press", só em teste de interface.
///
/// ## Por que existe
///
/// `buscar_referencia_editorial` ainda não está publicada, e a regra do
/// projeto é que os fluxos do CI rodem sem rede. As duas coisas juntas
/// deixariam o bloco sem nenhum teste de tela justamente na semana em que ele
/// nasce — e os quatro estados que interessam (achou, não achou, falhou,
/// trocou de pergunta no meio) são todos de tela, não de banco.
///
/// ## O que ela não faz
///
/// Não substitui o banco em nenhum caminho de produto: sem o argumento de
/// linha de comando, `ativa` é `false` e nada aqui é chamado. O argumento só
/// existe no `launchArguments` do XCTest, que não tem como chegar a um
/// aparelho de usuário.
enum ImprensaDeTeste {

    static let bandeira = "-CanarioUITestImprensa"

    /// O caso pedido, ou `nil` fora de teste.
    static var caso: String? {
        let argumentos = ProcessInfo.processInfo.arguments
        guard let i = argumentos.firstIndex(of: bandeira),
              i + 1 < argumentos.count else { return nil }
        return argumentos[i + 1]
    }

    static var ativa: Bool { caso != nil }

    /// Quanto a resposta "lenta" demora no caso `troca`.
    ///
    /// Precisa ser maior que a pausa de 350 ms da tela e folgada o bastante
    /// para o teste digitar a segunda expressão enquanto a primeira ainda
    /// está em voo — é esse cruzamento que o teste existe para provar.
    static let esperaDaLenta: UInt64 = 1_500_000_000

    static func responder(_ expressao: String) async throws
    -> ReferenciaEditorial.Resposta {
        switch caso {
        case "vazio":
            return .init(expressao: expressao, buscavel: true, total: 0,
                         materias: [])
        case "erro":
            throw Supabase.Falha.rede(URLError(.notConnectedToInternet))
        case "ausente":
            // O 404 exato de função inexistente no PostgREST. A tela precisa
            // calar neste, e só neste.
            throw Supabase.Falha.resposta(404, #"{"code":"PGRST202","message":"Could not find the function"}"#)
        case "troca":
            // Primeiro comprova a transicao visivel A -> B: A aparece, a tela
            // troca a consulta de uma vez e B demora. Nesse intervalo, A ja
            // nao pode continuar sob o texto de B.
            if expressao.lowercased().hasPrefix("primeira") {
                return resposta(expressao, titulo: "Resposta visivel da pergunta A")
            }
            if expressao.lowercased().hasPrefix("segunda") {
                try await Task.sleep(nanoseconds: esperaDaLenta)
                return resposta(expressao, titulo: "Resposta tardia da pergunta B")
            }
            // A pergunta lenta responde DEPOIS da rápida. Se a tela escrever
            // o que chega em vez do que foi perguntado, "Lenta" aparece por
            // cima de "Rapida" e o teste pega.
            if expressao.lowercased().hasPrefix("lenta") {
                try await Task.sleep(nanoseconds: esperaDaLenta)
                return resposta(expressao, titulo: "Resposta lenta da pergunta A")
            }
            return resposta(expressao, titulo: "Resposta rapida da pergunta B")
        default:
            return resposta(expressao,
                            titulo: "The Napoleon Jacket Is Making A Comeback This Fall")
        }
    }

    private static func resposta(_ expressao: String, titulo: String)
    -> ReferenciaEditorial.Resposta {
        .init(expressao: expressao, buscavel: true, total: 1,
              materias: [.init(titulo: titulo, veiculo: "Refinery29",
                               data: "2026-08-31",
                               url: "https://example.invalid/napoleon")])
    }
}
