import SwiftUI

/// Root of the authenticated experience. Uses a tab layout that adapts to the
/// platform: a bottom tab bar on iOS and the top tab bar on tvOS.
///
/// Switching tabs resets that tab to its root screen (rather than restoring the
/// last drill-down), so Home/Library/Settings always open at the top.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var selection = 0
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    /// Selecting a tab — INCLUDING re-selecting the one you're already on —
    /// always returns that tab to its root screen. A custom binding is the only
    /// way to see the re-selection: `onChange` never fires for an equal value,
    /// which left "press Settings to get back to the top of Settings" dead.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selection },
            set: { newValue in
                resetPath(for: newValue)
                selection = newValue
            }
        )
    }

    private func resetPath(for tab: Int) {
        switch tab {
        case 0: homePath = NavigationPath()
        case 1: libraryPath = NavigationPath()
        case 2: searchPath = NavigationPath()
        case 3: settingsPath = NavigationPath()
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

            NavigationStack(path: $searchPath) {
                SearchView()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(2)

            NavigationStack(path: $settingsPath) {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(3)

            #if os(tvOS)
            // The profile switcher lives in the tab row itself — a floating
            // overlay button was unreachable for the tvOS focus engine, and a
            // tab is also presentation-safe: switching rebuilds the tab tree
            // with no cover to tear down.
            ProfileSwitcherView(isTab: true, onDone: { selection = 0 })
                .tabItem { Label(profileTabTitle, systemImage: "person.crop.circle.fill") }
                .tag(4)
            #endif
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
}
