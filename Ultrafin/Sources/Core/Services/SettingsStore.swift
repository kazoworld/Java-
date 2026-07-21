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

    /// When true, the Continue Watching row leads with Next Up (the next
    /// unwatched episode) before in-progress items; false leads with in-progress.
    /// Stored standalone so adding it doesn't break decoding of existing groups.
    var nextUpFirst: Bool {
        didSet { UserDefaults.standard.set(nextUpFirst, forKey: Keys.nextUpFirst) }
    }

    /// When true (default), playback auto-selects an English audio track when the
    /// media has one, so titles don't start in another language.
    var preferEnglishAudio: Bool {
        didSet { UserDefaults.standard.set(preferEnglishAudio, forKey: Keys.preferEnglishAudio) }
    }

    /// Hide fully-watched titles from the Home discovery rows (Recently Added,
    /// TV Shows, Hidden Gems) so shelves only show things left to watch.
    var hideWatched: Bool {
        didSet { UserDefaults.standard.set(hideWatched, forKey: Keys.hideWatched) }
    }

    /// When true (default), an episode auto-advances to the next one as its
    /// credits end; off means the Up Next card still appears but waits for a click.
    var autoplayNextEpisode: Bool {
        didSet { UserDefaults.standard.set(autoplayNextEpisode, forKey: Keys.autoplayNextEpisode) }
    }

    /// Theater mode: detail pages play a muted highlight of the title behind
    /// the cover art, like a trailer.
    var theaterMode: Bool {
        didSet { UserDefaults.standard.set(theaterMode, forKey: Keys.theaterMode) }
    }

    /// Theme music: detail pages play the title's theme song (when the server
    /// has one), through the same volume button as theater mode.
    var themeMusic: Bool {
        didSet { UserDefaults.standard.set(themeMusic, forKey: Keys.themeMusic) }
    }

    /// Libraries the user hid from the Library tab — a client-side preference
    /// only; nothing changes on the Jellyfin server.
    var hiddenLibraryIDs: [String] {
        didSet { UserDefaults.standard.set(hiddenLibraryIDs, forKey: Keys.hiddenLibraryIDs) }
    }

    func isLibraryHidden(_ id: String) -> Bool { hiddenLibraryIDs.contains(id) }

    func toggleLibraryHidden(_ id: String) {
        if let index = hiddenLibraryIDs.firstIndex(of: id) {
            hiddenLibraryIDs.remove(at: index)
        } else {
            hiddenLibraryIDs.append(id)
        }
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
        static let nextUpFirst = "settings.nextUpFirst"
        static let preferEnglishAudio = "settings.preferEnglishAudio"
        static let hideWatched = "settings.hideWatched"
        static let autoplayNextEpisode = "settings.autoplayNextEpisode"
        static let theaterMode = "settings.theaterMode"
        static let themeMusic = "settings.themeMusic"
        static let hiddenLibraryIDs = "settings.hiddenLibraryIDs"
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
        nextUpFirst = UserDefaults.standard.object(forKey: Keys.nextUpFirst) as? Bool ?? true
        preferEnglishAudio = UserDefaults.standard.object(forKey: Keys.preferEnglishAudio) as? Bool ?? true
        hideWatched = UserDefaults.standard.object(forKey: Keys.hideWatched) as? Bool ?? false
        autoplayNextEpisode = UserDefaults.standard.object(forKey: Keys.autoplayNextEpisode) as? Bool ?? true
        theaterMode = UserDefaults.standard.object(forKey: Keys.theaterMode) as? Bool ?? true
        themeMusic = UserDefaults.standard.object(forKey: Keys.themeMusic) as? Bool ?? true
        hiddenLibraryIDs = UserDefaults.standard.stringArray(forKey: Keys.hiddenLibraryIDs) ?? []
        var layout = Self.load(Keys.homeLayout) ?? HomeLayoutPreferences()
        layout.normalize() // pick up any rows added in newer versions
        homeLayout = layout

        // One-time migration: dark became the default look. Installs that saved
        // an appearance blob under the old light default get flipped once; an
        // explicit choice made after this migration sticks forever.
        let darkDefaultFlag = "settings.migratedDarkDefault"
        if !UserDefaults.standard.bool(forKey: darkDefaultFlag) {
            UserDefaults.standard.set(true, forKey: darkDefaultFlag)
            if appearance.mode == .light {
                appearance.mode = .dark
                // didSet observers don't fire during init, so write through
                // explicitly — otherwise the migration reverts every launch.
                persist(appearance, key: Keys.appearance)
            }
        }
    }

    // MARK: - Home layout mutations

    /// Moves a row up or down in the Home order (used by the reorder controls,
    /// which work on tvOS where drag-to-reorder isn't available). The featured
    /// media bar is pinned to the top and can't be reordered.
    /// `isVisible` lets the caller mark rows that aren't currently on screen
    /// (disabled, or empty of content) so a move always hops past a row the
    /// user can actually see — otherwise a press "does nothing" while silently
    /// swapping with an invisible neighbor. The default treats every row as
    /// visible (the Home Layout editor lists them all, so adjacent moves are
    /// exactly right there).
    func moveHomeRow(_ kind: HomeRowKind, up: Bool, isVisible: (HomeRowKind) -> Bool = { _ in true }) {
        guard kind != .featured else { return }
        guard let i = homeLayout.rows.firstIndex(where: { $0.kind == kind }) else { return }
        let lower = homeLayout.rows.first?.kind == .featured ? 1 : 0
        var j = up ? i - 1 : i + 1
        while j >= lower, j < homeLayout.rows.count, !isVisible(homeLayout.rows[j].kind) {
            j += up ? -1 : 1
        }
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

    init() {}

    // Tolerant decoding (here and in every preference group below): fields
    // added in newer versions fall back to their defaults instead of failing
    // the whole blob — synthesized Decodable throws on a missing key even when
    // the property has a default, which silently reset entire settings groups
    // on app update.
    enum CodingKeys: String, CodingKey { case accent }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = (try? c.decodeIfPresent(AccentColor.self, forKey: .accent)) ?? .aurora
    }
}

