import SwiftUI

@Observable
@MainActor
final class ServerConnectViewModel {
    var address: String = ""
    var isConnecting = false
    var errorMessage: String?

    var discovered: [DiscoveredServer] = []
    var isScanning = false

    private let service = ServerService()
    private let discovery = ServerDiscovery()

    var canConnect: Bool { !address.trimmingCharacters(in: .whitespaces).isEmpty && !isConnecting }

    /// Scans the local network for Jellyfin servers so the user often doesn't
    /// have to type an address at all.
    func scan() async {
        isScanning = true
        defer { isScanning = false }
        discovered = await discovery.discover()
    }

    /// Connects to `address` (defaults to the typed field) and returns a
    /// verified server.
    func connect(to overrideAddress: String? = nil) async -> ServerConnection? {
        let target = overrideAddress ?? address
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            return try await service.connect(to: target)
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
                discoverySection

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
            .frame(maxWidth: 520)

            Spacer()
            Spacer()
        }
        .padding(Spacing.xl)
        .animation(.smooth, value: model.errorMessage)
        .animation(.smooth, value: model.discovered)
        .task { await model.scan() }
        .onAppear { addressFocused = true }
    }

    /// Discovered servers on the LAN, shown above manual entry so the user can
    /// connect with a single click instead of typing an address.
    @ViewBuilder
    private var discoverySection: some View {
        if model.isScanning && model.discovered.isEmpty {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Looking for servers on your network…")
                    .font(Typography.caption)
                    .foregroundStyle(UltrafinColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.discovered.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Found on your network")
                    .font(Typography.caption)
                    .foregroundStyle(UltrafinColors.secondaryText)
                ForEach(model.discovered) { server in
                    Button {
                        Task { await attemptConnect(address: server.address) }
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "server.rack")
                                .foregroundStyle(UltrafinColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(UltrafinColors.primaryText)
                                Text(server.address)
                                    .font(Typography.caption)
                                    .foregroundStyle(UltrafinColors.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(UltrafinColors.tertiaryText)
                        }
                        .padding(Spacing.md)
                        .glassCard(cornerRadius: Spacing.md)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.03, lift: false))
                }
            }
        }
    }

    private func attemptConnect(address: String? = nil) async {
        guard let server = await model.connect(to: address) else { return }
        appState.didConnect(to: server)
    }
}
