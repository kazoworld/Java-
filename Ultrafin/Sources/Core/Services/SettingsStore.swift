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
    var homeLayout: HomeLayoutPreferences {
        didSet { persist(homeLayout, key: Keys.homeLayout) }
    }
    var featured: FeaturedPreferences {
        didSet { persist(featured, key: Keys.featured) }
    }
    var audio: AudioPreferences {
        didSet { persist(audio, key: Keys.audio) }
    }
    var video: VideoPreferences {
        didSet { persist(video, key: Keys.video) }
    }
    var subtitles: SubtitlePreferences {
        didSet { persist(subtitles, key: Keys.subtitles) }
    }
    var downloads: DownloadPreferences {
        didSet { persist(downloads, key: Keys.downloads) }
    }

    private enum Keys {
        static let theme = "settings.theme"
        static let appearance = "settings.appearance"
        static let playback = "settings.playback"
        static let homeLayout = "settings.homeLayout"
        static let featured = "settings.featured"
        static let audio = "settings.audio"
        static let video = "settings.video"
        static let subtitles = "settings.subtitles"
        static let downloads = "settings.downloads"
    }

    private init() {
        theme = Self.load(Keys.theme) ?? ThemePreferences()
        appearance = Self.load(Keys.appearance) ?? AppearancePreferences()
        playback = Self.load(Keys.playback) ?? PlaybackPreferences()
        featured = Self.load(Keys.featured) ?? FeaturedPreferences()
        audio = Self.load(Keys.audio) ?? AudioPreferences()
        video = Self.load(Keys.video) ?? VideoPreferences()
        subtitles = Self.load(Keys.subtitles) ?? SubtitlePreferences()
        downloads = Self.load(Keys.downloads) ?? DownloadPreferences()
        var layout = Self.load(Keys.homeLayout) ?? HomeLayoutPreferences()
        layout.normalize() // pick up any rows added in newer versions
        homeLayout = layout
    }

    // MARK: - Home layout mutations

    /// Moves a row up or down in the Home order (used by the reorder controls,
    /// which work on tvOS where drag-to-reorder isn't available). The featured
    /// media bar is pinned to the top and can't be reordered.
    func moveHomeRow(_ kind: HomeRowKind, up: Bool) {
        guard kind != .featured else { return }
        guard let i = homeLayout.rows.firstIndex(where: { $0.kind == kind }) else { return }
        let lower = homeLayout.rows.first?.kind == .featured ? 1 : 0
        let j = up ? i - 1 : i + 1
        guard j >= lower, j < homeLayout.rows.count else { return }
        homeLayout.rows.swapAt(i, j)
    }

    /// Visibility of the featured media bar, mirrored to its Home Layout row so
    /// there's a single source of truth.
    var isFeaturedEnabled: Bool {
        get { homeLayout.rows.first(where: { $0.kind == .featured })?.isEnabled ?? true }
        set {
            if let i = homeLayout.rows.firstIndex(where: { $0.kind == .featured }) {
                homeLayout.rows[i].isEnabled = newValue
            }
        }
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
    /// Light by default — the app's airy frosted-glass look is designed for it.
    var mode: Mode = .light

    /// When false, large hero/parallax animations are disabled for users who
    /// prefer reduced motion or want maximum battery/perf headroom.
    var richMotion: Bool = true

    /// Controls how large poster/landscape cards render across the app.
    var cardDensity: CardDensity = .regular

    /// True-black surfaces for OLED panels (deeper blacks, less burn-in, lower
    /// power) — also implies a quieter background.
    var oledMode: Bool = false

    /// The colorful ambient wash. Turn off to reduce GPU/screen usage.
    var ambientBackground: Bool = true

    var colorScheme: ColorScheme? {
        switch mode {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

/// Relative sizing for media cards, applied app-wide. The default (Regular) is
/// the larger, premium size that reads best on a TV.
enum CardDensity: String, Codable, CaseIterable, Identifiable {
    case compact, regular, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Multiplier applied to the base card width.
    var scale: CGFloat {
        switch self {
        case .compact: 1.0
        case .regular: 1.22
        case .large: 1.45
        }
    }
}

// MARK: - Audio / Video / Subtitles

struct AudioPreferences: Codable {
    /// Even out loud and quiet passages (great for late-night viewing).
    var loudnessNormalization: Bool = false

    /// Boost the center/dialogue channel — like Sonos Speech Enhancement.
    enum DialogueEnhancement: String, Codable, CaseIterable, Identifiable {
        case off, low, medium, high
        var id: String { rawValue }
        var label: String { self == .off ? "Off" : rawValue.capitalized }
    }
    var dialogueEnhancement: DialogueEnhancement = .off

    /// Pass surround audio (Dolby/DTS) straight to the receiver/TV untouched.
    var passthrough: Bool = false

    /// Preferred audio language (ISO code), or empty for the server default.
    var preferredLanguage: String = ""
}

struct VideoPreferences: Codable {
    /// Allow HDR10 / Dolby Vision passthrough when the show and TV support it.
    var allowHDR: Bool = true
    /// Match the TV's refresh rate and dynamic range to the content.
    var matchContent: Bool = true
    /// Starting quality for new playback (the in-player Quality menu can still
    /// override per-session).
    var defaultQuality: QualityOption = .auto
}

struct SubtitlePreferences: Codable {
    /// Closed-caption behavior. "Off unless engaged" briefly shows captions when
    /// you skip/rewind, then hides them — the default.
    enum CaptionMode: String, Codable, CaseIterable, Identifiable {
        case off, whenEngaged, always
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: "Off"
            case .whenEngaged: "Off unless engaged"
            case .always: "Always on"
            }
        }
    }
    var captionMode: CaptionMode = .off

    enum Size: String, Codable, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// VLC text-scale percentage.
        var scalePercent: Int { switch self { case .small: 75; case .medium: 100; case .large: 150 } }
    }
    var size: Size = .medium

    enum TextColor: String, Codable, CaseIterable, Identifiable {
        case white, yellow
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// VLC RGB integer.
        var vlcColor: Int { switch self { case .white: 16_777_215; case .yellow: 16_776_960 } }
    }
    var textColor: TextColor = .white

    /// Preferred subtitle language (ISO code), or empty for none/auto.
    var preferredLanguage: String = ""
}

