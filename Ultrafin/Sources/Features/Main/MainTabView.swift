import SwiftUI

/// Root of the authenticated experience. Uses a tab layout that adapts to the
/// platform: a bottom tab bar on iOS and the top tab bar on tvOS.
///
/// Switching tabs resets that tab to its root screen (rather than restoring the
/// last drill-down), so Home/Library/Settings always open at the top.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var selection: Int
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var musicPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    /// The app-wide music session (mini-player + full player live here so they
    /// persist across every tab).
    @State private var music = MusicPlayer.shared
    @State private var showNowPlaying = false
    /// Drives the mini player's condensed state as pages scroll.
    @State private var chrome = ChromeState.shared

    /// The tab to land on, chosen by the "What's the vibe?" screen (0 = Media/
    /// Home, 2 = Music). Defaults to Home.
    init(initialTab: Int = 0) {
        _selection = State(initialValue: initialTab)
    }

    /// Selecting a tab — INCLUDING re-selecting the one you're already on —
    /// always returns that tab to its root screen. A custom binding is the only
    /// way to see the re-selection: `onChange` never fires for an equal value,
    /// which left "press Settings to get back to the top of Settings" dead.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selection },
            set: { newValue in
                resetPath(for: newValue)
                // A fresh tab starts at the top, so the chrome starts expanded.
                ChromeState.shared.reset()
                selection = newValue
            }
        )
    }

    private func resetPath(for tab: Int) {
        switch tab {
        case 0: homePath = NavigationPath()
        case 1: libraryPath = NavigationPath()
        case 2: musicPath = NavigationPath()
        case 3: searchPath = NavigationPath()
        case 4: settingsPath = NavigationPath()
        default: break
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack(path: $homePath) {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack(path: $libraryPath) {
                LibraryRootView()
            }
            .tabItem { Label("Library", systemImage: "square.stack.fill") }
            .tag(1)

            NavigationStack(path: $musicPath) {
                MusicHomeView()
            }
            .tabItem { Label("Music", systemImage: "music.note") }
            .tag(2)

            NavigationStack(path: $searchPath) {
                SearchView()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(3)

            NavigationStack(path: $settingsPath) {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(4)

            #if os(tvOS)
            // The profile switcher lives in the tab row itself — a floating
            // overlay button was unreachable for the tvOS focus engine, and a
            // tab is also presentation-safe: switching rebuilds the tab tree
            // with no cover to tear down.
            ProfileSwitcherView(isTab: true, onDone: { selection = 0 })
                .tabItem { Label(profileTabTitle, systemImage: "person.crop.circle.fill") }
                .tag(5)
            #endif
        }
        // The now-playing bar rides above the tab bar on every screen; tap it
        // (iOS) or focus it (tvOS) to expand into the full player.
        #if os(tvOS)
        // A bottom safe-area inset — NOT a floating overlay. An overlay sits
        // outside the focus engine's sweep, so the bar was visible but
        // unreachable; an inset is a real sibling below the tab content that the
        // engine can move focus down into.
        .safeAreaInset(edge: .bottom) {
            if music.hasQueue && !showNowPlaying {
                MiniPlayerBar(player: music) { showNowPlaying = true }
                    .padding(.horizontal, miniPlayerHPadding)
                    .padding(.bottom, miniPlayerBottomPadding)
                    .focusSection()
            }
        }
        #else
        .overlay(alignment: miniPlayerAlignment) {
            if music.hasQueue && !showNowPlaying {
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
            NowPlayingMusicView(player: music)
        }
        // Read the accent through the observed environment store so an accent
        // change in Settings recolors the tab bar live (the static
        // SettingsStore.shared read didn't re-render).
        .tint(settings.theme.accent.color)
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
