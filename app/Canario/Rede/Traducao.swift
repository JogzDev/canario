import Foundation

/// Tradução da busca do usuário para termos da taxonomia (§11).
///
/// Está num arquivo próprio, e não dentro da tela, por dois motivos: é a regra
/// mais fácil de violar sem perceber ("a barra de busca do app nunca vira
/// filtro de texto cru") e é a única lógica do app que merece teste — o resto
/// é layout e leitura de rede.
enum Traducao {

    /// Copy de apresentação até a migração para String Catalog. Os ids e os
    /// rótulos gravados no servidor continuam imutáveis: acento é assunto da
    /// interface, não uma migração de série histórica.
    private static let rotulosCorrigidos: [String: String] = [
        // Category
        "vestido": "Dress", "saia": "Skirt",
        "blusa_top": "Tops & T-shirts", "camisa": "Shirt",
        "calca": "Pants", "short": "Shorts & bermudas",
        "casaco_jaqueta": "Coats & jackets", "macacao": "Jumpsuit",
        // Pattern
        "liso": "Solid", "floral": "Floral", "listra": "Stripes",
        "animal_print": "Animal print", "xadrez": "Checks & plaid",
        "geometrica": "Graphic & geometric",
        // "Conversational print" é o termo do mercado e não sobreviveu ao
        // teste mais simples: o JP, que conhece o assunto, não soube dizer o
        // que era. Um rótulo que precisa de aula não é rótulo. "Illustrated"
        // diz a coisa em uma palavra e faz a fronteira certa com animal print,
        // que é PELE de bicho e não desenho de bicho.
        "conversacional": "Illustrated prints",
        // Material
        "algodao": "Cotton", "linho": "Linen", "jeans": "Denim", "couro": "Leather",
        "malha": "Knit & crochet", "trico_croche": "Knit & crochet",
        "viscose_fluido": "Viscose & fluid fabrics",
        // Length, silhouette and waist
        "curto": "Short", "midi": "Midi", "longo": "Long",
        "flare": "Flared & A-line", "reta_wide": "Straight & wide-leg",
        "cintura_alta": "High rise", "cintura_media": "Mid rise",
        "cintura_baixa": "Low rise",
        // Aesthetic
        "basico": "Essential", "romantico": "Romantic",
        "boho_artesanal": "Boho & artisanal", "alfaiataria": "Tailored",
        "festa_brilho": "Party & shine",
        // Color families
        "preto": "Black", "branco_cru": "White & cream", "cinza": "Gray",
        "azul": "Blue", "verde": "Green", "lilas_roxo": "Purple & lilac",
        "vermelho_rosa": "Red & pink", "amarelo_laranja": "Yellow & orange",
        "terrosos": "Earth tones", "outras_cores": "Other colors",
    ]

    static func rotuloExibido(_ termo: Termo) -> String {
        rotulosCorrigidos[termo.id] ?? termo.rotulo
    }

    /// Rótulo de um id quando a resposta do servidor não traz o `Termo`
    /// completo (por exemplo, `categoria_usada` no cálculo do cluster).
    static func rotuloExibido(id: String, fallback: String? = nil) -> String {
        rotulosCorrigidos[id] ?? fallback ?? id
    }

    /// `trico_croche` era uma segunda opção visual para a mesma família que o
    /// formulário já chamava de Knit. O motor histórico pode continuar lendo o
    /// alias, mas escolhas novas e peças sincronizadas usam um id canônico.
    static func idsCanonicos(_ ids: [String]) -> [String] {
        var vistos: Set<String> = []
        return ids.compactMap {
            let canonico = $0 == "trico_croche" ? "malha" : $0
            return vistos.insert(canonico).inserted ? canonico : nil
        }
    }

    /// Dimensões cujo rótulo pede JULGAMENTO em vez de observação.
    ///
    /// "Dress", "Black", "Midi" a pessoa responde olhando. "Romantic" ela
    /// responde opinando -- e opinião varia entre duas pessoas com a mesma peça
    /// na mão, o que envenena o dado na origem.
    private static let dimensoesQuePedemPista: Set<String> = ["estetica"]

