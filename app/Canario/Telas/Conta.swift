import AuthenticationServices
import CryptoKit
import GoogleSignIn
import Security
import SwiftUI

@MainActor
final class GestorDaConta: NSObject, ObservableObject {
    static let shared = GestorDaConta()

    @Published private(set) var sessao: SessaoDaConta?
    @Published private(set) var trabalhando = false
    @Published private(set) var ultimaSincronizacao: Date?
    @Published var mensagemDeErro: String?
    @Published var mostrarConfirmacaoDeEmail = false
    @Published var mostrarNovaSenha = false
    @Published var mostrarRevogacaoManualApple = false

    private var nonceApple: String?

    override private init() {
        super.init()
        Task {
            if let restaurada = await Autenticacao.shared.sessaoAtual() {
                await adotar(restaurada)
            }
        }
    }

    func prepararApple(_ pedido: ASAuthorizationAppleIDRequest) {
        let nonce = Self.nonce()
        nonceApple = nonce
        pedido.requestedScopes = [.email]
        pedido.nonce = Self.sha256(nonce)
    }

    func concluirApple(_ resultado: Result<ASAuthorization, Error>) {
        guard case .success(let autorizacao) = resultado,
              let credencial = autorizacao.credential as? ASAuthorizationAppleIDCredential,
              let dados = credencial.identityToken,
              let token = String(data: dados, encoding: .utf8),
              let nonceApple else {
            if case .failure(let erro) = resultado,
               (erro as? ASAuthorizationError)?.code != .canceled {
                mensagemDeErro = erro.localizedDescription
            }
            self.nonceApple = nil
            return
        }
        self.nonceApple = nil
        executar {
            try await Autenticacao.shared.entrarComToken(
                token, provedor: .apple, nonce: nonceApple)
        }
    }

    func entrarComGoogle() {
        guard let apresentador = Self.controladorVisivel() else {
            mensagemDeErro = "Google Sign-In could not be opened."
            return
        }
        trabalhando = true
        GIDSignIn.sharedInstance.signIn(withPresenting: apresentador) { [weak self] resultado, erro in
            Task { @MainActor in
                guard let self else { return }
                guard let token = resultado?.user.idToken?.tokenString else {
                    self.trabalhando = false
                    if let erro { self.mensagemDeErro = erro.localizedDescription }
                    return
                }
                defer { self.trabalhando = false }
                do {
                    await self.adotar(try await Autenticacao.shared.entrarComToken(
                        token, provedor: .google, nonce: nil))
                } catch {
                    self.mensagemDeErro = error.localizedDescription
                }
            }
        }
    }

    func entrar(email: String, senha: String) {
        executar { try await Autenticacao.shared.entrar(email: email, senha: senha) }
    }

    func cadastrar(email: String, senha: String) {
        trabalhando = true
        Task {
            defer { trabalhando = false }
            do {
                if let nova = try await Autenticacao.shared.cadastrar(email: email, senha: senha) {
                    await adotar(nova)
                } else {
                    mostrarConfirmacaoDeEmail = true
                }
            } catch {
                mensagemDeErro = error.localizedDescription
            }
        }
    }

    func recuperar(email: String) {
        trabalhando = true
        Task {
            defer { trabalhando = false }
            do {
                try await Autenticacao.shared.recuperarSenha(email: email)
                mostrarConfirmacaoDeEmail = true
            } catch {
                mensagemDeErro = error.localizedDescription
            }
        }
    }

    func sair() {
        trabalhando = true
        Task {
            await Autenticacao.shared.sair()
            sessao = nil
            ultimaSincronizacao = nil
            await PecasSalvas.shared.usarEspacoDoUsuario(nil)
            trabalhando = false
        }
    }

