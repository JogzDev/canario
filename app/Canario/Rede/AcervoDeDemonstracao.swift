#if DEBUG
import Foundation

/// Só no build de desenvolvimento: semeia o Acervo com peças reais do painel.
///
/// O recorte da Vision não roda no simulador (não há Neural Engine), então as
/// peças chegam já recortadas no Mac com o MESMO pedido que o app usa no
/// aparelho (`VNGenerateForegroundInstanceMaskRequest`), em PNG transparente —
/// o que um iPhone guardaria. Serve para capturas de tela e para as fotos da
/// App Store. Nada disto existe no build da loja.
///
/// Uso: `-CanarioSemearAcervo <pasta>` com um `manifesto.json` de
/// `{arquivo, termos, favorita?}`. Só age com o Acervo vazio.
enum AcervoDeDemonstracao {
    private struct Item: Decodable {
        let arquivo: String
        let termos: [String]
        let favorita: Bool?
    }

    static func semearSePedido() async -> Bool {
        let argumentos = ProcessInfo.processInfo.arguments
        guard let i = argumentos.firstIndex(of: "-CanarioSemearAcervo"),
              i + 1 < argumentos.count else { return false }
        let pasta = URL(fileURLWithPath: argumentos[i + 1])
        guard await PecasSalvas.shared.todas().isEmpty else {
            NSLog("AcervoDeDemonstracao: Acervo já tem peças; nada a semear")
            return false
        }
        let manifesto = pasta.appendingPathComponent("manifesto.json")
        guard let dados = try? Data(contentsOf: manifesto),
              let itens = try? JSONDecoder().decode([Item].self, from: dados) else {
            NSLog("AcervoDeDemonstracao: manifesto ilegível em \(manifesto.path)")
            return false
        }
        for (n, item) in itens.enumerated().reversed() {
            guard let png = try? Data(contentsOf: pasta.appendingPathComponent(item.arquivo)) else { continue }
            let peca = PecaSalva(termoIds: item.termos,
                                 criadaEm: Date().addingTimeInterval(Double(-n) * 3600),
                                 favorita: item.favorita)
            let salvou = await PecasSalvas.shared.salvar(peca, miniaturaDados: png)
            NSLog("AcervoDeDemonstracao: \(item.arquivo) salva = \(salvou)")
        }
        return true
    }
}
#endif
