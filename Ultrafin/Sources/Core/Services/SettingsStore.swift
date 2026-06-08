import SwiftUI
import Observation

/// User-customizable preferences, persisted to `UserDefaults` and observed by
/// the whole UI. This is the backing store for the Settings screen, so every
/// option the user changes takes effect live (accent, theme, playback, motion).
@Observable
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    var theme: ThemePreferences {
        didSet { persist(theme, key: Keys.theme) }
    }
    var appearance: AppearancePreferences {
        didSet { persist(appearance, key: Keys.appearance) }
    }
    var playback: PlaybackPreferences {
        didSet { persist(playback, key: Keys.playback) }
    }

    private enum Keys {
        static let theme = "settings.theme"
        static let appearance = "settings.appearance"
        static let playback = "settings.playback"
    }

    private init() {
        theme = Self.load(Keys.theme) ?? ThemePreferences()
        appearance = Self.load(Keys.appearance) ?? AppearancePreferences()
        playback = Self.load(Keys.playback) ?? PlaybackPreferences()
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Preference groups

struct ThemePreferences: Codable {
    var accent: AccentColor = .aurora
}

struct AppearancePreferences: Codable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case system, dark, light
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    var mode: Mode = .dark

    /// When false, large hero/parallax animations are disabled for users who
    /// prefer reduced motion or want maximum battery/perf headroom.
    var richMotion: Bool = true

    var colorScheme: ColorScheme? {
        switch mode {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

struct PlaybackPreferences: Codable {
    enum EnginePolicy: String, Codable, CaseIterable, Identifiable {
        /// Try AVPlayer first, fall back to VLCKit (recommended for smoothness).
        case hybrid
        /// Always use AVPlayer (lightest, relies on server transcode).
        case nativeOnly
        /// Always use VLCKit (maximum format support).
        case vlcOnly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .hybrid: "Hybrid (recommended)"
            case .nativeOnly: "Native AVPlayer"
            case .vlcOnly: "VLCKit"
            }
        }
    }
    var enginePolicy: EnginePolicy = .hybrid

    /// Resume from the last position instead of restarting.
    var autoResume: Bool = true
    /// Skip-forward/back interval in seconds.
    var seekInterval: Int = 15
    /// Default subtitle/audio behavior placeholders for future expansion.
    var preferredSubtitleLanguage: String = "eng"
    /// Cap UI animations to keep the player overlay buttery during playback.
    var maxBufferSeconds: Int = 30
}
