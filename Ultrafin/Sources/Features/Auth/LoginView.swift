import SwiftUI

@Observable
@MainActor
final class LoginViewModel {
    var username = ""
    var password = ""
    var isAuthenticating = false
    var errorMessage: String?

    let server: ServerConnection
    private let client: JellyfinClient

    init(server: ServerConnection) {
        self.server = server
        self.client = JellyfinClient(server: server)
    }

    var canSubmit: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty && !isAuthenticating }

    func authenticate() async -> UserSession? {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            return try await client.authenticate(username: username, password: password)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Sign in failed. Check your credentials."
            return nil
        }
    }
}

/// Username/password sign-in for the connected server.
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var model: LoginViewModel
    @FocusState private var focus: Field?

    enum Field { case username, password }

    init(server: ServerConnection) {
        _model = State(initialValue: LoginViewModel(server: server))
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            VStack(spacing: Spacing.sm) {
                Text("Sign in")
                    .font(Typography.displayTitle)
                    .foregroundStyle(UltrafinColors.primaryText)
                Text(model.server.name)
                    .font(Typography.body)
                    .foregroundStyle(UltrafinColors.secondaryText)
            }

            VStack(spacing: Spacing.md) {
                TextField("Username", text: $model.username)
                    .textFieldStyle(.plain)
                    .padding(Spacing.md)
                    .glassCard(cornerRadius: Spacing.md)
                    .focused($focus, equals: .username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .submitLabel(.next)
                    .onSubmit { focus = .password }

                SecureField("Password", text: $model.password)
                    .textFieldStyle(.plain)
                    .padding(Spacing.md)
                    .glassCard(cornerRadius: Spacing.md)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }

                if let error = model.errorMessage {
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.accent)
                        .transition(.opacity)
                }

                PrimaryButton(title: "Sign In", isLoading: model.isAuthenticating) {
                    Task { await submit() }
                }
                .disabled(!model.canSubmit)
                .opacity(model.canSubmit ? 1 : 0.5)

                Button("Use a different server") {
                    appState.signOut()
                }
                .font(Typography.caption)
                .foregroundStyle(UltrafinColors.secondaryText)
                .buttonStyle(.plain)
            }
            .foregroundStyle(UltrafinColors.primaryText)
            .frame(maxWidth: 460)

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
        .animation(.smooth, value: model.errorMessage)
        .onAppear { focus = .username }
    }

    private func submit() async {
        guard let session = await model.authenticate() else { return }
        appState.didAuthenticate(session)
    }
}
