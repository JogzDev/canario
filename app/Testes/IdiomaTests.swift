import XCTest
@testable import CanarioLogica

/// A troca de idioma tem duas partes que falham em silêncio, e são estas.
///
/// A primeira é a resolução: "seguir o iPhone" precisa acertar em `pt`, `pt-BR`
/// e `pt-PT`, e cair no inglês para o resto. Errar aqui manda a pessoa para o
/// idioma errado sem nenhum aviso.
///
/// A segunda é o preenchimento dos `%@`. Ele foi escrito à mão em vez de usar
/// `String(format:)` porque estas frases contêm `%` literal ("11,9% do
/// sortimento"), e `String(format:)` lê esse `%` como início de especificador.
/// Um teste que só olhasse frase sem porcentagem passaria e o app cairia na
/// primeira leitura de varejo.
final class IdiomaTests: XCTestCase {

    // MARK: - Resolver o idioma do sistema

    func testEscolhaExplicitaIgnoraOSistema() {
        XCTAssertEqual(
            PreferenciaDeIdioma.ingles.resolvido(preferidosDoSistema: ["pt-BR"]),
            .ingles)
        XCTAssertEqual(
            PreferenciaDeIdioma.portugues.resolvido(preferidosDoSistema: ["en-US"]),
            .portugues)
    }

    /// A comparação é por LÍNGUA, não por região. Um iPhone em `pt-PT` fala
    /// português; exigir `pt-BR` exato o mandaria para o inglês.
    func testSeguirOSistemaCasaPelaLinguaENaoPelaRegiao() {
        for tag in ["pt", "pt-BR", "pt-PT", "pt-br"] {
            XCTAssertEqual(
                PreferenciaDeIdioma.sistema.resolvido(preferidosDoSistema: [tag]),
                .portugues, "\(tag) devia resolver em português")
        }
        for tag in ["en", "en-US", "en-GB"] {
            XCTAssertEqual(
                PreferenciaDeIdioma.sistema.resolvido(preferidosDoSistema: [tag]),
                .ingles, "\(tag) devia resolver em inglês")
        }
    }

    /// A ORDEM da lista do aparelho manda: ela já vem em ordem de preferência.
    func testSeguirOSistemaRespeitaAOrdemDaLista() {
        XCTAssertEqual(
            PreferenciaDeIdioma.sistema.resolvido(
                preferidosDoSistema: ["es-ES", "pt-BR", "en-US"]),
            .portugues)
        XCTAssertEqual(
            PreferenciaDeIdioma.sistema.resolvido(
                preferidosDoSistema: ["fr-FR", "en-US", "pt-BR"]),
            .ingles)
    }

    /// Sem nenhum dos dois, cai no idioma-fonte do catálogo. Chutar português
    /// para um iPhone em espanhol seria adivinhar.
    func testIdiomaDesconhecidoCaiNoIdiomaFonte() {
        XCTAssertEqual(
            PreferenciaDeIdioma.sistema.resolvido(preferidosDoSistema: ["ja-JP"]),
            .ingles)
        XCTAssertEqual(
            PreferenciaDeIdioma.sistema.resolvido(preferidosDoSistema: []),
            .ingles)
    }

    /// O nome de cada idioma vai nele mesmo. É como o iOS lista os dele, e é o
    /// que permite alguém sair de um idioma que não lê.
    func testONomeDoIdiomaNuncaEhTraduzido() {
        XCTAssertEqual(Idioma.portugues.nomeNativo, "Português")
        XCTAssertEqual(Idioma.ingles.nomeNativo, "English")
    }

    // MARK: - A escolha sobrevive ao app fechar

    func testAEscolhaEhGravadaERelida() {
        let dominio = "IdiomaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: dominio)!
        defer { defaults.removePersistentDomain(forName: dominio) }

        let primeiro = GestorDeIdioma(defaults: defaults)
        XCTAssertEqual(primeiro.preferencia, .sistema, "o padrão é seguir o iPhone")
        primeiro.preferencia = .portugues

        let segundo = GestorDeIdioma(defaults: defaults)
        XCTAssertEqual(segundo.preferencia, .portugues,
                       "a escolha precisa sobreviver ao app fechar")
    }

    // MARK: - Preencher os argumentos

    func testPorcentoLiteralNaoEhEspecificador() {
        // Esta é a frase que quebraria `String(format:)`: um `%` colado numa
        // letra, no meio de texto com argumento.
        XCTAssertEqual(
            Frase.preencher("%@% of the assortment (%@)", com: ["11.9", "7217"]),
            "11.9% of the assortment (7217)")
        XCTAssertEqual(Frase.preencher("100% cotton", com: ["ignorado"]),
                       "100% cotton")
    }

    /// A tradução pode reordenar os argumentos; é para isso que serve `%n$@`.
    func testFormaPosicionalPermiteReordenar() {
        XCTAssertEqual(
            Frase.preencher("%2$@ antes de %1$@", com: ["A", "B"]),
            "B antes de A")
    }

    /// Um argumento a mais na tradução do que no código não pode derrubar o
    /// app: ele aparece como marcador, que é um defeito visível e corrigível.
    func testMarcadorSobrandoNaoEstouraEApareceNaTela() {
        XCTAssertEqual(Frase.preencher("%@ e %@", com: ["só um"]),
                       "só um e %@")
        XCTAssertEqual(Frase.preencher("%3$@", com: ["a", "b"]), "%3$@")
    }

    func testSemArgumentoOTextoPassaIntacto() {
        XCTAssertEqual(Frase.preencher("−12%", com: []), "−12%")
    }

    /// A chave que o extrator calcula tem de ser a mesma que o compilador
    /// monta. `ferramentas/extrair_frases.py` depende disto, e é o que impede
    /// uma frase de ficar em inglês sem ninguém perceber.
    func testAChaveMontadaUsaUmMarcadorPorInterpolacao() {
        let n = "3", termo = "midi"
        let f: Frase = "\(n) peças com \(termo)"
        XCTAssertEqual(f.chave, "%@ peças com %@")
        XCTAssertEqual(f.argumentos, ["3", "midi"])
    }

    /// O sentinela do portão de tradução não pode casar com chave real.
    ///
    /// O `extrair_frases.py` usava `""` como valor de fallback numa busca no
    /// catálogo. Existindo uma chave vazia no catálogo — e existia, gravada por
    /// um `--escrever` anterior ao filtro de texto de tela —, toda chave
    /// AUSENTE era reportada como presente e o portão inteiro virava decoração.
    /// Medido em 05/09.
    ///
    /// Este teste guarda o outro lado do problema: uma frase vazia não é texto
    /// de tela e nunca deve virar chave.
    func testFraseVaziaNaoVirarChaveDeCatalogo() {
        let vazia: Frase = ""
        XCTAssertTrue(vazia.chave.isEmpty)
        XCTAssertEqual(frase(vazia), "",
                       "frase vazia resolve para vazio, sem procurar tradução")
    }

    func testLiteralPuroNaoTemArgumentos() {
        let f: Frase = "Closet"
        XCTAssertEqual(f.chave, "Closet")
        XCTAssertTrue(f.argumentos.isEmpty)
    }
}
