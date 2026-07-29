import SwiftUI

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
