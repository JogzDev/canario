import SwiftUI
import UIKit

/// Contrato público e autocontido de uma peça compartilhada.
///
/// Não leva foto, leitura de mercado, identificador de usuário nem id interno
/// do Closet. Quem recebe ganha uma nova peça local com os atributos que a
/// outra pessoa decidiu compartilhar.
struct PecaCompartilhada: Identifiable, Equatable, Sendable {
    let id = UUID()
    let nome: String
    let termoIds: [String]

    var url: URL? {
        var c = URLComponents(string: "https://jogzdev.github.io/item/")
        c?.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "name", value: nome),
            URLQueryItem(name: "terms", value: termoIds.joined(separator: ",")),
        ]
        return c?.url
    }

    init(nome: String, termoIds: [String]) {
        self.nome = String(nome.prefix(120))
        self.termoIds = Array(Set(termoIds.filter(Self.idValido))).sorted()
    }

    init?(url: URL) {
        guard url.scheme == "https", url.host == "jogzdev.github.io",
              url.path == "/item" || url.path.hasPrefix("/item/") else { return nil }
        let itens = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let valores = Dictionary(uniqueKeysWithValues: itens.map { ($0.name, $0.value ?? "") })
        guard valores["v"] == "1", let ids = valores["terms"]?.split(separator: ",").map(String.init),
              !ids.isEmpty else { return nil }
        self.init(nome: valores["name"] ?? "", termoIds: ids)
        guard !termoIds.isEmpty else { return nil }
    }

    private static func idValido(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).contains($0)
        }
    }
}

@MainActor
final class CentralDeLinksCompartilhados: ObservableObject {
    static let shared = CentralDeLinksCompartilhados()
    @Published var recebida: PecaCompartilhada?

    func receber(_ url: URL) {
        if let peca = PecaCompartilhada(url: url) { recebida = peca }
    }
}

enum ExportadorDoCloset {
    static func csv(pecas: [PecaSalva], termos: [Termo], incluirMercado: Bool) async -> URL? {
        let porId = Dictionary(uniqueKeysWithValues: termos.map { ($0.id, $0) })
        let indices: [String: IndiceSemanal]
        if incluirMercado,
           let carregados = try? await CatalogoDeIndices.shared.carregar() {
            indices = SelecaoDeEstado.porTermo(carregados)
        } else {
            indices = [:]
        }

        var linhas = [["name", "attributes", "taxonomy_ids", "favorite", "created_at"]]
        if incluirMercado {
            linhas[0].append(contentsOf: ["market_readings", "market_measured_week"])
        }
        for peca in pecas {
            let atributos = peca.termoIds.compactMap { porId[$0].map(Traducao.rotuloExibido) }
            var linha = [
                peca.nome(comRotulos: Dictionary(uniqueKeysWithValues: termos.map { ($0.id, Traducao.rotuloExibido($0)) })),
                atributos.joined(separator: " · "),
                peca.termoIds.joined(separator: "|"),
                (peca.favorita ?? false) ? "yes" : "no",
                ISO8601DateFormatter().string(from: peca.criadaEm),
            ]
            if incluirMercado {
                let leituras = peca.termoIds.compactMap { id -> String? in
                    guard let termo = porId[id], let leitura = indices[id] else { return nil }
                    let valor = leitura.indice.map { Leitura.numero($0, casas: 2, sinal: true) } ?? "unavailable"
                    return "\(Traducao.rotuloExibido(termo)): \(valor)"
                }
                let semanas = Set(peca.termoIds.compactMap { indices[$0]?.semana }).sorted()
                linha.append(leituras.joined(separator: "; "))
                linha.append(semanas.joined(separator: "; "))
            }
            linhas.append(linha)
        }
        let texto = linhas.map { $0.map(escapar).joined(separator: ",") }.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataDrobe-Closet-\(UUID().uuidString.prefix(8)).csv")
        do {
            // BOM faz Excel reconhecer UTF-8 sem destruir nomes acentuados.
            try (Data([0xEF, 0xBB, 0xBF]) + Data(texto.utf8)).write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    private static func escapar(_ valor: String) -> String {
        "\"\(valor.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum CartaoCompartilhavel {
    @MainActor
    static func imagem(nome: String, atributos: [String]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1350))
        return renderer.image { contexto in
            UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1).setFill()
            contexto.fill(CGRect(x: 0, y: 0, width: 1080, height: 1350))
            let titulo = NSAttributedString(string: nome.isEmpty ? "A piece from my Closet" : nome,
                attributes: [.font: UIFont.systemFont(ofSize: 72, weight: .bold),
                             .foregroundColor: UIColor.black])
            titulo.draw(in: CGRect(x: 90, y: 210, width: 900, height: 250))
            let detalhe = NSAttributedString(string: atributos.joined(separator: "  ·  "),
                attributes: [.font: UIFont.systemFont(ofSize: 40, weight: .regular),
                             .foregroundColor: UIColor.darkGray])
            detalhe.draw(in: CGRect(x: 90, y: 510, width: 900, height: 430))
            NSAttributedString(string: "DATADROBE", attributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor.black,
            ]).draw(at: CGPoint(x: 90, y: 1160))
        }
    }
}

struct FolhaDeAtividades: UIViewControllerRepresentable {
    let itens: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: itens, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ReceberPecaCompartilhada: View {
    let peca: PecaCompartilhada
    @Environment(\.dismiss) private var dismiss
    @State private var nome: String
    @State private var termos: [Termo] = []
    @State private var carregando = true
    @State private var erro: String?

    init(peca: PecaCompartilhada) {
        self.peca = peca
        _nome = State(initialValue: peca.nome)
    }

    private var reconhecidos: [Termo] { termos.filter { peca.termoIds.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shared item") {
                    TextField("Clothing name", text: $nome)
                    if carregando { ProgressView() }
                    ForEach(reconhecidos) { termo in
                        Label(Traducao.rotuloExibido(termo), systemImage: "checkmark.circle")
                    }
                }
                if let erro { Text(erro).foregroundStyle(.secondary) }
                Section {
                    Text("Saving creates a new item in your Closet. The sender's photo and account are never included in the link.")
                        .font(Tokens.Fonte.miudo)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add to Closet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { salvar() }.disabled(reconhecidos.isEmpty)
                }
            }
        }
        .task {
            do { termos = try await CatalogoDeTermos.shared.carregar() }
            catch { erro = "The taxonomy is unavailable right now. Try again when you are online." }
            carregando = false
        }
    }

    private func salvar() {
        Task {
            let nova = PecaSalva(
                apelido: nome.trimmingCharacters(in: .whitespacesAndNewlines),
                termoIds: reconhecidos.map(\.id))
            if await PecasSalvas.shared.salvar(nova) { dismiss() }
            else { erro = "Your Closet is full (\(PecasSalvas.teto))." }
        }
    }
}
