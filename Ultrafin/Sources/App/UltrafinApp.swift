import SwiftUI

/// Application entry point shared between the iOS and tvOS targets.
///
/// The whole UI is driven off a small set of `@Observable` stores that are
/// injected into the environment once, at the root, so individual screens stay
/// lightweight and render at a steady 60fps without re-creating dependencies.
@main
struct UltrafinApp: App {
    @State private var appState = AppState()
    @State private var settings = SettingsStore.shared

    #if os(iOS)
    // Portrait-only app; the video player unlocks rotation while it's up.
    @UIApplicationDelegateAdaptor(OrientationLock.self) private var orientationLock
    #endif

    init() {
        // Set the audio category up front so the first playback can open the
        // route instantly instead of negotiating it cold.
        AudioSession.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(settings.theme.accent.color)
        }
    }
}
