import SwiftUI

/// A folha de referência dos ícones da taxonomia.
///
/// Não é tela de produto: abre só com `-CanarioAmostraDeIcones` e existe para
/// olhar o conjunto inteiro de uma vez. Ícone se aprova comparando, não um a
/// um — é lado a lado que aparece o glifo mais gordo que os vizinhos, a
/// categoria que ficou parecida com outra e o rótulo que não cabe.
///
/// A cobertura de termos é garantida pelo portão
/// `coletor/teste_icones_da_taxonomia.py`, não por esta lista. Se um termo
/// novo entrar na taxonomia e não aparecer aqui, o portão acusa antes.
struct AmostraDeIcones: View {

    private static let grupos: [(String, [String])] = [
        ("Category", ["blusa_top", "camisa", "vestido", "saia",
                      "calca", "short", "casaco_jaqueta", "macacao"]),
        ("Color", ["preto", "cinza", "branco_cru", "terrosos", "outras_cores",
                   "vermelho_rosa", "amarelo_laranja", "verde", "azul",
                   "lilas_roxo"]),
        // Print motif não é mais seção: os seis motivos viraram uma família
        // só, "Illustrated prints", dentro de Pattern. Os glifos de fruta
        // continuam existindo porque os termos continuam existindo no dado --
        // eles é que casam a estampa de tomate da Farm com a de outra marca --,
        // só não são mais seis botões para a pessoa escolher.
        ("Pattern", ["liso", "listra", "floral", "xadrez", "geometrica",
                     "animal_print", "conversacional"]),
        ("Print motif · dado, não escolha", ["tomate_print", "cereja_print",
                         "morango_print", "banana_print", "abacaxi_print",
                         "melancia_print"]),
        ("Style", ["romantico", "basico", "boho_artesanal", "alfaiataria",
                   "festa_brilho"]),
        ("Material", ["algodao", "jeans", "malha", "couro", "linho",
                      "viscose_fluido"]),
        ("Length", ["curto", "midi", "longo"]),
        ("Silhouette", ["flare", "reta_wide"]),
        ("Rise", ["cintura_alta", "cintura_media", "cintura_baixa"]),
    ]

    /// As três primeiras cores entram marcadas, com posição, porque a marca de
    /// prioridade é justamente o que precisa ser aprovado olhando: ela tem que
    /// sobreviver tanto sobre preto quanto sobre branco e cru.
    private static let prioridadeDaAmostra: [String: Int] = [
        "vermelho_rosa": 1, "azul": 2, "branco_cru": 3,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // O anel azul não é um estilo diferente de botão: é o
                    // estado "marcado". Na folha ele aparece em um item por
                    // seção porque é assim que a tela chega depois da leitura
                    // da Luna -- com o palpite dela já marcado e tudo pronto
                    // para a pessoa corrigir.
                    Text("The blue ring means selected — on the real screen it "
                         + "arrives on whatever Luna read, ready to be changed.")
                        .font(.footnote)
                        .foregroundStyle(Tokens.Cor.tintaFraca)

                    ForEach(Self.grupos, id: \.0) { titulo, ids in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(titulo)
                                .font(.system(size: 17, weight: .bold,
                                              design: .rounded))
                            FlowLayout(espaco: 12) {
                                ForEach(ids, id: \.self) { id in
                                    BotaoDeAtributo(
                                        termo: Self.termo(id),
                                        ativo: ativo(id),
                                        prioridade: Self.prioridadeDaAmostra[id],
                                        acao: {})
                                }
                            }
                            Divider()
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Icon sheet")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Um marcado por grupo, para o anel de seleção aparecer na folha.
    private func ativo(_ id: String) -> Bool {
        Self.prioridadeDaAmostra[id] != nil
            || ["blusa_top", "listra", "tomate_print", "romantico",
                "jeans", "midi", "flare", "cintura_alta"].contains(id)
    }

    /// A folha monta `Termo`s à mão porque não tem rede. No app eles vêm do
    /// servidor com `palavras_en` preenchido, que é de onde sai a legenda de
    /// Style — por isso as cinco de estética entram aqui com as palavras
    /// reais do CSV: sem elas a folha mostraria a grade sem as legendas que
    /// existem na tela de verdade.
    private static let palavrasDeEstetica: [String: String] = [
        "basico": "basic|essential|minimal",
        "romantico": "romantic|ruffle|lace|puff sleeve|broderie",
        "boho_artesanal": "boho|bohemian|fringe|embroidered|macrame|crochet trim",
        "alfaiataria": "tailoring|tailored|suiting",
        "festa_brilho": "party|sequin|lurex|sparkle|metallic",
    ]

    private static func termo(_ id: String) -> Termo {
        Termo(id: id, rotulo: id, dimensao: dimensao(de: id), exclusiva: false,
              sinonimos: nil, semPernaBusca: nil, palavrasPt: nil,
              palavrasEn: palavrasDeEstetica[id])
    }

    private static func dimensao(de id: String) -> String {
        if palavrasDeEstetica[id] != nil { return "estetica" }
        return grupos.first { $0.1.contains(id) }?.0 == "Color" ? "cor" : "outra"
    }
}
