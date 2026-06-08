import SwiftUI

@Observable
@MainActor
final class ServerConnectViewModel {
    var address: String = ""
    var isConnecting = false
    var errorMessage: String?

    private let service = ServerService()

    var canConnect: Bool { !address.trimmingCharacters(in: .whitespaces).isEmpty && !isConnecting }

    func connect() async -> ServerConnection? {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            return try await service.connect(to: address)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}

/// First-run screen: enter a Jellyfin server address.
struct ServerConnectView: View {
    @Environment(AppState.self) private var appState
    @State private var model = ServerConnectViewModel()
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Image(systemName: "server.rack")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(UltrafinColors.accentGradient)
                Text("Connect to Jellyfin")
                    .font(Typography.displayTitle)
                    .foregroundStyle(UltrafinColors.primaryText)
                Text("Enter the address of your Jellyfin server to get started.")
                    .font(Typography.body)
                    .foregroundStyle(UltrafinColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Spacing.md) {
                TextField("media.example.com", text: $model.address)
                    .textFieldStyle(.plain)
                    .padding(Spacing.md)
                    .glassCard(cornerRadius: Spacing.md)
                    .foregroundStyle(UltrafinColors.primaryText)
                    .focused($addressFocused)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    #endif
                    .onSubmit { Task { await attemptConnect() } }

                if let error = model.errorMessage {
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.accent)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                PrimaryButton(title: "Connect", systemImage: "arrow.right", isLoading: model.isConnecting) {
                    Task { await attemptConnect() }
                }
                .disabled(!model.canConnect)
                .opacity(model.canConnect ? 1 : 0.5)
            }
            .frame(maxWidth: 460)

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
        .animation(.smooth, value: model.errorMessage)
        .onAppear { addressFocused = true }
    }

    private func attemptConnect() async {
        guard let server = await model.connect() else { return }
        appState.didConnect(to: server)
    }
}
