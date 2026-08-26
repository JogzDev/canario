import Foundation

/// Quantas análises visuais **este aparelho** pediu hoje.
///
/// POR QUE NÃO É "QUANTAS RESTAM"
/// ==============================
///
/// O teto do servidor é contado por `sha256(salt : IP)` — por **rede**, não por
/// aparelho nem por conta. Duas pessoas no mesmo Wi-Fi dividem as 12; quem troca
/// de Wi-Fi para 4G recebe outras 12; atrás do CGNAT de uma operadora, divide
/// com estranhos.
///
/// Então "você tem 3 restantes" é uma conta que o app **não tem como fazer**.
/// Ele sabe o que ele mesmo pediu; não sabe o que a rede pediu. Subtrair seria
/// prometer um saldo que pode não existir, e a pessoa descobriria a mentira
/// justamente no momento em que fosse bloqueada.
///
/// Por isso este contador expõe dois fatos e nenhuma subtração: quantas **este
/// aparelho** pediu, e qual é o teto **da rede**. Quem lê tira a conclusão com
/// a incerteza à vista, que é o que a regra 2 pede.
///
/// ## Por que só aparece perto do fim
///
/// Doze análises num dia é muito para quase todo mundo. Um contador permanente
/// seria peso visual constante para um evento raro — exatamente o que a revisão
/// de UX pediu para tirar. Ele fica calado até valer a pena avisar.
///
/// ## Por que arquivo e não UserDefaults
///
/// O `PrivacyInfo.xcprivacy` declara, por varredura, que o app não toca em
/// `UserDefaults`. Isso o dispensa de declarar API de motivo obrigatório, e não
/// vale a pena perder essa propriedade por um contador.
public struct AnalisesDeHoje: Codable, Equatable, Sendable {
    public let dia: String
    public var quantidade: Int

    public init(dia: String, quantidade: Int) {
        self.dia = dia
        self.quantidade = quantidade
    }
}

public enum ContadorDeAnalises {
    /// O mesmo 12 de `_reservar_analise_visual`. Se um mudar, o outro mente.
    public static let tetoPorRede = 12

    /// Abaixo disto a tela não diz nada. Três de folga é aviso com tempo de
    /// reagir, e não alarme para quem analisou duas peças.
    public static let avisarAPartirDe = 9

    /// O dia de São Paulo, que é o mesmo que o servidor usa para virar a
    /// contagem. Usar o fuso do aparelho faria o app zerar em hora diferente
    /// do teto que ele descreve.
    public static func dia(_ agora: Date = Date()) -> String {
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone(identifier: "America/Sao_Paulo")
            ?? TimeZone(secondsFromGMT: -3 * 3600)!
        let partes = calendario.dateComponents([.year, .month, .day], from: agora)
        return String(format: "%04d-%02d-%02d",
                      partes.year ?? 0, partes.month ?? 0, partes.day ?? 0)
    }

    /// Soma uma análise, zerando quando o dia virou.
    public static func registrar(_ atual: AnalisesDeHoje?,
                                 agora: Date = Date()) -> AnalisesDeHoje {
        let hoje = dia(agora)
        guard let atual, atual.dia == hoje else {
            return AnalisesDeHoje(dia: hoje, quantidade: 1)
        }
        return AnalisesDeHoje(dia: hoje, quantidade: atual.quantidade + 1)
    }

    /// A linha que a tela mostra, ou `nil` para ficar calada.
    ///
    /// Diz o que este aparelho fez e qual é o teto da rede, **sem subtrair**.
    public static func aviso(_ atual: AnalisesDeHoje?,
                             agora: Date = Date()) -> String? {
        guard let atual, atual.dia == dia(agora),
              atual.quantidade >= avisarAPartirDe else { return nil }
        let plural = atual.quantidade == 1 ? "" : "s"
        return "\(atual.quantidade) analysis\(plural.isEmpty ? "" : "es") "
             + "from this iPhone today. The daily cap is \(tetoPorRede), "
             + "shared by everyone on the same network."
    }
}

/// Guarda a contagem entre aberturas do app.
///
/// Arquivo, e não `UserDefaults`: o `PrivacyInfo.xcprivacy` declara por
/// varredura que o app não toca nele, e isso o dispensa de declarar API de
/// motivo obrigatório. Não vale perder essa propriedade por um contador.
///
/// Falha de leitura ou escrita é engolida de propósito. Este número orienta uma
/// frase de aviso; quem de fato barra a chamada é o servidor. Um contador que
/// derruba a análise seria pior que contador nenhum.
public actor RegistroDeAnalises {
    public static let shared = RegistroDeAnalises()

    private let arquivo: URL?
    private var memoria: AnalisesDeHoje?

    public init(arquivo: URL? = nil) {
        if let arquivo {
            self.arquivo = arquivo
        } else {
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.arquivo = base?.appendingPathComponent("analises_de_hoje.json")
        }
    }

    private func carregado() -> AnalisesDeHoje? {
        if let memoria { return memoria }
        guard let arquivo, let dados = try? Data(contentsOf: arquivo) else {
            return nil
        }
        memoria = try? JSONDecoder().decode(AnalisesDeHoje.self, from: dados)
        return memoria
    }

    /// Soma uma análise e devolve o estado novo.
    @discardableResult
    public func registrar(agora: Date = Date()) -> AnalisesDeHoje {
        let novo = ContadorDeAnalises.registrar(carregado(), agora: agora)
        memoria = novo
        if let arquivo, let dados = try? JSONEncoder().encode(novo) {
            try? dados.write(to: arquivo, options: .atomic)
        }
        return novo
    }

    /// A frase de aviso, ou `nil` quando ainda não é hora de avisar.
    public func aviso(agora: Date = Date()) -> String? {
        ContadorDeAnalises.aviso(carregado(), agora: agora)
    }
}

/// Escolha persistente para a leitura visual. O primeiro uso continua sendo
/// consentimento informado; depois disso o app respeita a escolha até a pessoa
/// alterá-la em Settings. Arquivo próprio mantém a mesma política de não usar
/// `UserDefaults` adotada pelo contador acima.
public enum PreferenciaDaAnaliseVisual: String, Codable, Sendable {
    case perguntar
    case nuvem
    case aparelho
}

public actor PreferenciasDaAnaliseVisual {
    public static let shared = PreferenciasDaAnaliseVisual()

    private let arquivo: URL?
    private var memoria: PreferenciaDaAnaliseVisual?

    public init(arquivo: URL? = nil) {
        if let arquivo {
            self.arquivo = arquivo
        } else {
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.arquivo = base?.appendingPathComponent(
                "preferencia_analise_visual.json")
        }
    }

    public func preferencia() -> PreferenciaDaAnaliseVisual {
        if let memoria { return memoria }
        guard let arquivo, let dados = try? Data(contentsOf: arquivo),
              let valor = try? JSONDecoder().decode(
                PreferenciaDaAnaliseVisual.self, from: dados) else {
            memoria = .perguntar
            return .perguntar
        }
        memoria = valor
        return valor
    }

    public func definir(_ valor: PreferenciaDaAnaliseVisual) {
        memoria = valor
        guard let arquivo, let dados = try? JSONEncoder().encode(valor) else { return }
        try? dados.write(to: arquivo, options: .atomic)
    }
}
