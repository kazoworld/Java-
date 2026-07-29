import SwiftUI

/// Asked once, the first time the user opens Music: where should the music come
/// from — the Jellyfin server they're already signed into, or a Navidrome server
/// they link here. Picking Jellyfin is one tap; Navidrome slides open a compact
/// link form so nobody has to go hunting through Settings.
struct MusicSourceOnboardingView: View {
    /// Called once a source is settled and Music can open.
    let onDone: () -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var navidrome = NavidromeStore.shared

    @State private var appeared = false
    @State private var linking = false
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        GeometryReader { geo in
            let scale = ResponsiveScale(size: geo.size)
            ZStack {
                UltrafinMeshBackdrop()
                Color.black.opacity(0.3).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: scale(32)) {
                        headline(scale)

                        if linking {
                            navidromeForm(scale)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity))
                        } else {
                            choices(scale)
                        }
                    }
                    .padding(.horizontal, scale(26))
                    .padding(.vertical, scale(36))
                    .frame(maxWidth: scale(560))
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: linking)
        .animation(.smooth(duration: 0.25), value: errorMessage)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.22)) { appeared = true }
        }
    }

    // MARK: - Pieces

    private func headline(_ scale: ResponsiveScale) -> some View {
        VStack(spacing: scale(10)) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: scale(40), weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: settings.theme.accent.color.opacity(0.5), radius: scale(18))
            Text("Where's your music?")
                .font(.system(size: scale(30), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            Text("You can change this later in Music → Settings.")
                .font(.system(size: scale(15), weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : scale(16))
    }

    private func choices(_ scale: ResponsiveScale) -> some View {
        VStack(spacing: scale(16)) {
            sourceCard(
                title: "Jellyfin",
                subtitle: "Use the music library on the server you're signed into.",
                icon: "server.rack",
                colors: [Color(hex: 0x2B32B2), Color(hex: 0x1488CC)],
                delay: 0.06, scale: scale
            ) {
                Haptics.play(.success)
                MusicPlayer.shared.stop()
                settings.musicSource = .jellyfin
                MusicSourceOnboarding.complete()
                onDone()
            }

            sourceCard(
                title: "Navidrome",
                subtitle: navidrome.config == nil
                    ? "Link a Navidrome server — it speaks the Subsonic API."
                    : "Already linked · \(navidrome.config?.serverURL.host ?? "server")",
                icon: "dot.radiowaves.left.and.right",
                colors: [Color(hex: 0x8E2DE2), Color(hex: 0xE94057)],
                delay: 0.14, scale: scale
            ) {
                Haptics.play(.selection)
                if navidrome.config != nil {
                    MusicPlayer.shared.stop()
                    settings.musicSource = .navidrome
                    MusicSourceOnboarding.complete()
                    onDone()
                } else {
                    linking = true
                }
            }
        }
    }

    private func sourceCard(title: String, subtitle: String, icon: String,
                            colors: [Color], delay: Double, scale: ResponsiveScale,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: scale(16)) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: icon)
                        .font(.system(size: scale(22), weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: scale(56), height: scale(56))
                .shadow(color: colors.first?.opacity(0.5) ?? .clear, radius: scale(14), y: 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: scale(19), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: scale(13), weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: scale(8))
                Image(systemName: "chevron.right")
                    .font(.system(size: scale(14), weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(scale(18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: scale(22), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: scale(22), style: .continuous)
                    .strokeBorder(LiquidGlass.rim(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.03, lift: true))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : scale(22))
        .animation(.spring(duration: 0.6, bounce: 0.28).delay(delay), value: appeared)
    }

    private func navidromeForm(_ scale: ResponsiveScale) -> some View {
        VStack(spacing: scale(14)) {
            GlassField(icon: "server.rack", placeholder: "Server address (https://…)",
                       text: $address, keyboard: .url, submitLabel: .next, autofocus: true)
            GlassField(icon: "person.fill", placeholder: "Username", text: $username)
            GlassField(icon: "lock.fill", placeholder: "Password",
                       text: $password, isSecure: true, submitLabel: .go) {
                Task { await link() }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: scale(13), weight: .medium))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            PrimaryButton(title: "Link Server", systemImage: "link", isLoading: isConnecting) {
                Task { await link() }
            }
            .disabled(!canLink || isConnecting)
            .opacity(canLink ? 1 : 0.5)

            Button("Use Jellyfin instead") {
                Haptics.play(.selection)
                MusicPlayer.shared.stop()
                settings.musicSource = .jellyfin
                MusicSourceOnboarding.complete()
                onDone()
            }
            .font(.system(size: scale(14), weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.04, lift: false))
        }
        .padding(scale(20))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: scale(26), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: scale(26), style: .continuous)
                .strokeBorder(LiquidGlass.rim(0.7), lineWidth: 1)
        )
    }

    private var canLink: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Linking

    private func link() async {
        guard canLink, !isConnecting else { return }
        errorMessage = nil
        guard let url = normalizedURL(from: address) else {
            errorMessage = "That address doesn't look right — try something like music.example.com."
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        let config = NavidromeConfig(serverURL: url,
                                     username: username.trimmingCharacters(in: .whitespaces),
                                     password: password)
        do {
            try await NavidromeClient(config: config).ping()
            navidrome.link(config)
            MusicPlayer.shared.stop()
            settings.musicSource = .navidrome
            MusicSourceOnboarding.complete()
            Haptics.play(.success)
            onDone()
        } catch let error as APIError {
            errorMessage = error.errorDescription ?? "Couldn't reach that server."
        } catch {
            errorMessage = "Couldn't reach that server — check the address and try again."
        }
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
