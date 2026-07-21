import SwiftUI

/// Settings → Music: choose which backend powers the Music tab (Jellyfin by
/// default), and link/unlink a Navidrome server. One source at a time.
struct MusicSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var navidrome = NavidromeStore.shared
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLinking = false
    @State private var linkError: String?

    var body: some View {
        Form {
            Section {
                sourceRow(.jellyfin, subtitle: "Your Jellyfin server's music libraries")
                sourceRow(.navidrome, subtitle: navidromeSubtitle)
            } header: {
                Text("Source")
            } footer: {
                Text("One source powers Music at a time. Switching stops whatever is playing.")
            }

            if let config = navidrome.config {
                Section {
                    LabeledContent("Server", value: config.serverURL.absoluteString).tvFocusable()
                    LabeledContent("User", value: config.username).tvFocusable()
                    Button("Unlink Server", role: .destructive) { unlink() }
                } header: {
                    Text("Navidrome server")
                } footer: {
                    Text("Unlinking removes the saved credentials from this device and returns Music to Jellyfin.")
                }
            } else {
                Section {
                    TextField("Server address (https://…)", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Button {
                        link()
                    } label: {
                        if isLinking {
                            ProgressView()
                        } else {
                            Text("Link Server")
                        }
                    }
                    .disabled(isLinking || address.trimmingCharacters(in: .whitespaces).isEmpty
                              || username.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Link your Navidrome server")
                } footer: {
                    Text("Ultrafin signs in over the Subsonic API. Credentials are stored in this device's Keychain and only ever sent to your server.")
                }
            }

            if let linkError {
                Section {
                    Label(linkError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .tvFocusable()
                }
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Music")
        .tint(settings.theme.accent.color)
    }

    private var navidromeSubtitle: String {
        if let config = navidrome.config {
            return "Linked · \(config.serverURL.host ?? config.serverURL.absoluteString)"
        }
        return "Link a server below to enable"
    }

    private func sourceRow(_ kind: MusicSourceKind, subtitle: String) -> some View {
        Button {
            select(kind)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                        .foregroundStyle(UltrafinColors.primaryText)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.secondaryText)
                }
                Spacer()
                if settings.musicSource == kind {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(settings.theme.accent.color)
                }
            }
        }
    }

    private func select(_ kind: MusicSourceKind) {
        linkError = nil
        guard kind != settings.musicSource else { return }
        if kind == .navidrome && navidrome.config == nil {
            linkError = "Link your Navidrome server below first."
            return
        }
        Haptics.play(.selection)
        // The old queue streams from the old backend — clear it so the mini
        // player never shows one server's song over the other's library.
        MusicPlayer.shared.stop()
        settings.musicSource = kind
    }

    private func link() {
        linkError = nil
        guard let url = normalizedURL(from: address) else {
            linkError = "That server address doesn't look right — include the host, like https://music.example.com."
            return
        }
        let config = NavidromeConfig(serverURL: url,
                                     username: username.trimmingCharacters(in: .whitespaces),
                                     password: password)
        isLinking = true
        Task {
            do {
                try await NavidromeClient(config: config).ping()
                navidrome.link(config)
                MusicPlayer.shared.stop()
                settings.musicSource = .navidrome
                address = ""; username = ""; password = ""
                Haptics.play(.success)
            } catch let error as APIError {
                linkError = error.errorDescription ?? "Couldn't reach that server — check the address and try again."
            } catch {
                linkError = "Couldn't reach that server — check the address and try again."
            }
            isLinking = false
        }
    }

    private func unlink() {
        Haptics.play(.selection)
        MusicPlayer.shared.stop()
        navidrome.unlink()
        settings.musicSource = .jellyfin
        linkError = nil
    }

    /// Accepts "music.example.com", "http://…", or "https://…:4533/path".
    private func normalizedURL(from input: String) -> URL? {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
            raw = "https://" + raw
        }
        while raw.hasSuffix("/") { raw.removeLast() }
        guard let url = URL(string: raw), url.host != nil else { return nil }
        return url
    }
}
