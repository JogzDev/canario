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
        ("Pattern", ["liso", "listra", "floral", "xadrez", "geometrica",
                     "animal_print", "conversacional"]),
        ("Print motif", ["tomate_print", "cereja_print", "morango_print",
                         "banana_print", "abacaxi_print", "melancia_print"]),
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

    private static func termo(_ id: String) -> Termo {
        Termo(id: id, rotulo: id, dimensao: dimensao(de: id), exclusiva: false,
              sinonimos: nil, semPernaBusca: nil, palavrasPt: nil, palavrasEn: nil)
    }

    private static func dimensao(de id: String) -> String {
        grupos.first { $0.1.contains(id) }?.0 == "Color" ? "cor" : "outra"
    }
}
