import SwiftUI

struct MenuLateral: View {
    let fechar: () -> Void
    let escolher: (String) -> Void

    private let itens = ["Favorites", "Account", "Terms", "Settings", "Privacy", "Q&A"]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.08)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: fechar)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Button(action: fechar) {
                        ZStack {
                            Vidro(forma: Circle())
                            Image(systemName: "xmark")
                                .font(.system(size: 29, weight: .medium))
                                .foregroundStyle(Tokens.Cor.noite)
                        }
                        .frame(width: 62, height: 62)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close menu")
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(itens, id: \.self) { item in
                            Button(item) { escolher(item) }
                                .font(.system(size: 29, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 104)
                        }
                    }
                    .padding(.top, 34)
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.trailing, 26)
                .frame(width: geo.size.width * 0.79)
                .frame(maxHeight: .infinity)
                .background(Tokens.Cor.azulMarca)
                .shadow(color: .black.opacity(0.24), radius: 22, x: 10)
            }
            .ignoresSafeArea()
        }
    }
}
