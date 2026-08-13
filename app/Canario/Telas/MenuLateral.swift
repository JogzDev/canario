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

                Tokens.Cor.azulMarca
                    .frame(width: geo.size.width * 0.79)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(itens, id: \.self) { item in
                            Button(item) { escolher(item) }
                                .font(.system(size: 29, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 104)
                        }
                    }
                    // O controle de fechar pertence à raiz e ocupa a mesma
                    // posição do ellipsis. A lista começa abaixo dele.
                    .padding(.top, 100)
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.trailing, 26)
                .frame(width: geo.size.width * 0.79)
                .frame(maxHeight: .infinity)
                .shadow(color: .black.opacity(0.24), radius: 22, x: 10)
            }
        }
    }
}
