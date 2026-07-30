import SwiftUI

/// Root of the authenticated experience. Uses a tab layout that adapts to the
/// platform: a bottom tab bar on iOS and the top tab bar on tvOS.
///
/// The tab set belongs to the current ``AppMode`` — Media and Music are separate
/// experiences with their own tabs and their own settings. The last tab is a
/// switcher that flips between them rather than opening a screen of its own.
///
/// Switching tabs resets that tab to its root screen (rather than restoring the
/// last drill-down), so every tab always opens at the top.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @Binding var mode: AppMode

    @State private var selection = 0
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    // Music mode's own stacks — kept separate so the two experiences never
    // inherit each other's navigation.
    @State private var listenPath = NavigationPath()
    @State private var musicSearchPath = NavigationPath()
    @State private var musicSettingsPath = NavigationPath()
    /// The app-wide music session (mini-player + full player live here so they
    /// persist across every tab).
    @State private var music = MusicPlayer.shared
    @State private var showNowPlaying = false
    /// Drives the mini player's condensed state as pages scroll.
    @State private var chrome = ChromeState.shared

    /// The switcher's tag. Selecting it flips modes instead of navigating.
    private static let switchTag = 90

    /// Selecting a tab — INCLUDING re-selecting the one you're already on —
    /// always returns that tab to its root screen. A custom binding is the only
    /// way to see the re-selection: `onChange` never fires for an equal value,
    /// which left "press Settings to get back to the top of Settings" dead.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selection },
            set: { newValue in
                #if os(iOS)
                // A tap on the switcher tab is an explicit action, so act on it.
                guard newValue != Self.switchTag else {
                    switchMode()
                    return
                }
                #endif
                // On tvOS selection follows FOCUS along the top tab row, so the
                // switcher must never act here — merely moving focus onto it
                // would flip modes. Its tab shows a screen with a real button.
                resetPath(for: newValue)
                // A fresh tab starts at the top, so the chrome starts expanded.
                ChromeState.shared.reset()
                selection = newValue
            }
        )
    }

    /// Flip to the other experience, landing on its first tab with clean stacks.
    private func switchMode() {
        Haptics.play(.success)
        ChromeState.shared.reset()
        resetAllPaths()
        withAnimation(.smooth(duration: 0.35)) {
            mode = mode.opposite
            selection = 0
        }
        mode.remember()
    }

    private func resetPath(for tab: Int) {
        switch mode {
        case .media:
            switch tab {
            case 0: homePath = NavigationPath()
            case 1: libraryPath = NavigationPath()
            case 2: searchPath = NavigationPath()
            case 3: settingsPath = NavigationPath()
            default: break
            }
        case .music:
            switch tab {
            case 0: listenPath = NavigationPath()
            case 1: musicSearchPath = NavigationPath()
            case 2: musicSettingsPath = NavigationPath()
            default: break
            }
        }
    }

    private func resetAllPaths() {
        homePath = NavigationPath(); libraryPath = NavigationPath()
        searchPath = NavigationPath(); settingsPath = NavigationPath()
        listenPath = NavigationPath(); musicSearchPath = NavigationPath()
        musicSettingsPath = NavigationPath()
    }

    var body: some View {
        TabView(selection: tabSelection) {
            if mode == .media { mediaTabs } else { musicTabs }
        }
        // The now-playing bar rides above the tab bar; tap it (iOS) or focus it
        // (tvOS) to expand into the full player. It belongs to Music mode — in
        // Media mode the two experiences stay out of each other's way.
        #if os(tvOS)
        // A bottom safe-area inset — NOT a floating overlay. An overlay sits
        // outside the focus engine's sweep, so the bar was visible but
        // unreachable; an inset is a real sibling below the tab content that the
        // engine can move focus down into.
        .safeAreaInset(edge: .bottom) {
            if showsMiniPlayer {
                MiniPlayerBar(player: music) { showNowPlaying = true }
                    .padding(.horizontal, miniPlayerHPadding)
                    .padding(.bottom, miniPlayerBottomPadding)
                    .focusSection()
            }
        }
        // Holding Select anywhere in Music reopens the full player. The mini bar
        // is easy to miss with the remote, so this is the reliable way back into
        // the carousel without hunting for it.
        .onLongPressGesture(minimumDuration: 0.7) {
            guard music.hasQueue, !showNowPlaying else { return }
            showNowPlaying = true
        }
        #else
        .overlay(alignment: miniPlayerAlignment) {
            if showsMiniPlayer {
                MiniPlayerBar(player: music, onExpand: { showNowPlaying = true },
                              isCondensed: chrome.isCondensed)
                    .padding(.horizontal, miniPlayerHPadding)
                    .padding(.bottom, miniPlayerBottomPadding)
            }
        }
        #endif
        .animation(.smooth(duration: 0.35), value: music.hasQueue)
        // Starting a fresh listening session opens the full-screen player
        // automatically — the carousel is the default look, and on tvOS this
        // also sidesteps the focus engine ever having to reach the mini bar to
        // begin controlling playback.
        .onChange(of: music.sessionStamp) { _, stamp in
            if stamp > 0 { showNowPlaying = true }
        }
        .fullScreenCoverCompat(isPresented: $showNowPlaying) {
            NowPlayingMusicView(player: music) { destination in
                // Tapping the album/artist in the player opens that page in the
                // Music tab, switching modes if we're browsing Media.
                if mode != .music {
                    mode = .music
                    mode.remember()
                }
                selection = 0
                listenPath.append(destination)
            }
        }
        // Read the accent through the observed environment store so an accent
        // change in Settings recolors the tab bar live (the static
        // SettingsStore.shared read didn't re-render).
        .tint(settings.theme.accent.color)
    }

    /// The bar only belongs to Music mode, and never behind the full player.
    private var showsMiniPlayer: Bool {
        mode == .music && music.hasQueue && !showNowPlaying
    }

    // MARK: - Media tabs

    @ViewBuilder
    private var mediaTabs: some View {
        NavigationStack(path: $homePath) { HomeView() }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

        NavigationStack(path: $libraryPath) { LibraryRootView() }
            .tabItem { Label("Library", systemImage: "square.stack.fill") }
            .tag(1)

        NavigationStack(path: $searchPath) { SearchView() }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(2)

        NavigationStack(path: $settingsPath) { SettingsView() }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(3)

        #if os(tvOS)
        // The profile switcher lives in the tab row itself — a floating overlay
        // button was unreachable for the tvOS focus engine, and a tab is also
        // presentation-safe: switching rebuilds the tab tree with no cover to
        // tear down.
        ProfileSwitcherView(isTab: true, onDone: { selection = 0 })
            .tabItem { Label(profileTabTitle, systemImage: "person.crop.circle.fill") }
            .tag(4)
        #endif

        switcherTab
    }

    // MARK: - Music tabs

    @ViewBuilder
    private var musicTabs: some View {
        NavigationStack(path: $listenPath) { MusicHomeView() }
            .tabItem { Label("Listen Now", systemImage: "play.circle.fill") }
            .tag(0)

        NavigationStack(path: $musicSearchPath) { MusicSearchView() }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(1)

        NavigationStack(path: $musicSettingsPath) { MusicSettingsRootView() }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(2)

        #if os(tvOS)
        ProfileSwitcherView(isTab: true, onDone: { selection = 0 })
            .tabItem { Label(profileTabTitle, systemImage: "person.crop.circle.fill") }
            .tag(4)
        #endif

        switcherTab
    }

    /// The mode switcher. On iOS a tap flips modes straight away. On tvOS the tab
    /// shows a confirmation screen with a focusable button, because tab selection
    /// there follows focus — acting on selection alone would switch the moment
    /// the remote drifted onto it.
    @ViewBuilder
    private var switcherTab: some View {
        ModeSwitchScreen(target: mode.opposite) { switchMode() }
            .tabItem { Label(mode.switchLabel, systemImage: mode.switchImage) }
            .tag(Self.switchTag)
    }

    #if os(tvOS)
    /// The signed-in name labels the profile tab, like a Netflix profile chip.
    private var profileTabTitle: String {
        if case .authenticated(let session) = appState.phase { return session.username }
        return "Profile"
    }
    #endif

    // MARK: - Mini-player placement

    private var miniPlayerAlignment: Alignment {
        #if os(tvOS)
        .bottomTrailing
        #else
        .bottom
        #endif
    }
    private var miniPlayerHPadding: CGFloat {
        #if os(tvOS)
        60
        #else
        Spacing.md
        #endif
    }
    private var miniPlayerBottomPadding: CGFloat {
        #if os(tvOS)
        40
        #else
        58 // clears the floating tab bar
        #endif
    }
}

