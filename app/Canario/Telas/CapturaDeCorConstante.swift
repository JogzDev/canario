import AVFoundation
import SwiftUI
import UIKit

/// Captura com **cor constante** da Apple: a foto sai com a cor da peça, e não
/// com a cor da luz da sala.
///
/// POR QUE ISTO EXISTE
/// ===================
///
/// O `CorDaPeca` mede a cor dominante do pixel e pré-marca a dimensão `cor` do
/// formulário. Isso funciona quando o pixel é confiável, e o pixel de uma foto
/// comum não é: o balanço de branco automático do iPhone tenta adivinhar a
/// temperatura da luz e a corrige inteira. Sob lâmpada quente uma blusa branca
/// sai bege; sob LED frio a mesma blusa sai azulada; ao lado da janela ao
/// entardecer ela sai rosada. A peça não mudou, e o número que o app grava no
/// Closet mudou três vezes.
///
/// Era exatamente a ressalva levantada na revisão de 05/09: ângulo e iluminação
/// do ambiente alteram a percepção de cor da peça. A moldura neutra (ver
/// `SubstratoDaPeca`) resolve a metade da percepção humana; esta resolve a
/// metade da medição.
///
/// COMO A APPLE RESOLVE
/// ====================
///
/// A partir do iOS 18 o `AVCapturePhotoOutput` sabe fazer uma captura de cor
/// constante: dispara o flash com espectro conhecido, mede a cena com e sem
/// essa luz e reconstrói a imagem como ela seria sob uma iluminação de
/// referência. O resultado não depende da lâmpada do ambiente — é o mesmo
/// princípio de fotografar com carta de cinza, feito pelo próprio sistema.
///
/// O sistema devolve também **quanta confiança** ele tem em cada região, o que
/// é a parte que mais importa para este projeto: em vez de sempre sugerir uma
/// cor, o app passa a saber quando não deve. Regra inviolável 2 — lacuna vira
/// ausência declarada, nunca valor plausível.
///
/// O PREÇO, DITO NA CARA
/// =====================
///
/// A rota **sempre dispara o flash**, não aceita RAW e não aceita exposição
/// manual. Por isso ela é uma escolha explícita da pessoa, e não o caminho
/// padrão: `CapturaDeCamera` (a câmera do sistema) continua sendo o botão
/// principal de "Take a photo". Quem quer a cor medida escolhe esta; quem só
/// quer registrar a peça continua onde estava.
///
/// Referência: [Capturing consistent color images](https://developer.apple.com/documentation/avfoundation/capturing-consistent-color-images),
/// WWDC24 "Keep colors consistent across captures".
struct CapturaDeCorConstante: UIViewControllerRepresentable {

    /// O que a captura devolve.
    ///
    /// **DUAS FOTOS, E O MOTIVO SAIU DO APARELHO.**
    ///
    /// O JP testou a rota no iPhone em 05/09 e trouxe o que nenhum teste
    /// pegaria: *"senti que o flash deixou mais difícil até de definir a cor"*
    /// — e, ao mesmo tempo, *"acertou a cor marcada sim"*. As duas coisas são
    /// verdadeiras ao mesmo tempo, e é isso que obriga a separar.
    ///
    /// Flash no eixo, de perto, cria reflexo especular no tecido e desbota a
    /// superfície **para quem olha**, mesmo quando o sensor mediu certo. Usar a
    /// mesma imagem para as duas funções otimizava a medição e piorava o
    /// julgamento humano — o contrário do que a A54 (fundo neutro) foi fazer.
    ///
    /// A captura já produz as duas fotos, pela entrega de reserva: a natural e
    /// a de cor constante, da mesma cena, no mesmo disparo. Antes a natural era
    /// descartada. Agora cada uma faz o que faz melhor.
    struct Resultado {
        /// A foto que a pessoa VÊ, recorta e guarda: a natural, sem o brilho
        /// do flash. Já com a orientação aplicada, em memória — mesmo caminho
        /// da `CapturaDeCamera`: não vira arquivo, não vai à fototeca.
        let imagem: CGImage

