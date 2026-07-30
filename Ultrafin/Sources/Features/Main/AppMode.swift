import SwiftUI
import Observation

/// The experience currently on screen, published so the app root can adapt
/// window-level things to it — chiefly the colour scheme, since Music has its
/// own black/white canvas that has to override the media side's appearance.
@Observable
@MainActor
final class AppModeState {
    static let shared = AppModeState()
    private init() {}

    var current: AppMode?
}

/// Which experience the app is currently in. The two are deliberately separate:
/// each has its own tab set, its own settings, and its own idea of "home", so
/// browsing movies never mixes with listening to records.
enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case media, music

    var id: String { rawValue }

    var label: String { self == .media ? "Media" : "Music" }

    /// What the switcher offers — the mode you are *not* in.
    var opposite: AppMode { self == .media ? .music : .media }

    /// Icon for the mode itself.
    var systemImage: String { self == .media ? "film.stack.fill" : "music.note" }

    /// The switcher's label/icon: "Music" with a swap glyph while in Media.
    var switchLabel: String { opposite.label }
    var switchImage: String { "arrow.triangle.2.circlepath" }

    /// Remembered so a relaunch can offer the last choice first.
    private static let key = "app.lastMode"

    static var remembered: AppMode {
        AppMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .media
    }

    func remember() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}

/// What happens at launch: ask which experience to open, or go straight into
/// one. Set from the "What's the vibe?" screen (via "Start here every time")
/// and changeable later in Settings.
enum StartupPreference: Equatable, Sendable {
    case ask
    case launch(AppMode)

    private static let key = "app.startupMode"

    static var current: StartupPreference {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let mode = AppMode(rawValue: raw) else { return .ask }
        return .launch(mode)
    }

    static func set(_ preference: StartupPreference) {
        switch preference {
        case .ask:
            UserDefaults.standard.removeObject(forKey: key)
        case .launch(let mode):
            UserDefaults.standard.set(mode.rawValue, forKey: key)
        }
    }

    /// The mode to open directly, or nil to show the chooser.
    var directMode: AppMode? {
        if case .launch(let mode) = self { return mode }
        return nil
    }

    var label: String {
        switch self {
        case .ask: "Ask every time"
        case .launch(let mode): "Open \(mode.label)"
        }
    }
}

/// Where the Music experience gets its library. Asked once, the first time the
/// user opens Music, so a Navidrome listener never has to hunt through Settings.
enum MusicSourceOnboarding {
    private static let key = "music.sourceChosen"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func complete() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
