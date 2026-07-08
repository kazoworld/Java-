import SwiftUI

// MARK: - Avatar

/// A circular profile avatar: the user's Jellyfin profile picture when one is
/// set, otherwise a premium monogram — their initials (one letter, or two for
/// "First Last" names) on a rich gradient chosen deterministically from the
/// name, so every profile keeps its own color.
struct ProfileAvatar: View {
    let name: String
    var imageURL: URL? = nil
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let imageURL {
                RemoteImage(url: imageURL)
                    .frame(width: size, height: size)
            } else {
                monogram
            }
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(LiquidGlass.rim(0.8), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: size * 0.08, y: size * 0.04)
    }

    private var monogram: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            // A soft top sheen so the badge reads as lit glass, not a flat chip.
            Circle().fill(LiquidGlass.sheen)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
    }

    /// "leo" → "L", "Lisa Simpson" → "LS".
    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    /// A stable, name-keyed pick from a curated set of premium gradients.
    private var gradient: [Color] {
        let palettes: [[Color]] = [
            [Color(hex: 0x6D8BFF), Color(hex: 0xB56DFF)], // aurora → orchid
            [Color(hex: 0x38BDF8), Color(hex: 0x6D8BFF)], // ocean → aurora
            [Color(hex: 0xFF6D5A), Color(hex: 0xFFC857)], // ember → gold
            [Color(hex: 0x3DD9A0), Color(hex: 0x38BDF8)], // mint → ocean
            [Color(hex: 0xFF6DAE), Color(hex: 0xB56DFF)], // rose → orchid
            [Color(hex: 0xFFC857), Color(hex: 0xFF6DAE)]  // gold → rose
        ]
        var hash: UInt64 = 5381
        for byte in name.lowercased().utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return palettes[Int(hash % UInt64(palettes.count))]
    }
}

// MARK: - Who's Watching

