import SwiftUI
import UIKit

/// Câmera do sistema, embrulhada para o SwiftUI (A12).
///
/// **Por que UIKit.** O SwiftUI não tem captura de câmera nativa; `PhotosPicker`
/// cobre a fototeca e só. `UIImagePickerController` com `sourceType = .camera` é
/// a via que a Apple documenta para tirar uma foto sem construir uma sessão de
/// captura inteira — e construir uma sessão daria controle que não precisamos
/// (foco manual, exposição, vídeo) em troca de muito mais código para revisar.
///
/// **Retenção zero, que é o ponto.** A imagem sai daqui como `CGImage` em
/// memória e vai direto para o `LeitorDeArquivo`. Não passa por arquivo
/// temporário, não vai para a fototeca, não sobe para lugar nenhum. Não existe
/// caminho de disco neste arquivo — de propósito, porque o que não existe não
/// pode ser esquecido ligado.
///
/// `allowsEditing = false`: o recorte do iOS parece útil e não é. Ele devolve a
/// imagem já cortada, e o corte que o usuário faz com o dedo mudaria a cor
/// dominante que o `CorDaPeca` mede — o app estaria medindo o enquadramento, e
/// não a peça.
struct CapturaDeCamera: UIViewControllerRepresentable {
    /// Recebe a foto em memória. `nil` quando o usuário cancelou.
    let aoCapturar: (CGImage?) -> Void

    /// Falso no simulador e em aparelho sem câmera. A tela usa isto para não
    /// oferecer um botão que não abre nada.
    static var disponivel: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.allowsEditing = false
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordenador { Coordenador(aoCapturar: aoCapturar) }

    final class Coordenador: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        let aoCapturar: (CGImage?) -> Void
        init(aoCapturar: @escaping (CGImage?) -> Void) { self.aoCapturar = aoCapturar }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let imagem = info[.originalImage] as? UIImage
            // `cgImage` pode vir nulo quando a foto chega como CIImage. Nesse
            // caso redesenha uma vez, em vez de devolver nada e o usuário achar
            // que a câmera falhou.
            aoCapturar(imagem?.cgImage ?? imagem.flatMap(Self.redesenhar))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            aoCapturar(nil)
        }

        private static func redesenhar(_ ui: UIImage) -> CGImage? {
            UIGraphicsImageRenderer(size: ui.size).image { _ in
                ui.draw(in: CGRect(origin: .zero, size: ui.size))
            }.cgImage
        }
    }
}
