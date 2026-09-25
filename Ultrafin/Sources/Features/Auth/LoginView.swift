import SwiftUI

@Observable
@MainActor
final class LoginViewModel {
    var username = ""
    var password = ""
    var isAuthenticating = false
    var errorMessage: String?

    // Quick Connect: the short code shown on screen while we wait for the user
    // to approve it from their signed-in Jellyfin phone/desktop app.
    var quickCode: String?
    var quickActive = false
    /// Set when Quick Connect completes — the view hands it to AppState.
    var quickSession: UserSession?
    private var quickTask: Task<Void, Never>?

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

    // MARK: - Quick Connect

    func startQuickConnect() {
        errorMessage = nil
        quickActive = true
        quickCode = nil
        quickTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = try await self.client.quickConnectInitiate()
                self.quickCode = start.code
                // Poll until the user approves the code from another device.
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    guard let state = try? await self.client.quickConnectState(secret: start.secret) else { continue }
                    if state.authenticated == true {
                        let session = try await self.client.authenticateWithQuickConnect(secret: start.secret)
                        self.quickSession = session
                        return
                    }
                }
            } catch is CancellationError {
                // user backed out — nothing to report
            } catch {
                self.errorMessage = "Quick Connect isn't available — check it's enabled in your server's settings."
                self.quickActive = false
            }
        }
    }

    func cancelQuickConnect() {
        quickTask?.cancel()
        quickTask = nil
        quickActive = false
        quickCode = nil
    }
}

/// Sign-in for the connected server, on a floating glass card. Two paths:
/// username/password, or Quick Connect (approve a short code from the Jellyfin
/// app on your phone or computer — no typing on the TV).
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var model: LoginViewModel
    @State private var appeared = false

    init(server: ServerConnection) {
        _model = State(initialValue: LoginViewModel(server: server))
    }

    var body: some View {
        VStack {
            Spacer()
            AuthCard {
                if model.quickActive {
                    quickConnectContent
                } else {
                    credentialsContent
                }
            }
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .background(AuthBackdrop())
        .animation(.smooth, value: model.errorMessage)
        .animation(.smooth(duration: 0.35), value: model.quickActive)
        .animation(.smooth(duration: 0.35), value: model.quickCode)
        .task { withAnimation(.smooth(duration: 0.5)) { appeared = true } }
        .onChange(of: model.quickSession?.userID) { _, _ in
            if let session = model.quickSession { appState.didAuthenticate(session) }
        }
        #if os(tvOS)
        .onExitCommand {
            if model.quickActive { model.cancelQuickConnect() } else { appState.signOut() }
        }
        #endif
    }

    // MARK: - Username & password

    @ViewBuilder
    private var credentialsContent: some View {
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

        // No typing on the TV: approve a code from the Jellyfin app instead.
        Button { model.startQuickConnect() } label: {
            Label("Sign in with Quick Connect", systemImage: "iphone.gen3")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(UltrafinColors.primaryText)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .glassCapsule(dim: 0.08)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))

        Button("Use a different server") {
            appState.signOut()
        }
        .font(Typography.caption)
        .foregroundStyle(UltrafinColors.secondaryText)
        .buttonStyle(.plain)
    }

    // MARK: - Quick Connect

    @ViewBuilder
    private var quickConnectContent: some View {
        AuthBrand(systemImage: "iphone.gen3.radiowaves.left.and.right",
                  title: "Quick Connect",
                  subtitle: "Sign in from your phone — nothing to type here.")

        if let code = model.quickCode {
            // The code, big enough to read across the room.
            HStack(spacing: Spacing.sm) {
                ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: codeDigitSize, weight: .bold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                        .frame(width: codeDigitSize * 1.3, height: codeDigitSize * 1.7)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(LiquidGlass.rim(0.5), lineWidth: 1)
                        )
                }
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))

            Text("In the Jellyfin app on your phone or computer, open **Settings → Quick Connect** and enter this code.")
                .font(Typography.caption)
                .foregroundStyle(UltrafinColors.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Waiting for approval…")
                    .font(Typography.caption)
                    .foregroundStyle(UltrafinColors.tertiaryText)
            }
        } else {
            ProgressView().padding(.vertical, Spacing.lg)
        }

        Button("Back to password sign-in") {
            model.cancelQuickConnect()
        }
        .font(Typography.caption)
        .foregroundStyle(UltrafinColors.secondaryText)
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.04, lift: false))
    }

    private var codeDigitSize: CGFloat {
        #if os(tvOS)
        44
        #else
        30
        #endif
    }

    private func submit() async {
        guard let session = await model.authenticate() else { return }
        appState.didAuthenticate(session)
    }
}
