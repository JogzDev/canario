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
            // Frase inteira por origem, e não um fragmento interpolado: era
            // `From \(fonte)` com "PDF text" cru por dentro, e o miolo ficava
            // em inglês dentro do português. Mesma classe do `\(lado)` do
            // `Leitura.explicacao`, e a mesma correção.
            let lidos = porTexto.map(Traducao.rotuloExibido).joined(separator: ", ")
            achado.procedencia.append(leitura.origem == .textoDoPDF
                ? frase("From PDF text: \(lidos).")
                : frase("From text recognized in the image: \(lidos)."))
        }

        if let cor = leitura.cor {
            let jaTemCor = porTexto.contains { $0.dimensao == "cor" }
            let existe = termos.first { $0.id == cor.termoId }
            if !jaTemCor, let termo = existe {
                // O portão da cor de constante (iOS 18): quando o SISTEMA mediu
                // a captura e disse que não confia nela, o app não pré-marca.
                //
                // A alternativa era marcar assim mesmo e escrever "confiança
                // baixa" ao lado. Isso inverte o custo do erro: a §28 desenhou
                // a sugestão para custar um toque quando errada, mas um chip
                // JÁ MARCADO é aceito por omissão — quem não lê a ressalva
                // salva a cor errada no Closet sem nunca ter decidido nada.
                // Deixar desmarcado custa o mesmo toque e não decide por
                // ninguém, que é o que a regra 2 pede quando falta base.
                if cor.podeSugerirCor {
                    achado.marcados.insert(termo.id)
                    achado.procedencia.append(frase("From the image color: \(Traducao.rotuloExibido(termo)) — measured from the garment pixels, and is the suggestion that most needs your review."))
                } else {
                    achado.procedencia.append(frase("The color was left unselected on purpose: this photo's lighting was not reliable enough to measure it. Pick the color below, or retake the photo with color-accurate capture."))
                }
            }
        }

        return achado
    }

    /// Marcas reconhecidas pelo OCR local. É contexto para a futura avaliação
    /// da Luna, nunca prova de modelo, material ou composição. Os aliases ficam
    /// explícitos para não transformar substring acidental em identidade.
    static func marcasNoTexto(_ texto: String) -> [String] {
        let palavras = Traducao.normalizar(texto).split(whereSeparator: {
            !$0.isLetter && !$0.isNumber
        }).map(String.init)
        let linha = " " + palavras.joined(separator: " ") + " "
        let aliases: [(String, [String])] = [
            ("Patagonia", ["patagonia"]),
            ("Farm Rio", ["farm rio", "farmrio"]),
            ("Animale", ["animale"]),
            ("Maria Filó", ["maria filo", "mariafilo"]),
            ("Dress To", ["dress to", "dressto"]),
            ("PatBo", ["patbo"]),
            ("Hering", ["hering"]),
            ("Zinzane", ["zinzane"]),
            ("Cantão", ["cantao"]),
            ("Amaro", ["amaro"]),
        ]
        return aliases.compactMap { nome, formas in
            formas.contains { linha.contains(" \($0) ") } ? nome : nil
        }
    }
}