    func excluirConta() {
        trabalhando = true
        Task {
            defer { trabalhando = false }
            do {
                let usavaApple = sessao?.usuario.provedores?.contains("apple") == true
                try await Autenticacao.shared.solicitarExclusao()
                await PecasSalvas.shared.apagarTudo()
                await PecasSalvas.shared.usarEspacoDoUsuario(nil)
                sessao = nil
                ultimaSincronizacao = nil
                mostrarRevogacaoManualApple = usavaApple
            } catch {
                mensagemDeErro = error.localizedDescription
            }
        }
    }

    func receberLink(_ url: URL) {
        if GIDSignIn.sharedInstance.handle(url) { return }
        guard url.scheme == "datadrobe", url.host == "auth-callback" else { return }
        trabalhando = true
        Task {
            defer { trabalhando = false }
            do {
                let recuperacao = Autenticacao.tipoDoCallback(url) == "recovery"
                await adotar(try await Autenticacao.shared.receberCallback(url))
                if recuperacao { mostrarNovaSenha = true }
            } catch {
                mensagemDeErro = error.localizedDescription
            }
        }
    }

    func atualizarSenha(_ senha: String) {
        trabalhando = true
        Task {
            defer { trabalhando = false }
            do {
                try await Autenticacao.shared.atualizarSenha(senha)
                mostrarNovaSenha = false
            } catch {
                mensagemDeErro = error.localizedDescription
            }
        }
    }

    private func executar(_ operacao: @escaping () async throws -> SessaoDaConta) {
        trabalhando = true
        Task {
            defer { trabalhando = false }
            do {
                await adotar(try await operacao())
            } catch {
                mensagemDeErro = error.localizedDescription
            }
        }
    }

    private func adotar(_ nova: SessaoDaConta) async {
        sessao = nova
        await PecasSalvas.shared.usarEspacoDoUsuario(nova.usuario.id)
        do {
            ultimaSincronizacao = try await SincronizacaoDoCloset.shared.sincronizar().data
        } catch {
            // Login continua válido e o Closet local continua utilizável. A
            // mensagem explica que falhou só a réplica, não a conta inteira.
            mensagemDeErro = error.localizedDescription
        }
    }

    private static func nonce(comprimento: Int = 32) -> String {
        let alfabeto = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var resultado = ""
        var bytes = [UInt8](repeating: 0, count: comprimento)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        for byte in bytes { resultado.append(alfabeto[Int(byte) % alfabeto.count]) }
        return resultado
    }

    private static func sha256(_ entrada: String) -> String {
        SHA256.hash(data: Data(entrada.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func controladorVisivel() -> UIViewController? {
        let cenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var atual = cenas.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let apresentado = atual?.presentedViewController { atual = apresentado }
        return atual
    }
}

extension GestorDaConta: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let cenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return cenas.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

struct ContaDoMenu: View {
    @EnvironmentObject private var conta: GestorDaConta
    @Environment(\.openURL) private var abrirURL
    @State private var mostrarEmail = false
    @State private var confirmarExclusao = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let sessao = conta.sessao {
                    contaConectada(sessao)
                } else {
                    entrada
                }
            }
            .padding(20)
        }
        .disabled(conta.trabalhando)
        .overlay {
            if conta.trabalhando {
                ProgressView().controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            }
        }
        .sheet(isPresented: $mostrarEmail) { EntradaPorEmail() }
        .sheet(isPresented: $conta.mostrarNovaSenha) { NovaSenha() }
        .alert("Account service", isPresented: Binding(
            get: { conta.mensagemDeErro != nil },
            set: { if !$0 { conta.mensagemDeErro = nil } }
        )) {
            Button("OK") { conta.mensagemDeErro = nil }
        } message: {
            Text(conta.mensagemDeErro ?? "")
        }
        .alert("Check your email", isPresented: $conta.mostrarConfirmacaoDeEmail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use the secure link we sent to finish this action. Your local Closet remains available while you wait.")
        }
        .alert("Finish removing Apple access", isPresented: $conta.mostrarRevogacaoManualApple) {
            Button("Open Apple Account") {
                if let url = URL(string: "https://account.apple.com/account/manage") {
                    abrirURL(url)
                }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Your DataDrobe account and data are already deleted. In Apple Account, open Sign-In & Security → Sign in with Apple and remove DataDrobe to revoke the remaining Apple authorization.")
        }
        .confirmationDialog(
            "Permanently delete this account?", isPresented: $confirmarExclusao,
            titleVisibility: .visible
        ) {
            Button("Delete account and local Closet", role: .destructive) {
                conta.excluirConta()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the account, its synced data and the Closet stored on this iPhone. This cannot be undone.")
        }
    }

    private var entrada: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Tokens.Cor.azulMarca)
            Text("Take your Closet with you")
                .font(.title2.bold())
            Text("Sign in to restore item details and keep them in sync. Photos stay on this iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            SignInWithAppleButton(.continue) { pedido in
                conta.prepararApple(pedido)
            } onCompletion: { resultado in
                conta.concluirApple(resultado)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 13))

