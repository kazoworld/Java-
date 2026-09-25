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
    @State private var mode = AppModeState.shared

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
                .preferredColorScheme(effectiveColorScheme)
                .tint(settings.accent)
        }
    }

    /// Music mode's Theme owns the window while it's on screen; otherwise the
    /// media side's Appearance does.
    ///
    /// This has to happen at the root: `preferredColorScheme` here sets the
    /// window's interface style, and `UltrafinColors` resolves through UIKit
    /// traits — so a nested `.environment(\.colorScheme,)` further down can't
    /// override it, which is why switching the music theme appeared to do
    /// nothing.
    private var effectiveColorScheme: ColorScheme? {
        if mode.current == .music {
            return settings.musicTheme.colorScheme
        }
        return settings.appearance.colorScheme
    }
}