/// The switcher tab's screen: a single, deliberate "Switch to …" button. On
/// tvOS this is what actually performs the switch (selection follows focus up
/// there, so it can't be done on selection); on iOS the tap already switched and
/// this is only a brief hand-off.
private struct ModeSwitchScreen: View {
    let target: AppMode
    let onSwitch: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: Spacing.xl) {
                Image(systemName: target.systemImage)
                    .font(.system(size: glyph, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)

                VStack(spacing: Spacing.sm) {
                    Text("Switch to \(target.label)")
                        .font(.system(size: title, weight: .heavy, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                    Text(target == .music
                         ? "Albums, playlists and your listening."
                         : "Movies, shows and your library.")
                        .font(.system(size: subtitle, weight: .medium, design: .rounded))
                        .foregroundStyle(UltrafinColors.secondaryText)
                        .multilineTextAlignment(.center)
                }

                #if os(tvOS)
                Button(action: onSwitch) {
                    Label("Switch to \(target.label)", systemImage: target.systemImage)
                        .font(.system(size: subtitle, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.lg)
                        .glassCapsule(dim: 0.12)
                }
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: true))
                .padding(.top, Spacing.md)
                #endif
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
            .padding(Spacing.xxl)
        }
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { appeared = true } }
    }

    private var glyph: CGFloat {
        #if os(tvOS)
        90
        #else
        48
        #endif
    }
    private var title: CGFloat {
        #if os(tvOS)
        46
        #else
        26
        #endif
    }
    private var subtitle: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
}