        /// A foto de cor constante, usada só para MEDIR a cor.
        ///
        /// `nil` quando a rota não produziu uma (aparelho sem suporte, erro do
        /// sistema). Aí a medição acontece na mesma imagem que a pessoa vê,
        /// que é o comportamento de sempre.
        let imagemDeMedicao: CGImage?
        /// Confiança média ponderada ao centro, 0…1, como o sistema reporta.
        ///
        /// `nil` quando esta captura **não** passou pela rota de cor constante
        /// — aparelho sem suporte, erro do sistema ou entrega de reserva. `nil`
        /// não é "confiança zero": é "não medida", e o app trata os dois casos
        /// de forma diferente de propósito.
        let confianca: Double?

        var usouCorConstante: Bool { confianca != nil && imagemDeMedicao != nil }
    }

    let aoCapturar: (Resultado?) -> Void

    /// Vale oferecer esta rota neste aparelho?
    ///
    /// Só responde pelo que dá para saber **sem** pedir permissão de câmera:
    /// versão do sistema e existência de uma câmera traseira. O veredito real
    /// (`isConstantColorSupported`) exige uma sessão configurada, e portanto
    /// permissão concedida — ele acontece dentro da tela, que avisa em texto
    /// quando o suporte não existe em vez de devolver uma foto comum calada.
    static var disponivel: Bool {
        guard #available(iOS 18.0, *) else { return false }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return false }
        return AVCaptureDevice.default(.builtInWideAngleCamera,
                                       for: .video, position: .back) != nil
    }

    func makeUIViewController(context: Context) -> ControladorDeCorConstante {
        ControladorDeCorConstante(aoCapturar: aoCapturar)
    }

    func updateUIViewController(_ c: ControladorDeCorConstante, context: Context) {}
}

/// A câmera desenhada à mão que a rota de cor constante obriga.
///
/// O `UIImagePickerController` não expõe `AVCapturePhotoSettings`, então não há
/// como pedir cor constante por ele — a sessão precisa ser nossa. É o único
/// motivo de esta tela existir; ela imita a câmera do sistema no que importa
/// (prévia cheia, obturador, cancelar) e não tenta reproduzir o resto.
final class ControladorDeCorConstante: UIViewController {

    private let aoCapturar: (CapturaDeCorConstante.Resultado?) -> Void

    private let sessao = AVCaptureSession()
    private let saida = AVCapturePhotoOutput()
    private let fila = DispatchQueue(label: "br.com.canario.ch3.app.corconstante")
    private var camadaDePrevia: AVCaptureVideoPreviewLayer?

    /// O veredito do sistema, conhecido só depois de configurar a sessão.
    private var suportaCorConstante = false
    /// Acumula as duas entregas sem supor qual callback chega primeiro.
    private var montador = MontadorDeParDeCaptura<CGImage>()
    private var jaDevolveu = false

    private let aviso = UILabel()
    private let obturador = UIButton(type: .custom)
    private let cancelar = UIButton(type: .system)
    private let girando = UIActivityIndicatorView(style: .large)

    init(aoCapturar: @escaping (CapturaDeCorConstante.Resultado?) -> Void) {
        self.aoCapturar = aoCapturar
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        montarInterface()
        pedirPermissaoEConfigurar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        camadaDePrevia?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        fila.async { [sessao] in
            if sessao.isRunning { sessao.stopRunning() }
        }
    }

    // MARK: - Interface

