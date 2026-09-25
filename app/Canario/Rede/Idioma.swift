import Foundation
#if canImport(Combine)
import Combine
#endif

/// O idioma da interface, escolhido dentro do app.
///
/// POR QUE ISTO EXISTE
/// ===================
///
/// A A16 fixou a interface em inglês e a §34 listou "sem multi-idioma" no
/// anti-escopo. As duas foram emendadas em 05/09 (A53) por decisão do JP depois
/// da apresentação: o app precisa trocar de idioma **inteiro**, e não só de
/// alguns rótulos.
///
/// "Inteiro" é a parte que dá trabalho e é onde este arquivo importa. O
/// `Localizable.xcstrings` resolve sozinho tudo que é `LocalizedStringKey` —
/// `Text("Closet")`, `Button("Cancel")`, `navigationTitle`. Ele **não** resolve
/// as centenas de frases que o app monta como `String` e mostra depois:
/// mensagens de erro, a prosa do `Explicacao`, os rótulos da taxonomia. Para
/// essas, o idioma precisa ser perguntado explicitamente — é o que `frase(_:)`
/// faz, e é por isso que existe um dono único da escolha em vez de cada tela
/// ler `Locale.current`.
///
/// **O idioma do app não é o idioma do dado.** Os ids da taxonomia continuam em
/// português (`vestido`, `branco_cru`) porque são contrato de banco e série
/// histórica; o que troca é o rótulo exibido. Manchete de veículo brasileiro
/// continua em português mesmo com a interface em inglês, porque é citação de
/// fonte — traduzi-la seria inventar texto que a fonte não publicou, contra a
/// regra inviolável 3.
public enum Idioma: String, CaseIterable, Sendable {
    case ingles = "en"
    case portugues = "pt-BR"

    /// Como o idioma se chama **nele mesmo**. Nunca traduzido: quem abre os
    /// ajustes com o app num idioma que não lê precisa reconhecer o próprio.
    /// É a razão de a lista de idiomas do iOS dizer "Português", e não
    /// "Portuguese", quando o aparelho está em inglês.
    public var nomeNativo: String {
        switch self {
        case .ingles:    return "English"
        case .portugues: return "Português"
        }
    }

    /// O `Locale` que formata data, número e moeda neste idioma.
    public var locale: Locale { Locale(identifier: rawValue) }
}

/// O que a pessoa escolheu nos Ajustes.
///
/// Três estados, e não dois, pelo mesmo motivo que a preferência de análise
/// visual tem três: *seguir o sistema* é uma escolha real e é a única que
/// continua certa quando a pessoa troca o idioma do iPhone depois. Um par
/// inglês/português obrigaria a decidir no primeiro uso e nunca mais acertar
/// sozinho.
public enum PreferenciaDeIdioma: String, CaseIterable, Sendable {
    case sistema
    case ingles
    case portugues

    /// Em que idioma isto resolve, dado o que o sistema pede.
    ///
    /// `preferidosDoSistema` recebe algo como `["pt-BR", "en-US"]`. A
    /// comparação é por **prefixo de língua**, não por igualdade: um iPhone em
    /// `pt-PT` ou `pt` continua sendo português para efeito de interface, e
    /// exigir `pt-BR` exato mandaria essa pessoa para o inglês sem motivo.
    public func resolvido(preferidosDoSistema: [String]) -> Idioma {
        switch self {
        case .ingles:    return .ingles
        case .portugues: return .portugues
        case .sistema:
            for tag in preferidosDoSistema {
                let lingua = tag.split(separator: "-").first.map(String.init)?
                    .lowercased() ?? tag.lowercased()
                if lingua == "pt" { return .portugues }
                if lingua == "en" { return .ingles }
            }
            // Sem português nem inglês na lista do aparelho, o app cai no
            // idioma-fonte do catálogo. Não é escolha de gosto: é a única
            // localização que existe por completo, e chutar português para um
            // iPhone em espanhol seria adivinhar.
            return .ingles
        }
    }
}

/// Dono único da escolha de idioma.
///
/// Guarda em `UserDefaults` porque a escolha precisa sobreviver ao app fechar e
/// não pertence ao Closet nem à conta — é preferência deste aparelho, como a de
/// análise visual.
public final class GestorDeIdioma: ObservableObject {

    public static let shared = GestorDeIdioma(ehOGlobal: true)

    private static let chave = "idioma_da_interface"

