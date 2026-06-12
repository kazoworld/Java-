import SwiftUI

/// Root of the authenticated experience. Uses a tab layout that adapts to the
/// platform: a bottom tab bar on iOS and the top tab bar on tvOS.
///
/// Switching tabs resets that tab to its root screen (rather than restoring the
/// last drill-down), so Home/Library/Settings always open at the top.
struct MainTabView: View {
    @Environment(AppState.self) private var appState

    @State private var selection = 0
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        TabView(selection: $selection) {
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
        }
        .tint(SettingsStore.shared.theme.accent.color)
        .onChange(of: selection) { _, newValue in
            // Reset the selected tab to its root screen.
            switch newValue {
            case 0: homePath = NavigationPath()
            case 1: libraryPath = NavigationPath()
            case 2: searchPath = NavigationPath()
            case 3: settingsPath = NavigationPath()
            default: break
            }
        }
    }
}