    // Estampa ficou de fora, e a tentativa de incluí-la é a razão deste
    // comentário. `palavras_en` é vocabulário do MATCHER, não legenda: as de
    // `conversacional` são "conversational print | novelty print | object
    // print | fruit print…", e as três primeiras devolveriam na tela
    // exatamente o jargão que o rótulo novo existe para não usar. Legenda de
    // estampa tem casa própria no CSV -- a coluna `exemplo` --, que o servidor
    // ainda não expõe e o `Termo` ainda não carrega.

    /// O que OLHAR para responder, quando o rótulo sozinho pede gosto.
    ///
    /// O JP: "não é muito amigável com o usuário fazer ele descrever o que é
    /// uma peça romântica". Ele tem razão, e a taxonomia já carrega a resposta:
    /// `palavras_en` de `romantico` é `romantic|ruffle|lace|puff sleeve|
    /// broderie`. Babado, renda, manga bufante — evidência que se vê, não
    /// estilo que se declara.
    ///
    /// O app **já baixava** esse campo (`Supabase.swift` pede `palavras_en`
    /// desde sempre) e o descartava na tela. Aqui ele vira a segunda linha do
    /// chip. Isso não conserta a taxonomia; conserta a pergunta feita a quem
    /// não conhece a taxonomia.
    ///
    /// Três itens no máximo: a quarta palavra faz o chip virar parágrafo, e
    /// quem precisa de quatro pistas não vai decidir por causa da quarta.
    static func pistaDoTermo(_ termo: Termo) -> String? {
        guard dimensoesQuePedemPista.contains(termo.dimensao) else { return nil }
        let rotulo = rotuloExibido(termo).lowercased()
        let palavras = (termo.palavrasEn ?? "")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { palavra in
                guard !palavra.isEmpty else { return false }
                // O sinônimo que só repete o próprio rótulo não é pista -- e
                // "repetir" inclui a variação da mesma palavra. A comparação
                // por conteúdo deixava passar "bohemian" ao lado de "Boho" e
                // "tailoring" ao lado de "Tailored": duas linhas gastas para
                // não dizer nada. Radical de quatro letras em comum já é a
                // mesma palavra para efeito de pista.
                return !Self.compartilhaRadical(palavra.lowercased(), com: rotulo)
            }
        guard !palavras.isEmpty else { return nil }
        return palavras.prefix(3).joined(separator: " · ")
    }

    /// Duas palavras são a mesma para efeito de legenda quando começam igual
    /// por pelo menos três letras E esse começo é pelo menos metade da menor
    /// delas. As duas condições existem juntas por casos reais opostos:
    /// `boho` e `bohemian` só compartilham três letras e são obviamente a
    /// mesma palavra (3 de 4 letras de `boho`), enquanto `sequin` e `shine`
    /// compartilham uma e não são.
    ///
    /// Isto vale para legenda e **só** para legenda. O matcher do §11 continua
    /// exigindo palavra inteira, porque lá radical em comum é exatamente o
    /// erro que faz `reta` casar `preta`.
    private static func compartilhaRadical(_ palavra: String,
                                           com rotulo: String) -> Bool {
        rotulo.split(whereSeparator: { !$0.isLetter }).contains { pedaco in
            let a = Array(palavra), b = Array(pedaco.lowercased())
            let menor = min(a.count, b.count)
            var iguais = 0
            while iguais < menor, a[iguais] == b[iguais] { iguais += 1 }
            return iguais >= 3 && iguais * 2 >= menor
        }
    }

    static func rotuloDaDimensao(_ dimensao: String) -> String {
        [
            "categoria": "Category",
            "cor": "Color",
            "estampa": "Pattern",
            "tecido": "Material",
            "estetica": "Style",
            "comprimento": "Length",
            "silhueta": "Silhouette",
            "cintura": "Waist",
        ][dimensao] ?? dimensao.capitalized
    }