    /// Só UM gestor manda no bundle que `frase(_:)` consulta.
    ///
    /// Sem esta trava, qualquer instância secundária — um teste com
    /// `UserDefaults` próprio, uma pré-visualização — reescrevia o idioma
    /// global ao nascer. Aconteceu na primeira execução da suíte: o teste que
    /// grava "português" mudou o bundle do processo inteiro, e as asserções de
    /// `TraducaoTests` sobre os rótulos em inglês passaram a receber
    /// "Blusas e camisetas". O sintoma foi teste vermelho; num app com duas
    /// instâncias seria a tela trocando de idioma sozinha.
    private let ehOGlobal: Bool

    /// O que a pessoa escolheu. Escrever aqui já grava e já reconstrói o
    /// bundle: não existe um segundo passo a esquecer.
    @Published public var preferencia: PreferenciaDeIdioma {
        didSet {
            guard preferencia != oldValue else { return }
            defaults.set(preferencia.rawValue, forKey: Self.chave)
            if ehOGlobal { Self.publicarIdioma(atual) }
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, ehOGlobal: Bool = false) {
        self.defaults = defaults
        self.ehOGlobal = ehOGlobal
        let guardado = defaults.string(forKey: Self.chave)
        self.preferencia = guardado.flatMap(PreferenciaDeIdioma.init(rawValue:)) ?? .sistema
        if ehOGlobal { Self.publicarIdioma(atual) }
    }

    /// O idioma efetivo agora.
    public var atual: Idioma {
        preferencia.resolvido(preferidosDoSistema: Locale.preferredLanguages)
    }

    public var locale: Locale { atual.locale }

    // MARK: - A ponte para `frase(_:)`
    //
    // `frase(_:)` é chamada de dentro de código que não é `@MainActor` — o
    // `Explicacao`, o `Similares`, os erros de rede. Ela não pode alcançar uma
    // `ObservableObject` publicada na main thread sem arriscar corrida, então o
    // gestor **empurra** o bundle resolvido para um cofre protegido por lock em
    // vez de deixar cada chamador puxar.

    private static let cofre = NSLock()
    nonisolated(unsafe) private static var bundleAtual = Bundle.main
    nonisolated(unsafe) private static var idiomaAtual = Idioma.ingles

    private static func publicarIdioma(_ idioma: Idioma) {
        cofre.lock()
        defer { cofre.unlock() }
        idiomaAtual = idioma
        bundleAtual = Self.bundle(de: idioma) ?? .main
    }

    /// O `.lproj` do idioma escolhido, ou `nil` quando ele não foi empacotado.
    ///
    /// `nil` cai no bundle principal, e o principal devolve a chave — que é o
    /// texto em inglês, o idioma-fonte do catálogo. Uma tradução que faltou
    /// aparece em inglês no meio do português, e isso é de propósito: é
    /// visível, é corrigível e não é uma tela vazia.
    static func bundle(de idioma: Idioma) -> Bundle? {
        if let caminho = Bundle.main.path(forResource: idioma.rawValue,
                                          ofType: "lproj"),
           let achado = Bundle(path: caminho) { return achado }
        // `pt-BR` empacotado como `pt`, que é como o Xcode às vezes resolve a
        // região quando só existe uma variante da língua.
        let curto = idioma.rawValue.split(separator: "-").first.map(String.init)
        if let curto, let caminho = Bundle.main.path(forResource: curto,
                                                    ofType: "lproj") {
            return Bundle(path: caminho)
        }
        return nil
    }

    /// Usado por `frase(_:)`. Não é público de propósito: quem precisa de texto
    /// chama `frase`, e não escolhe bundle na mão.
    static var bundleResolvido: Bundle {
        cofre.lock()
        defer { cofre.unlock() }
        return bundleAtual
    }

    static var idiomaResolvido: Idioma {
        cofre.lock()
        defer { cofre.unlock() }
        return idiomaAtual
    }
}

/// A chave de uma frase, montada pelo compilador.
///
/// POR QUE NÃO É `String.LocalizationValue`
/// =======================================
///
/// `String.LocalizationValue` aceita qualquer tipo interpolado e escolhe o
/// especificador conforme o tipo: `\(7217)` vira `%lld`, `\(0.5)` vira `%lf`.
/// Isso parece conveniente e é uma armadilha aqui, por dois motivos que só
/// aparecem depois de o app já estar traduzido:
///
/// 1. **Formatação de número entra pela porta dos fundos.** `%lld` faz o
///    sistema aplicar o separador de milhar do idioma, e `7217` vira `7,217`.
///    Neste projeto número tem dono (`Formato`, `Leitura.numero`); uma segunda
///    convenção nascendo dentro das frases traduzidas é dívida silenciosa.
/// 2. **A chave deixa de ser previsível.** O `ferramentas/extrair_frases.py`
///    lê o código para saber quais chaves precisam existir no catálogo, e ele
///    não tem compilador para inferir tipos. Uma chave com `%lld` no binário e
///    `%@` no catálogo não casa: a busca falha, o idioma cai no inglês, e não
///    há erro em lugar nenhum — nem no build, nem na tela.
///
/// `Frase` resolve os dois de uma vez, e não por convenção: existe **uma**
/// sobrecarga de `appendInterpolation`, e ela recebe `String`. Interpolar um
/// `Int` aqui é erro de compilação, não uma regra que alguém pode esquecer.
public struct Frase: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {

