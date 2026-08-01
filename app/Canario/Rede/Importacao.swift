import Foundation

/// Junta o que o arquivo entregou e decide o que fica marcado no formulário.
///
/// Vive fora da tela porque é a única parte da entrada por arquivo que tem
/// decisão dentro — qual fonte ganha quando duas discordam — e decisão se
/// verifica testando, não olhando.
enum Importacao {

    struct Achado: Equatable {
        var marcados: Set<String> = []
        /// Uma linha por fonte, para a tela mostrar de onde veio cada marcação.
        var procedencia: [String] = []
    }

    /// **Texto ganha de pixel.** Quando o título diz "off white" e o pixel mede
    /// cinza, o título vale: ele é a cor que a marca declarou, o pixel é a cor
    /// que a foto capturou sob a luz do estúdio. Marcar as duas poria duas
    /// cores na mesma peça, que é contradição na cara do usuário.
    static func atributos(de leitura: LeitorDeArquivo.Leitura,
                          em termos: [Termo]) -> Achado {
        var achado = Achado()

        let porTexto = Traducao.termos(para: leitura.texto, em: termos)
        if !porTexto.isEmpty {
            achado.marcados.formUnion(porTexto.map(\.id))
            let fonte = leitura.origem == .textoDoPDF
                ? "texto do PDF"
                : "texto reconhecido na imagem"
            achado.procedencia.append(
                "Do \(fonte): " + porTexto.map(\.rotulo).joined(separator: ", ") + ".")
        }

        if let cor = leitura.cor {
            let jaTemCor = porTexto.contains { $0.dimensao == "cor" }
            let existe = termos.first { $0.id == cor.termoId }
            if !jaTemCor, let termo = existe {
                achado.marcados.insert(termo.id)
                achado.procedencia.append(
                    "Da cor da imagem: \(termo.rotulo) — medida no próprio pixel, "
                    + "é a marcação que mais pede conferência.")
            }
        }

        return achado
    }
}