    /// Nome que a pessoa usou, quando ele é mais claro que o rótulo interno.
    ///
    /// A taxonomia agrupa poá dentro de `geometrica`, porque o motor precisa de
    /// uma série com volume. Isso não obriga a interface a responder "Geométrica
    /// e étnica" para quem escreveu "vestido de bolinha". O cálculo continua
    /// no id aprovado; só a conversa preserva a palavra de quem pesquisou.
    static func rotuloAmigavel(_ termo: Termo, na consulta: String) -> String {
        let palavras = Set(normalizar(consulta)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
        if termo.id == "geometrica" {
            if !palavras.isDisjoint(with: ["bolinha", "bolinhas", "poa"]) {
                return "Polka dot"
            }
        }
        return rotuloExibido(termo)
    }

    /// Descrição da peça em linguagem de busca, sem expor ids ou agrupamentos
    /// editoriais. O resultado é apenas apresentação; os ids não mudam.
    static func descricaoAmigavel(_ termos: [Termo], consulta: String) -> String {
        termos.map { rotuloAmigavel($0, na: consulta) }.joined(separator: " · ")
    }

    /// Normaliza para comparação: sem acento, minúsculas, sem espaço nas pontas.
    static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Quebra um candidato em partes independentes.
    ///
    /// Metade dos rótulos da taxonomia é ENUMERAÇÃO, não expressão: "Casaco e
    /// jaqueta", "Blusa e top", "Tricô e crochê", "Branco e cru". Exigir todas
    /// as palavras nesses casos faz a busca mais óbvia falhar — quem digita
    /// "casaco" não encontrava "Casaco e jaqueta".
    ///
    /// Já "wide leg" e "manga bufante" são expressões: as palavras andam
    /// juntas e só valem juntas. A diferença é o conectivo.
    private static func partes(_ candidato: String) -> [[String]] {
        let normalizado = normalizar(candidato)
        // Separadores de enumeração; o resto continua sendo frase.
        let pedacos = normalizado
            .replacingOccurrences(of: " e ", with: "|")
            .replacingOccurrences(of: "/", with: "|")
            .split(separator: "|")
        return pedacos.compactMap { pedaco in
            let palavras = pedaco
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            return palavras.isEmpty ? nil : palavras
        }
    }

    /// Casa a string do usuário contra rótulos, ids e sinônimos.
    ///
    /// Casa por PALAVRA INTEIRA, nunca por pedaço de palavra. É a mesma
    /// regressão que o `matcher.py` carrega do lado do coletor: "reta" não pode
    /// casar "preta", senão uma peça preta entra como silhueta reta.
    static func casa(_ consulta: String, _ termo: Termo) -> Bool {
        let alvo = normalizar(consulta)
        guard !alvo.isEmpty else { return false }
        let palavrasDaConsulta = Set(alvo.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
        guard !palavrasDaConsulta.isEmpty else { return false }

        // O rótulo exibido entra no vocabulário: a tela mostra "Stripes" e a
        // taxonomia só conhece "stripe|striped". Sem isto, o app não encontra
        // seis dos próprios rótulos -- inclusive dois que ele mesmo sugere.
        for candidato in termo.termosDeBusca + [rotuloExibido(termo)] {
            for palavrasDaParte in partes(candidato) {
                // Dentro de uma parte, é expressão: todas as palavras contam.
                if palavrasDaParte.allSatisfy({ palavrasDaConsulta.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    /// Todos os termos que a consulta alcança, na ordem em que vieram.
    static func termos(para consulta: String, em todos: [Termo]) -> [Termo] {
        todos.filter { casa(consulta, $0) }
    }
}

/// Ordem e pertinência das perguntas do formulário depois que a categoria é
/// conhecida. Uma medida que não se aplica não é apenas ruído visual: sugere
/// que o sistema entendeu a peça quando não entendeu.
enum FormularioDaPeca {
    static func dimensoesPermitidas(categorias: Set<String>) -> Set<String> {
        // Cor, estampa, tecido e estética não dependem de categoria: uma peça
        // cinza é cinza antes de alguém dizer se é saia ou casaco. Elas ficavam
        // escondidas até a categoria ser escolhida, e isso mordia justamente na
        // hora pior -- quando a leitura automática falha, a pessoa abre o
        // formulário para preencher à mão e encontra só a lista de categorias.
        //
        // Pior ainda em `podar`: marcar a cor antes da categoria apagava a cor.
        //
        // Condicional é só o que a categoria de fato governa -- comprimento,
        // silhueta e cintura --, que é o que a Bianca descreveu: "Todas também
        // terão Padrão e Material! O que tem que aparecer condicional é estilo
        // da calça e por aí vai."
        var resultado: Set<String> = [
            "categoria", "cor", "estampa", "tecido", "estetica"
        ]
        if !categorias.isDisjoint(with: ["vestido", "saia"]) {
            resultado.insert("comprimento")
        }
        if categorias.contains("calca") {
            resultado.insert("silhueta")
        }
        if !categorias.isDisjoint(with: ["calca", "short", "saia"]) {
            resultado.insert("cintura")
        }
        return resultado
    }

    static func temCategoria(_ marcados: Set<String>, termos: [Termo]) -> Bool {
        termos.contains { $0.dimensao == "categoria" && marcados.contains($0.id) }
    }

    /// Marca ou desmarca um termo respeitando a taxonomia.
    ///
    /// Até 19/08/2026 o formulário só fazia `insert`/`remove` no conjunto, e
    /// com isso deixava montar peça que não existe: `vestido` **e** `calca`
    /// como categoria, `floral` **e** `xadrez` como estampa, `midi` **e**
    /// `longo` como comprimento. A taxonomia sempre soube disso -- o campo
    /// `exclusiva` vem do banco e chega ao app em `Termo` --, mas nada o lia.
    ///
    /// Dimensões exclusivas hoje: categoria, cintura, comprimento, estampa,
    /// silhueta. Múltiplas: cor, estética, tecido. O app não guarda essa lista:
    /// lê de cada termo, para não virar uma segunda cópia que diverge.
    static func alternar(_ termo: Termo, em marcados: Set<String>,
                         termos: [Termo]) -> Set<String> {
        var novo = marcados
        if novo.contains(termo.id) {
            novo.remove(termo.id)
        } else {
            if termo.exclusiva {
                // Trocar de valor, não acumular: marcar `longo` com `midi`
                // marcado significa que a pessoa mudou de ideia.
                novo.subtract(termos.lazy
                    .filter { $0.dimensao == termo.dimensao }
                    .map(\.id))
            }
            novo.insert(termo.id)
        }
        return podar(novo, termos: termos)
    }

    /// Tira do conjunto o que a categoria atual não comporta.
    ///
    /// O outro defeito da mesma tela, e mais silencioso: as dimensões visíveis
    /// dependem da categoria (comprimento só aparece em vestido e saia; cintura
    /// em calça, short e saia), mas quem escolhia `vestido`, marcava
    /// comprimento `midi` e depois trocava para `calca` continuava com `midi`
    /// no conjunto. A linha sumia da tela e o atributo seguia para o relatório
    /// -- uma calça com comprimento de vestido, que ninguém escolheu e ninguém
    /// via.
    static func podar(_ marcados: Set<String>, termos: [Termo]) -> Set<String> {
        guard !termos.isEmpty else { return marcados }
        let categorias = Set(termos.lazy
            .filter { $0.dimensao == "categoria" && marcados.contains($0.id) }
            .map(\.id))
        let permitidas = dimensoesPermitidas(categorias: categorias)
        let porId = Dictionary(termos.map { ($0.id, $0) },
                               uniquingKeysWith: { primeiro, _ in primeiro })
        var canonicos = marcados
        if canonicos.remove("trico_croche") != nil { canonicos.insert("malha") }
        return canonicos.filter { id in
            // Id fora da taxonomia carregada não é podado: pode ser termo novo
            // que este app ainda não conhece, e apagar seria perder escolha.
            guard let termo = porId[id] else { return true }
            return permitidas.contains(termo.dimensao)
        }
    }
}