    /// O texto com `%@` no lugar de cada interpolação. É exatamente esta
    /// String que vive no `Localizable.xcstrings`.
    public let chave: String
    /// Os valores, na ordem em que apareceram.
    public let argumentos: [String]

    public init(stringLiteral valor: String) {
        chave = valor
        argumentos = []
    }

    public init(stringInterpolation interpolacao: StringInterpolation) {
        chave = interpolacao.chave
        argumentos = interpolacao.argumentos
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var chave = ""
        var argumentos: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            chave.reserveCapacity(literalCapacity + interpolationCount * 2)
            argumentos.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            chave += literal
        }

        /// A única sobrecarga que existe. É isto que faz a regra ser do
        /// compilador em vez de ser do comentário.
        public mutating func appendInterpolation(_ valor: String) {
            chave += "%@"
            argumentos.append(valor)
        }
    }
}

/// Uma frase de interface no idioma escolhido **dentro** do app.
///
/// Existe porque `Text(umaString)` não localiza nada: o SwiftUI só resolve
/// `LocalizedStringKey`, e uma `String` já montada chega pronta à tela. Todo
/// texto que o app calcula antes de exibir — erro, explicação, rótulo derivado
/// — passa por aqui, senão a troca de idioma vira meia troca: barra e botões em
/// português, mensagens em inglês.
///
/// A chave é a própria frase em inglês, igual ao resto do catálogo. Assim uma
/// tradução que falta cai no inglês legível em vez de num identificador.
public func frase(_ chave: Frase) -> String {
    let traduzida = GestorDeIdioma.bundleResolvido.localizedString(
        forKey: chave.chave, value: chave.chave, table: nil)
    return Frase.preencher(traduzida, com: chave.argumentos)
}

extension Frase {
    /// Substitui `%@` e `%n$@` pelos argumentos.
    ///
    /// **Escrito à mão em vez de `String(format:)` de propósito.** O texto
    /// destas frases contém `%` literal ("11,9% do sortimento"), e
    /// `String(format:)` leria esse `%` como início de especificador: no melhor
    /// caso sai lixo na tela, no pior o processo cai. Escapar `%` para `%%` só
    /// nas partes literais resolveria — e exigiria que a tradução também
    /// escapasse, ou seja, uma regra invisível para quem escreve português.
    ///
    /// Aqui `%` sozinho é só um por cento. Só `%@` e `%n$@` consomem argumento,
    /// e um índice fora da faixa devolve o próprio marcador em vez de estourar:
    /// uma tradução errada vira um defeito visível, nunca um crash.
    static func preencher(_ formato: String, com argumentos: [String]) -> String {
        guard !argumentos.isEmpty else { return formato }
        var saida = ""
        var proximo = 0
        var i = formato.startIndex
        while i < formato.endIndex {
            guard formato[i] == "%" else {
                saida.append(formato[i])
                i = formato.index(after: i)
                continue
            }
            var j = formato.index(after: i)
            // `%n$@`: a forma posicional, que é como uma tradução reordena os
            // argumentos sem mexer no código.
            var digitos = ""
            while j < formato.endIndex, formato[j].isNumber {
                digitos.append(formato[j])
                j = formato.index(after: j)
            }
            if !digitos.isEmpty, j < formato.endIndex, formato[j] == "$" {
                let k = formato.index(after: j)
                if k < formato.endIndex, formato[k] == "@" {
                    let indice = (Int(digitos) ?? 0) - 1
                    saida += argumentos.indices.contains(indice)
                        ? argumentos[indice] : "%\(digitos)$@"
                    i = formato.index(after: k)
                    continue
                }
            }
            if digitos.isEmpty, j < formato.endIndex, formato[j] == "@" {
                saida += proximo < argumentos.count ? argumentos[proximo] : "%@"
                proximo += 1
                i = formato.index(after: j)
                continue
            }
            saida.append("%")
            i = formato.index(after: i)
        }
        return saida
    }
}
