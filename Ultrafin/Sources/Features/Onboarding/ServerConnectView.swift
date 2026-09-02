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

/// First-run screen: enter a Jellyfin server address, on a floating glass card.
struct ServerConnectView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var model = ServerConnectViewModel()
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            AuthCard {
                AuthBrand(title: "Ultrafin",
                          subtitle: "Enter your Jellyfin server's address or IP to get started — like 192.168.1.20:8096 or media.example.com.")

                discoverySection

                GlassField(icon: "server.rack", placeholder: "192.168.1.20:8096",
                           text: $model.address, keyboard: .url, submitLabel: .go, autofocus: true) {
                    Task { await attemptConnect() }
                }

                #if os(tvOS)
                // Typing an IP with the Siri Remote is slow — nudge toward the
                // iPhone keyboard that pops up automatically.
                Label("Tip: typing is much faster with your iPhone — a keyboard notification appears when a text field is selected.",
                      systemImage: "iphone.gen3")
                    .font(Typography.caption)
                    .foregroundStyle(UltrafinColors.tertiaryText)
                    .multilineTextAlignment(.leading)
                #endif

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
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .background(AuthBackdrop())
        .animation(.smooth, value: model.errorMessage)
        .animation(.smooth, value: model.discovered)
        .task {
            withAnimation(.smooth(duration: 0.5)) { appeared = true }
            await model.scan()
        }
    }

    /// Discovered servers on the LAN, shown above manual entry as glass rows.
    @ViewBuilder
    private var discoverySection: some View {
        if model.isScanning && model.discovered.isEmpty {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Looking for servers on your network…")
                    .font(Typography.caption)
                    .foregroundStyle(UltrafinColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else if !model.discovered.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Found on your network")
                    .font(Typography.caption)
                    .foregroundStyle(UltrafinColors.secondaryText)
                ForEach(model.discovered) { server in
                    Button { Task { await attemptConnect(address: server.address) } } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "server.rack").foregroundStyle(UltrafinColors.accent)
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
                            Image(systemName: "chevron.right").foregroundStyle(UltrafinColors.tertiaryText)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .glassCapsule(dim: 0)
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