            Button { conta.entrarComGoogle() } label: {
                Label("Continue with Google", systemImage: "g.circle.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 13))

            Button { mostrarEmail = true } label: {
                Label("Continue with email", systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 13))

            Text("You can close this screen and keep using DataDrobe without an account. Nothing is uploaded until you sign in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 26))
    }

    private func contaConectada(_ sessao: SessaoDaConta) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                    .font(.system(size: 46))
                    .foregroundStyle(Tokens.Cor.azulMarca)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Account connected").font(.headline)
                    Text(sessao.usuario.email ?? "Private Apple relay")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            BlocoInformativo(
                icone: "arrow.triangle.2.circlepath.icloud",
                titulo: "Offline-first sync",
                texto: "Item details are kept on this iPhone first and synchronized when a connection is available. Photos remain local in this version.")

            if let ultima = conta.ultimaSincronizacao {
                Label("Last synced \(ultima.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "checkmark.icloud")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("Waiting to sync", systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                conta.sair()
            }
            .buttonStyle(.bordered)

            Divider().padding(.vertical, 4)

            Button("Delete account", systemImage: "trash", role: .destructive) {
                confirmarExclusao = true
            }
            .buttonStyle(.bordered)
        }
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 26))
    }
}

private struct NovaSenha: View {
    @EnvironmentObject private var conta: GestorDaConta
    @State private var senha = ""
    @State private var confirmacao = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $senha)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirmacao)
                        .textContentType(.newPassword)
                } footer: {
                    Text("Use at least 10 characters.")
                }
                Button("Save new password") { conta.atualizarSenha(senha) }
                    .disabled(senha.count < 10 || senha != confirmacao || conta.trabalhando)
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}

private struct EntradaPorEmail: View {
    enum Modo: String, CaseIterable, Identifiable {
        case entrar = "Sign in"
        case criar = "Create account"
        var id: String { rawValue }
    }

    @EnvironmentObject private var conta: GestorDaConta
    @Environment(\.dismiss) private var dismiss
    @State private var modo: Modo = .entrar
    @State private var email = ""
    @State private var senha = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Action", selection: $modo) {
                    ForEach(Modo.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $senha)
                        .textContentType(modo == .criar ? .newPassword : .password)
                } footer: {
                    Text("Use at least 10 characters. DataDrobe never stores your password itself.")
                }

                Section {
                    Button(modo.rawValue) {
                        if modo == .entrar {
                            conta.entrar(email: email, senha: senha)
                        } else {
                            conta.cadastrar(email: email, senha: senha)
                        }
                    }
                    .disabled(email.isEmpty || senha.isEmpty || conta.trabalhando)

                    if modo == .entrar {
                        Button("Forgot password?") { conta.recuperar(email: email) }
                            .disabled(email.isEmpty || conta.trabalhando)
                    }
                }
            }
            .navigationTitle("Email account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: conta.sessao) { _, nova in
                if nova != nil { dismiss() }
            }
        }
    }
}
