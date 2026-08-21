import Foundation

/// Separa um toque deliberado do começo de um scroll nos chips do formulário.
/// O limite é menor que o limiar de arrasto do sistema de propósito: na zona
/// ambígua, preservar a rolagem é mais seguro que alterar um atributo.
enum IntencaoDoToque {
    static let deslocamentoMaximo: Double = 6

    static func confirma(deslocamentoX: Double, deslocamentoY: Double) -> Bool {
        hypot(deslocamentoX, deslocamentoY) <= deslocamentoMaximo
    }
}
