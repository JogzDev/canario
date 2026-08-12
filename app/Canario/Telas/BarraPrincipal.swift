import SwiftUI

struct BarraPrincipal: View {
    @Binding var aba: Raiz.Aba
    let buscar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                item(.adicionar, "Add", "hanger")
                item(.armario, "Closet", "tshirt.fill")
                item(.dados, "Analytics", "chart.line.uptrend.xyaxis")
            }
            .padding(5)
            .background { Vidro(raio: 34) }

            Button(action: buscar) {
                ZStack {
                    Vidro(forma: Circle())
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Tokens.Cor.noite)
                }
                .frame(width: 62, height: 62)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
        }
    }

    private func item(_ destino: Raiz.Aba, _ titulo: String, _ simbolo: String) -> some View {
        Button { aba = destino } label: {
            VStack(spacing: 2) {
                Image(systemName: simbolo)
                    .font(.system(size: 22, weight: .semibold))
                Text(titulo)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(aba == destino ? Color.accentColor : Tokens.Cor.noite)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(aba == destino ? Color.white.opacity(0.27) : .clear,
                        in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(aba == destino ? .isSelected : [])
    }
}