struct AppearancePreferences: Codable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case system, dark, light
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    /// Dark by default — the cinematic look the app is designed around (light
    /// remains a first-class option in Settings → Appearance).
    var mode: Mode = .dark

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
        // OLED implies dark — otherwise adaptive text stays dark on a black
        // background and disappears.
        if oledMode { return .dark }
        switch mode {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    init() {}

    enum CodingKeys: String, CodingKey {
        case mode, richMotion, cardDensity, oledMode, ambientBackground
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? .dark
        richMotion = (try? c.decodeIfPresent(Bool.self, forKey: .richMotion)) ?? true
        cardDensity = (try? c.decodeIfPresent(CardDensity.self, forKey: .cardDensity)) ?? .regular
        oledMode = (try? c.decodeIfPresent(Bool.self, forKey: .oledMode)) ?? false
        ambientBackground = (try? c.decodeIfPresent(Bool.self, forKey: .ambientBackground)) ?? true
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

    init() {}

    enum CodingKeys: String, CodingKey {
        case loudnessNormalization, dialogueEnhancement, passthrough, preferredLanguage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        loudnessNormalization = (try? c.decodeIfPresent(Bool.self, forKey: .loudnessNormalization)) ?? false
        dialogueEnhancement = (try? c.decodeIfPresent(DialogueEnhancement.self, forKey: .dialogueEnhancement)) ?? .off
        passthrough = (try? c.decodeIfPresent(Bool.self, forKey: .passthrough)) ?? false
        preferredLanguage = (try? c.decodeIfPresent(String.self, forKey: .preferredLanguage)) ?? ""
    }
}

struct VideoPreferences: Codable {
    /// Allow HDR10 / Dolby Vision passthrough when the show and TV support it.
    var allowHDR: Bool = true
    /// Match the TV's refresh rate and dynamic range to the content.
    var matchContent: Bool = true
    /// Starting quality for new playback (the in-player Quality menu can still
    /// override per-session).
    var defaultQuality: QualityOption = .auto

    init() {}

    enum CodingKeys: String, CodingKey { case allowHDR, matchContent, defaultQuality }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allowHDR = (try? c.decodeIfPresent(Bool.self, forKey: .allowHDR)) ?? true
        matchContent = (try? c.decodeIfPresent(Bool.self, forKey: .matchContent)) ?? true
        defaultQuality = (try? c.decodeIfPresent(QualityOption.self, forKey: .defaultQuality)) ?? .auto
    }
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
        case small, medium, large, huge
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// VLC text-scale / AVPlayer relative-size percentage.
        var scalePercent: Int {
            switch self { case .small: 75; case .medium: 100; case .large: 150; case .huge: 200 }
        }
    }
    var size: Size = .medium

    enum TextColor: String, Codable, CaseIterable, Identifiable {
        case white, yellow, cyan, green, orange
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// VLC RGB integer.
        var vlcColor: Int {
            switch self {
            case .white: 0xFFFFFF
            case .yellow: 0xFFFF00
            case .cyan: 0x00FFFF
            case .green: 0x00FF00
            case .orange: 0xFFA500
            }
        }
        /// AVPlayer text-markup ARGB components (0–1).
        var argb: [NSNumber] {
            let rgb = vlcColor
            return [1,
                    NSNumber(value: Double((rgb >> 16) & 0xFF) / 255),
                    NSNumber(value: Double((rgb >> 8) & 0xFF) / 255),
                    NSNumber(value: Double(rgb & 0xFF) / 255)]
        }
        /// Swatch/preview color.
        var color: Color {
            switch self {
            case .white: .white
            case .yellow: Color(hex: 0xFFFF00)
            case .cyan: Color(hex: 0x00FFFF)
            case .green: Color(hex: 0x00FF00)
            case .orange: Color(hex: 0xFFA500)
            }
        }
    }
    var textColor: TextColor = .white

    /// The caption typeface — three distinct voices.
    enum CaptionFont: String, Codable, CaseIterable, Identifiable {
        case standard, serif, typewriter
        var id: String { rawValue }
        var label: String {
            switch self {
            case .standard: "Standard"
            case .serif: "Serif"
            case .typewriter: "Typewriter"
            }
        }
        /// Family name for both VLC freetype and AVPlayer text-markup rules.
        var fontName: String {
            switch self {
            case .standard: "Helvetica Neue"
            case .serif: "Georgia"
            case .typewriter: "Courier New"
            }
        }
        /// Preview font for the settings screen.
        func previewFont(size: CGFloat, bold: Bool) -> Font {
            .custom(fontName, size: size).weight(bold ? .bold : .regular)
        }
    }
    var font: CaptionFont = .standard

    /// Optional black box behind the text for busy scenes.
    enum Background: String, Codable, CaseIterable, Identifiable {
        case off, box
        var id: String { rawValue }
        var label: String { self == .off ? "None" : "Black box" }
    }
    var background: Background = .off

    var boldText: Bool = false

    /// Preferred subtitle language (ISO code), or empty for none/auto.
    var preferredLanguage: String = ""

    init() {}

    // Tolerant decoding: fields added in newer versions fall back to their
    // defaults instead of failing the whole blob (which would silently reset
    // every subtitle preference on update).
    enum CodingKeys: String, CodingKey {
        case captionMode, size, textColor, font, background, boldText, preferredLanguage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        captionMode = (try? c.decodeIfPresent(CaptionMode.self, forKey: .captionMode)) ?? .off
        size = (try? c.decodeIfPresent(Size.self, forKey: .size)) ?? .medium
        textColor = (try? c.decodeIfPresent(TextColor.self, forKey: .textColor)) ?? .white
        font = (try? c.decodeIfPresent(CaptionFont.self, forKey: .font)) ?? .standard
        background = (try? c.decodeIfPresent(Background.self, forKey: .background)) ?? .off
        boldText = (try? c.decodeIfPresent(Bool.self, forKey: .boldText)) ?? false
        preferredLanguage = (try? c.decodeIfPresent(String.self, forKey: .preferredLanguage)) ?? ""
    }
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

    init() {}

    enum CodingKeys: String, CodingKey { case quality, maxStorageGB, allowCellular }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quality = (try? c.decodeIfPresent(Quality.self, forKey: .quality)) ?? .high
        maxStorageGB = (try? c.decodeIfPresent(Int.self, forKey: .maxStorageGB)) ?? 10
        allowCellular = (try? c.decodeIfPresent(Bool.self, forKey: .allowCellular)) ?? false
    }
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
    case comingUp // merged into Continue Watching; kept for decode compatibility
    case recentlyAdded
    case recentShows
    case favorites
    case hiddenGems
    case libraries

    /// Rows that appear in the Home Layout editor (Coming Up is folded into
    /// Continue Watching, so it isn't independently arrangeable).
    static var layoutKinds: [HomeRowKind] { allCases.filter { $0 != .comingUp } }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: "Featured Banner"
        case .continueWatching: "Continue Watching"
        case .comingUp: "Coming Up"
        case .recentlyAdded: "Recently Added"
        case .recentShows: "Recently Added TV Shows"
        case .favorites: "Favorites"
        case .hiddenGems: "Hidden Gems"
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
        case .hiddenGems: "diamond"
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
        case shuffle, recentlyAdded, continueWatching, both
        var id: String { rawValue }
        var label: String {
            switch self {
            case .shuffle: "Shuffle (whole library)"
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
    var source: Source = .shuffle
    /// Number of items in the media bar; 0 means "show all".
    var itemCount: Int = 15
    /// Libraries that feed the bar. Empty means all libraries.
    var sourceLibraryIDs: [String] = []
    /// Automatically rotate through items.
    var autoAdvance: Bool = true
    /// Seconds between rotations.
    var rotationSeconds: Int = 8

    init() {}

    enum CodingKeys: String, CodingKey {
        case contentType, source, itemCount, sourceLibraryIDs, autoAdvance, rotationSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contentType = (try? c.decodeIfPresent(ContentType.self, forKey: .contentType)) ?? .all
        source = (try? c.decodeIfPresent(Source.self, forKey: .source)) ?? .shuffle
        itemCount = (try? c.decodeIfPresent(Int.self, forKey: .itemCount)) ?? 15
        sourceLibraryIDs = (try? c.decodeIfPresent([String].self, forKey: .sourceLibraryIDs)) ?? []
        autoAdvance = (try? c.decodeIfPresent(Bool.self, forKey: .autoAdvance)) ?? true
        rotationSeconds = (try? c.decodeIfPresent(Int.self, forKey: .rotationSeconds)) ?? 8
    }
}

/// Ordered, toggleable set of Home rows.
struct HomeLayoutPreferences: Codable {
    var rows: [HomeRowConfig]

    init() {
        rows = HomeRowKind.allCases.map { HomeRowConfig(kind: $0, isEnabled: true) }
    }

    enum CodingKeys: String, CodingKey { case rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = (try? c.decodeIfPresent([HomeRowConfig].self, forKey: .rows))
            ?? HomeRowKind.allCases.map { HomeRowConfig(kind: $0, isEnabled: true) }
    }

    /// Ensures the stored list contains every known row exactly once, appending
    /// any newly-added kinds and dropping unknown ones (forward/backward compat).
    mutating func normalize() {
        var seen = Set<HomeRowKind>()
        // Drop de-duped rows and any kind no longer surfaced in the layout
        // (e.g. the legacy Coming Up row, now folded into Continue Watching).
        rows = rows.filter { HomeRowKind.layoutKinds.contains($0.kind) && seen.insert($0.kind).inserted }
        for kind in HomeRowKind.layoutKinds where !seen.contains(kind) {
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

    init() {}

    enum CodingKeys: String, CodingKey {
        case enginePolicy, autoResume, seekInterval, preferredSubtitleLanguage, maxBufferSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enginePolicy = (try? c.decodeIfPresent(EnginePolicy.self, forKey: .enginePolicy)) ?? .hybrid
        autoResume = (try? c.decodeIfPresent(Bool.self, forKey: .autoResume)) ?? true
        seekInterval = (try? c.decodeIfPresent(Int.self, forKey: .seekInterval)) ?? 15
        preferredSubtitleLanguage = (try? c.decodeIfPresent(String.self, forKey: .preferredSubtitleLanguage)) ?? "eng"
        maxBufferSeconds = (try? c.decodeIfPresent(Int.self, forKey: .maxBufferSeconds)) ?? 30
    }
}