    private func montarInterface() {
        let previa = AVCaptureVideoPreviewLayer(session: sessao)
        previa.videoGravity = .resizeAspectFill
        previa.frame = view.bounds
        view.layer.addSublayer(previa)
        camadaDePrevia = previa

        // O texto não é enfeite: a rota dispara o flash sempre, e disparar
        // flash sem avisar num ambiente já claro parece defeito.
        aviso.numberOfLines = 0
        aviso.textAlignment = .center
        aviso.textColor = .white
        aviso.font = .preferredFont(forTextStyle: .footnote)
        aviso.adjustsFontForContentSizeCategory = true
        // O TEXTO DIZ QUANDO VALE, E NAO SO O QUE FAZ.
        //
        // A primeira versao explicava o mecanismo ("dispara o flash para a cor
        // não depender da luz da sala") e deixava a decisão sem critério. O JP
        // testou no aparelho em 05/09 e trouxe as duas coisas que faltavam: o
        // flash disparou num ambiente já bem iluminado, e o reflexo do flash
        // atrapalhou ele a julgar a cor a olho -- mesmo com a medição tendo
        // acertado. Os dois efeitos são reais: flash no eixo, de perto, cria
        // brilho especular no tecido e desbota a superfície para quem olha.
        //
        // A rota não pode existir sem flash: é assim que a cor constante
        // funciona. O que dá para consertar é a escolha ficar informada.
        aviso.text = frase("The flash always fires: that is how the color is measured without depending on the room light. Worth it under yellow light, shade or store lighting. In good light a normal photo already reads well.")
        aviso.translatesAutoresizingMaskIntoConstraints = false

        let tarja = UIView()
        tarja.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        tarja.layer.cornerRadius = 14
        tarja.layer.cornerCurve = .continuous
        tarja.translatesAutoresizingMaskIntoConstraints = false
        tarja.addSubview(aviso)
        view.addSubview(tarja)

        obturador.backgroundColor = .white
        obturador.layer.cornerRadius = 34
        obturador.layer.borderWidth = 4
        obturador.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        obturador.accessibilityLabel = frase("Take a color-accurate photo")
        obturador.addTarget(self, action: #selector(disparar), for: .touchUpInside)
        obturador.translatesAutoresizingMaskIntoConstraints = false
        obturador.isEnabled = false
        view.addSubview(obturador)

        cancelar.setTitle(frase("Cancel"), for: .normal)
        cancelar.setTitleColor(.white, for: .normal)
        cancelar.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancelar.titleLabel?.adjustsFontForContentSizeCategory = true
        cancelar.addTarget(self, action: #selector(desistir), for: .touchUpInside)
        cancelar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelar)

        girando.color = .white
        girando.hidesWhenStopped = true
        girando.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(girando)

        let guia = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tarja.leadingAnchor.constraint(greaterThanOrEqualTo: guia.leadingAnchor, constant: 20),
            tarja.trailingAnchor.constraint(lessThanOrEqualTo: guia.trailingAnchor, constant: -20),
            tarja.centerXAnchor.constraint(equalTo: guia.centerXAnchor),
            tarja.topAnchor.constraint(equalTo: guia.topAnchor, constant: 16),
            aviso.topAnchor.constraint(equalTo: tarja.topAnchor, constant: 10),
            aviso.bottomAnchor.constraint(equalTo: tarja.bottomAnchor, constant: -10),
            aviso.leadingAnchor.constraint(equalTo: tarja.leadingAnchor, constant: 14),
            aviso.trailingAnchor.constraint(equalTo: tarja.trailingAnchor, constant: -14),

            obturador.centerXAnchor.constraint(equalTo: guia.centerXAnchor),
            obturador.bottomAnchor.constraint(equalTo: guia.bottomAnchor, constant: -28),
            obturador.widthAnchor.constraint(equalToConstant: 68),
            obturador.heightAnchor.constraint(equalToConstant: 68),

            cancelar.leadingAnchor.constraint(equalTo: guia.leadingAnchor, constant: 24),
            cancelar.centerYAnchor.constraint(equalTo: obturador.centerYAnchor),

            girando.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            girando.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Sessão

    private func pedirPermissaoEConfigurar() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configurar()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] concedido in
                DispatchQueue.main.async {
                    guard let self else { return }
                    concedido ? self.configurar() : self.devolver(nil)
                }
            }
        default:
            devolver(nil)
        }
    }

    private func configurar() {
        girando.startAnimating()
        fila.async { [weak self] in
            guard let self else { return }
            let pronta = self.montarSessao()
            if pronta { self.sessao.startRunning() }
            DispatchQueue.main.async {
                self.girando.stopAnimating()
                guard pronta else { self.devolver(nil); return }
                self.obturador.isEnabled = true
                if !self.suportaCorConstante {
                    // Honestidade antes de conveniência: sem suporte, a pessoa
                    // precisa saber que esta foto NÃO é a de cor medida antes
                    // de tirá-la — e não descobrir depois pelo resultado.
                    // O texto anterior prometia "nenhuma cor virá pré-marcada",
                    // e isso era falso: sem suporte, a foto segue o caminho
                    // normal, onde o `CorDaPeca` sugere cor como sempre sugeriu
                    // (confiança ausente = não medida, não zero). Prometer uma
                    // proteção que não existe é pior que não ter a proteção.
                    self.aviso.text = frase("This iPhone does not support color-accurate capture. The photo will be a normal one, and the color will be suggested the usual way — worth checking it yourself.")
                }
            }
        }
    }

    /// Roda fora da main thread. Devolve `false` quando não há como capturar.
    private func montarSessao() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back),
              let entrada = try? AVCaptureDeviceInput(device: camera) else { return false }

        sessao.beginConfiguration()
        defer { sessao.commitConfiguration() }
        sessao.sessionPreset = .photo
        guard sessao.canAddInput(entrada), sessao.canAddOutput(saida) else { return false }
        sessao.addInput(entrada)
        sessao.addOutput(saida)

        // A ordem importa: `isConstantColorSupported` só tem resposta depois
        // que a saída está na sessão, e ligar a propriedade reconfigura o
        // pipeline inteiro — a Apple pede que isso aconteça uma vez, aqui, e
        // não a cada disparo.
        if #available(iOS 18.0, *), saida.isConstantColorSupported {
            saida.isConstantColorEnabled = true
            suportaCorConstante = true
        }
        return true
    }

    // MARK: - Disparo

    @objc private func disparar() {
        obturador.isEnabled = false
        girando.startAnimating()
        let ajustes = AVCapturePhotoSettings()
        if #available(iOS 18.0, *), suportaCorConstante {
            ajustes.isConstantColorEnabled = true
            // A entrega de reserva faz dois trabalhos. Ela salva o
            // enquadramento quando a rota de cor constante falha -- e, desde
            // 05/09, ela É a foto que a pessoa vai olhar: a natural, sem o
            // brilho do flash. Ver `Resultado`.
            ajustes.isConstantColorFallbackPhotoDeliveryEnabled = true
        }
        if saida.supportedFlashModes.contains(.on) { ajustes.flashMode = .on }
        montador = MontadorDeParDeCaptura()
        jaDevolveu = false
        saida.capturePhoto(with: ajustes, delegate: self)
    }

    @objc private func desistir() {
        montador.cancelar()
        devolver(nil)
    }

    /// O ÚNICO caminho de saída, e ele acontece na fila principal.
    ///
    /// Os callbacks do `AVCapturePhotoCaptureDelegate` não têm garantia de
    /// rodar na main queue — a Apple os entrega numa fila interna. Este método
    /// mexe em UIKit (`girando`) e dispara a mudança de estado do SwiftUI
    /// (`aoCapturar`), e as duas coisas exigem a principal.
    ///
    /// Pior que a fila errada é a corrida: `jaDevolveu` era lido e escrito pelo
    /// delegate e pelo botão de cancelar ao mesmo tempo, e é justamente ele que
    /// impede a tela de ser fechada duas vezes. Um teste de lógica nunca pegaria
    /// isso; ele aparece como fechamento duplo ou congelamento intermitente no
    /// aparelho de alguém.
    ///
    /// `Thread.isMainThread` em vez de `async` sempre: vindo do botão, a
    /// entrega é síncrona e a tela fecha no mesmo ciclo, sem um quadro de
    /// atraso visível no toque.
    private func devolver(_ resultado: CapturaDeCorConstante.Resultado?) {
        if Thread.isMainThread {
            entregar(resultado)
        } else {
            DispatchQueue.main.async { [weak self] in self?.entregar(resultado) }
        }
    }

    private func entregar(_ resultado: CapturaDeCorConstante.Resultado?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !jaDevolveu else { return }
        jaDevolveu = true
        girando.stopAnimating()
        aoCapturar(resultado)
    }

    /// Os callbacks do AVFoundation podem vir fora da fila principal. Todos
    /// os eventos do mesmo disparo passam por ela antes de tocar o montador;
    /// além de proteger o estado, isso preserva a ordem do ciclo do delegate.
    private func registrarNatural(_ imagem: CGImage) {
        guard !Thread.isMainThread else {
            montador.registrarNatural(imagem)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.montador.registrarNatural(imagem)
        }
    }

    private func registrarConstante(_ imagem: CGImage,
                                    confianca: Double?) {
        guard !Thread.isMainThread else {
            montador.registrarConstante(imagem, confianca: confianca)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.montador.registrarConstante(imagem, confianca: confianca)
        }
    }

    /// Mesma normalização da `CapturaDeCamera`: o bitmap cru não carrega a
    /// orientação, e uma foto vertical chegaria deitada ao leitor de cor.
    fileprivate static func normalizar(_ dados: Data) -> CGImage? {
        guard let ui = UIImage(data: dados) else { return nil }
        return UIGraphicsImageRenderer(size: ui.size).image { _ in
            ui.draw(in: CGRect(origin: .zero, size: ui.size))
        }.cgImage
    }
}