/// Offline download preferences. (The download engine itself is a separate,
/// upcoming feature; these settings persist your choices for it.)
struct DownloadPreferences: Codable {
    enum Quality: String, Codable, CaseIterable, Identifiable {
        case original, high, medium
        var id: String { rawValue }
        var label: String {
            switch self {
            case .original: "Original"
            case .high: "High · 1080p"
            case .medium: "Medium · 720p"
            }
        }
    }
    var quality: Quality = .high
    var maxStorageGB: Int = 10
    var allowCellular: Bool = false
}

/// Common languages offered in audio/subtitle pickers (ISO 639-2 codes).
enum MediaLanguage {
    static let options: [(code: String, label: String)] = [
        ("", "Default"),
        ("eng", "English"),
        ("spa", "Spanish"),
        ("fre", "French"),
        ("ger", "German"),
        ("ita", "Italian"),
        ("por", "Portuguese"),
        ("jpn", "Japanese"),
        ("kor", "Korean"),
        ("chi", "Chinese")
    ]
}

// MARK: - Home layout

/// The kinds of rows that can appear on Home, in their default order.
enum HomeRowKind: String, Codable, CaseIterable, Identifiable {
    case featured
    case continueWatching
    case comingUp
    case recentlyAdded
    case recentShows
    case favorites
    case libraries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: "Featured Banner"
        case .continueWatching: "Continue Watching"
        case .comingUp: "Coming Up"
        case .recentlyAdded: "Recently Added"
        case .recentShows: "Recently Added TV Shows"
        case .favorites: "Favorites"
        case .libraries: "Your Libraries"
        }
    }

    var systemImage: String {
        switch self {
        case .featured: "rectangle.on.rectangle.angled"
        case .continueWatching: "play.circle"
        case .comingUp: "calendar"
        case .recentlyAdded: "sparkles"
        case .recentShows: "tv"
        case .favorites: "heart"
        case .libraries: "square.stack"
        }
    }
}

struct HomeRowConfig: Codable, Identifiable, Equatable {
    var kind: HomeRowKind
    var isEnabled: Bool
    var id: HomeRowKind { kind }
}

/// Settings for the featured media bar (the big rotating hero on Home).
struct FeaturedPreferences: Codable {
    /// Where the featured items are drawn from.
    enum Source: String, Codable, CaseIterable, Identifiable {
        case recentlyAdded, continueWatching, both
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recentlyAdded: "Recently Added"
            case .continueWatching: "Continue Watching"
            case .both: "Both"
            }
        }
    }

    /// Which media types are eligible for the media bar.
    enum ContentType: String, Codable, CaseIterable, Identifiable {
        case all, movies, shows
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "Movies & TV"
            case .movies: "Movies"
            case .shows: "TV Shows"
            }
        }
    }

    var contentType: ContentType = .all
    var source: Source = .both
    var itemCount: Int = 5
    /// Libraries that feed the bar. Empty means all libraries.
    var sourceLibraryIDs: [String] = []
    /// Automatically rotate through items.
    var autoAdvance: Bool = true
    /// Seconds between rotations.
    var rotationSeconds: Int = 8
}

/// Ordered, toggleable set of Home rows.
struct HomeLayoutPreferences: Codable {
    var rows: [HomeRowConfig]

    init() {
        rows = HomeRowKind.allCases.map { HomeRowConfig(kind: $0, isEnabled: true) }
    }

    /// Ensures the stored list contains every known row exactly once, appending
    /// any newly-added kinds and dropping unknown ones (forward/backward compat).
    mutating func normalize() {
        var seen = Set<HomeRowKind>()
        rows = rows.filter { seen.insert($0.kind).inserted }
        for kind in HomeRowKind.allCases where !seen.contains(kind) {
            rows.append(HomeRowConfig(kind: kind, isEnabled: true))
        }
        // Pin the featured media bar to the top.
        if let fi = rows.firstIndex(where: { $0.kind == .featured }), fi != 0 {
            let featured = rows.remove(at: fi)
            rows.insert(featured, at: 0)
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
