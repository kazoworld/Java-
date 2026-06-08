import SwiftUI

/// Root of the authenticated experience. Uses a tab layout that adapts to the
/// platform: a bottom tab bar on iOS and the top tab bar on tvOS.
struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                LibraryRootView()
            }
            .tabItem { Label("Library", systemImage: "square.stack.fill") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(SettingsStore.shared.theme.accent.color)
    }
}