extension ControladorDeCorConstante: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let dados = photo.fileDataRepresentation(),
              let imagem = Self.normalizar(dados) else { return }

        // Com a entrega de reserva ligada, este método é chamado duas vezes.
        // Nenhuma chamada entrega o resultado: só o fim do disparo fecha o
        // par, então a ordem natural→constante ou constante→natural dá o mesmo.
        if #available(iOS 18.0, *) {
            if photo.isConstantColorFallbackPhoto {
                registrarNatural(imagem)
                return
            }
            if suportaCorConstante {
                // O QUE ESTE NÚMERO MEDE, E O QUE ELE NÃO MEDE.
                //
                // `centerWeightedMean` é uma média do quadro inteiro ponderada
                // ao CENTRO. Uma peça bem enquadrada cai onde o peso é maior, e
                // aí ele descreve o que interessa; uma peça na periferia é
                // descrita por um número que fala principalmente do fundo.
                //
                // A Apple entrega também `constantColorConfidenceMap`, com
                // valor por região — que responderia a pergunta certa, "quanta
                // confiança HÁ NA PEÇA". Usá-lo exige saber onde a peça está, e
                // a segmentação só acontece depois, no importador. Enquanto a
                // média ao centro for o que temos, ela é o que o portão usa, e
                // o limite fica escrito aqui em vez de virar suposição.
                // Registrado em `FILA_DO_DEPOIS.md`, seção 2.6.
                let nivel = photo.constantColorCenterWeightedMeanConfidenceLevel
                // O sistema reporta `Float`. Um valor fora de 0…1 (ou NaN) é
                // ausência de medida, não confiança máxima: vira `nil`.
                let confianca = nivel.isFinite && nivel >= 0 && nivel <= 1
                    ? Double(nivel) : nil
                registrarConstante(imagem, confianca: confianca)
                return
            }
        }
        registrarNatural(imagem)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        // Fim da captura inteira. Se a de cor constante já respondeu, isto não
        // faz nada; se ela falhou, é aqui que a reserva salva o enquadramento.
        // Mesma razão de `devolver`: esta decisão lê `jaDevolveu` e mexe na
        // interface, e o callback pode não estar na fila principal.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.photoOutput(output, didFinishCaptureFor: resolvedSettings,
                                  error: error)
            }
            return
        }
        guard !jaDevolveu else { return }
        switch montador.concluir() {
        case let .captura(par):
            devolver(.init(imagem: par.imagem,
                           imagemDeMedicao: par.imagemDeMedicao,
                           confianca: par.confianca))
        case .tentarNovamente:
            girando.stopAnimating()
            obturador.isEnabled = true
        case .ignorar:
            break
        }
    }
}
