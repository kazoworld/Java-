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

/// Username/password sign-in for the connected server, on a floating glass card.
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var model: LoginViewModel
    @State private var appeared = false

    init(server: ServerConnection) {
        _model = State(initialValue: LoginViewModel(server: server))
    }

    var body: some View {
        VStack {
            Spacer()
            AuthCard {
                AuthBrand(systemImage: "person.crop.circle.fill",
                          title: "Sign In",
                          subtitle: model.server.name)

                GlassField(icon: "person.fill", placeholder: "Username",
                           text: $model.username, submitLabel: .next, autofocus: true)

                GlassField(icon: "lock.fill", placeholder: "Password",
                           text: $model.password, isSecure: true, submitLabel: .go) {
                    Task { await submit() }
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.accent)
                        .multilineTextAlignment(.center)
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
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .animation(.smooth, value: model.errorMessage)
        .task { withAnimation(.smooth(duration: 0.5)) { appeared = true } }
    }

    private func submit() async {
        guard let session = await model.authenticate() else { return }
        appState.didAuthenticate(session)
    }
}