/// The full-screen profile switcher: every account on the server as a big,
/// focusable circular avatar. Profiles with a remembered session (or with no
/// password) switch instantly; locked profiles ask for their password once and
/// are remembered after that.
struct ProfileSwitcherView: View {
    /// True when hosted as a tvOS tab (vs. presented as a cover on iOS):
    /// switching applies immediately — there's no presentation to unwind — and
    /// "done" hands control back via `onDone` instead of dismissing.
    var isTab: Bool = false
    var onDone: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var users: [ServerUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// The locked profile currently asking for its password, if any.
    @State private var passwordTarget: ServerUser?
    @State private var password = ""
    @State private var isSwitching = false

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    var body: some View {
        ZStack {
            ZStack {
                UltrafinColors.background
                LinearGradient(colors: [settings.theme.accent.color.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Text("Who's Watching?")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)

                if isLoading {
                    ProgressView().padding(.top, Spacing.xxl)
                } else if users.isEmpty {
                    Text(errorMessage ?? "No other profiles on this server.")
                        .font(Typography.body)
                        .foregroundStyle(UltrafinColors.secondaryText)
                } else {
                    profileGrid
                }

                if let errorMessage, !users.isEmpty {
                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.secondaryText)
                }
            }
            .padding(edgePadding)

            if let target = passwordTarget {
                passwordPrompt(for: target)
            }

            if isSwitching {
                Color.black.opacity(0.35).ignoresSafeArea()
                ProgressView().tint(.white).scaleEffect(1.4)
            }
        }
        .environment(\.colorScheme, .dark)
        .task { await load() }
        #if os(tvOS)
        // Menu closes an open password prompt; beyond that, a presented cover
        // dismisses while a tab lets the system handle Menu normally.
        .onExitCommand(perform: passwordTarget != nil
            ? { passwordTarget = nil }
            : (isTab ? nil : { dismiss() }))
        #endif
    }

    private var profileGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: profileSpacing) {
                ForEach(users) { user in
                    profileButton(user)
                }
            }
            .padding(Spacing.lg)
        }
        .scrollClipDisabled()
        // A strictly horizontal rail: tall enough that the content never
        // overflows the frame (so .basedOnSize resolves to no vertical bounce),
        // and never wider than THREE profiles — a wall of ten avatars is
        // overwhelming; the rest scroll in from the side.
        .frame(height: railHeight)
        .frame(maxWidth: visibleRailWidth)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }

    /// Width that fits exactly three profile cards (plus gaps and the rail's
    /// own padding) — the on-screen limit no matter how many users exist.
    private var visibleRailWidth: CGFloat {
        let card = avatarSize + 40
        return card * 3 + profileSpacing * 2 + Spacing.lg * 2
    }

    private func profileButton(_ user: ServerUser) -> some View {
        let isCurrent = user.id == session?.userID
        return Button { select(user) } label: {
            VStack(spacing: Spacing.md) {
                ProfileAvatar(name: user.name, imageURL: avatarURL(user), size: avatarSize)
                    .overlay(
                        Circle().strokeBorder(
                            isCurrent ? settings.theme.accent.color : .clear,
                            lineWidth: 3)
                    )
                HStack(spacing: 5) {
                    Text(user.name)
                        .font(.system(size: nameSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                        .lineLimit(1)
                    if user.hasPassword == true && savedSession(user) == nil && !isCurrent {
                        Image(systemName: "lock.fill")
                            .font(.system(size: nameSize * 0.7))
                            .foregroundStyle(UltrafinColors.tertiaryText)
                    }
                }
                if isCurrent {
                    Text("Watching now")
                        .font(.system(size: nameSize * 0.66, weight: .medium))
                        .foregroundStyle(settings.theme.accent.color)
                }
            }
            .frame(width: avatarSize + 40)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.12, lift: true))
        .disabled(isSwitching)
    }

    // MARK: - Selection

    /// The remembered session for a profile on the current server, if any.
    private func savedSession(_ user: ServerUser) -> UserSession? {
        guard let server = session?.server else { return nil }
        return appState.sessionStore.savedSession(userID: user.id, serverID: server.id)
    }

    /// Leave the switcher without changing anything.
    private func finishWithoutSwitching() {
        if isTab { onDone?() } else { dismiss() }
    }

    private func select(_ user: ServerUser) {
        errorMessage = nil
        guard user.id != session?.userID else { finishWithoutSwitching(); return }

        // 1) A remembered session switches instantly, no typing. If its token
        //    was revoked (Jellyfin drops a device's old token when the same
        //    device signs in as someone else), fall through to a silent re-auth
        //    for passwordless accounts before ever bothering with a prompt.
        if let saved = savedSession(user) {
            switchUsing { await appState.validateSaved(saved) ? saved : nil } fallback: {
                if user.hasPassword == false {
                    switchUsing { await authenticate(user: user, password: "") } fallback: { promptPassword(user) }
                } else {
                    promptPassword(user)
                }
            }
            return
        }
        // 2) Accounts with no password sign in silently.
        if user.hasPassword == false {
            switchUsing { await authenticate(user: user, password: "") } fallback: { promptPassword(user) }
            return
        }
        // 3) Locked account we haven't seen — ask for its password (once).
        promptPassword(user)
    }

    private func promptPassword(_ user: ServerUser) {
        password = ""
        withAnimation(.smooth(duration: 0.25)) { passwordTarget = user }
    }

    /// Obtains a validated session with the busy overlay, then applies it. As a
    /// cover (iOS), the cover is dismissed FIRST and the app switches after it
    /// unwinds — applying the switch while presented rebuilds the presenting
    /// hierarchy underneath a live presentation, which blanked the whole window
    /// until an app restart. As a tab (tvOS) there's nothing to unwind, so the
    /// switch applies immediately.
    private func switchUsing(_ makeSession: @escaping () async -> UserSession?, fallback: @escaping () -> Void) {
        isSwitching = true
        Task {
            guard let newSession = await makeSession() else {
                isSwitching = false
                fallback()
                return
            }
            isSwitching = false
            Haptics.play(.success)
            if isTab {
                appState.didAuthenticate(newSession)
                onDone?()
            } else {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    appState.didAuthenticate(newSession)
                }
            }
        }
    }

    /// Signs into `user` fresh and returns the session (the caller applies it
    /// at a presentation-safe moment).
    private func authenticate(user: ServerUser, password: String) async -> UserSession? {
        guard let server = session?.server else { return nil }
        let client = JellyfinClient(server: server)
        return try? await client.authenticate(username: user.name, password: password)
    }

    private func submitPassword(for user: ServerUser) {
        let entered = password
        passwordTarget = nil
        switchUsing { await authenticate(user: user, password: entered) } fallback: {
            errorMessage = "Wrong password for \(user.name) — try again."
            promptPassword(user)
        }
    }

    // MARK: - Password prompt

    private func passwordPrompt(for user: ServerUser) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                #if os(iOS)
                .onTapGesture { passwordTarget = nil }
                #endif

            VStack(spacing: Spacing.lg) {
                ProfileAvatar(name: user.name, imageURL: avatarURL(user), size: avatarSize * 0.55)
                Text("Enter \(user.name)'s password")
                    .font(.system(size: nameSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .padding(Spacing.md)
                    .frame(width: fieldWidth)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit { submitPassword(for: user) }

                HStack(spacing: Spacing.md) {
                    Button("Cancel") { withAnimation(.smooth(duration: 0.2)) { passwordTarget = nil } }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))
                    Button("Switch") { submitPassword(for: user) }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))
                        .foregroundStyle(settings.theme.accent.color)
                }
                .font(.system(size: nameSize, weight: .semibold, design: .rounded))
            }
            .padding(Spacing.xxl)
            .liquidGlass(cornerRadius: 24)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    // MARK: - Data

    private func load() async {
        guard let client = appState.client else { isLoading = false; return }
        do {
            var list = try await client.serverUsers()
            // Current profile first, the rest alphabetical.
            let currentID = session?.userID
            list.sort {
                if $0.id == currentID { return true }
                if $1.id == currentID { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            users = list
        } catch {
            errorMessage = "Couldn't load profiles from the server."
        }
        isLoading = false
    }

    private func avatarURL(_ user: ServerUser) -> URL? {
        guard user.primaryImageTag != nil else { return nil }
        return appState.client?.userImageURL(userID: user.id, tag: user.primaryImageTag,
                                             maxWidth: Int(avatarSize * 2))
    }

    // MARK: - Metrics

    private var titleSize: CGFloat {
        #if os(tvOS)
        44
        #else
        28
        #endif
    }
    private var avatarSize: CGFloat {
        #if os(tvOS)
        180
        #else
        92
        #endif
    }
    private var nameSize: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }
    private var profileSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        Spacing.xl
        #endif
    }
    /// Avatar + name + "Watching now" + the rail's own padding, with headroom —
    /// content overflowing this frame is what made the rail drag vertically.
    private var railHeight: CGFloat {
        #if os(tvOS)
        avatarSize + 150
        #else
        avatarSize + 120
        #endif
    }
    private var fieldWidth: CGFloat {
        #if os(tvOS)
        420
        #else
        260
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        60
        #else
        20
        #endif
    }
}
