import SwiftUI
import UIKit

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
                NomeCompartilhavel.resolver(peca, termos: termos),
                atributos.joined(separator: " · "),
                peca.termoIds.joined(separator: "|"),
                (peca.favorita ?? false) ? "yes" : "no",
                ISO8601DateFormatter().string(from: peca.criadaEm),
            ]
            if incluirMercado {
                let leituras = peca.termoIds.compactMap { id -> String? in
                    guard let termo = porId[id], let leitura = indices[id] else { return nil }
                    let valor = leitura.indice.map { Leitura.numero($0, casas: 2, sinal: true) } ?? "unavailable"
                    return frase("\(Traducao.rotuloExibido(termo)): \(valor)")
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
    static func imagem(nome: String, atributos: [String], miniatura: UIImage? = nil) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1350))
        return renderer.image { contexto in
            UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1).setFill()
            contexto.fill(CGRect(x: 0, y: 0, width: 1080, height: 1350))
            let temFoto = miniatura != nil
            if let miniatura {
                let destino = retanguloAspectFit(
                    tamanho: miniatura.size,
                    dentroDe: CGRect(x: 90, y: 80, width: 900, height: 650))
                miniatura.draw(in: destino)
            }
            let titulo = NSAttributedString(string: nome.isEmpty ? "A piece from my Closet" : nome,
                attributes: [.font: UIFont.systemFont(ofSize: 72, weight: .bold),
                             .foregroundColor: UIColor.black])
            titulo.draw(in: CGRect(x: 90, y: temFoto ? 760 : 210, width: 900, height: 190))
            let detalhe = NSAttributedString(string: atributos.joined(separator: "  ·  "),
                attributes: [.font: UIFont.systemFont(ofSize: 40, weight: .regular),
                             .foregroundColor: UIColor.darkGray])
            detalhe.draw(in: CGRect(x: 90, y: temFoto ? 930 : 510, width: 900,
                                    height: temFoto ? 180 : 430))
            NSAttributedString(string: "DATADROBE", attributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor.black,
            ]).draw(at: CGPoint(x: 90, y: 1160))
        }
    }

    private static func retanguloAspectFit(tamanho: CGSize, dentroDe limite: CGRect) -> CGRect {
        guard tamanho.width > 0, tamanho.height > 0 else { return limite }
        let escala = min(limite.width / tamanho.width, limite.height / tamanho.height)
        let novo = CGSize(width: tamanho.width * escala, height: tamanho.height * escala)
        return CGRect(x: limite.midX - novo.width / 2,
                      y: limite.midY - novo.height / 2,
                      width: novo.width, height: novo.height)
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
            catch { erro = frase("The taxonomy is unavailable right now. Try again when you are online.") }
            carregando = false
        }
    }

    private func salvar() {
        Task {
            let nova = PecaSalva(
                apelido: nome.trimmingCharacters(in: .whitespacesAndNewlines),
                termoIds: reconhecidos.map(\.id))
            if await PecasSalvas.shared.salvar(nova) { dismiss() }
            else { erro = frase("Your Closet is full (\(String(PecasSalvas.teto))).") }
        }
    }
}
