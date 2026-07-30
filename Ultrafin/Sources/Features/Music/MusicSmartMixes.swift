import SwiftUI

/// An app-generated playlist built from the user's own listening — no setup,
/// they just appear and refresh. Modeled after Apple Music's "Made For You"
/// mixes, drawn from Jellyfin/Navidrome play data.
struct SmartMix: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case onRepeat, discovery, favorites, recentlyPlayed
        var id: String { rawValue }
    }

    let kind: Kind
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .onRepeat: "On Repeat"
        case .discovery: "Discovery"
        case .favorites: "Favorites Mix"
        case .recentlyPlayed: "Recently Played"
        }
    }

    var subtitle: String {
        switch kind {
        case .onRepeat: "The songs you can't stop playing"
        case .discovery: "Gems you haven't heard yet"
        case .favorites: "Everything you've hearted, shuffled"
        case .recentlyPlayed: "Pick up where you left off"
        }
    }

    var systemImage: String {
        switch kind {
        case .onRepeat: "repeat"
        case .discovery: "sparkles"
        case .favorites: "heart.fill"
        case .recentlyPlayed: "clock.arrow.circlepath"
        }
    }

    /// The tile gradient — each mix reads as its own distinct artwork.
    var colors: [Color] {
        switch kind {
        case .onRepeat: [Color(hex: 0x8E2DE2), Color(hex: 0xE94057)]
        case .discovery: [Color(hex: 0x11998E), Color(hex: 0x38BDF8)]
        case .favorites: [Color(hex: 0xFF512F), Color(hex: 0xDD2476)]
        case .recentlyPlayed: [Color(hex: 0x2B32B2), Color(hex: 0x6D8BFF)]
        }
    }

    static let all: [SmartMix] = Kind.allCases.map { SmartMix(kind: $0) }

    // MARK: - Weekly rotation

    /// Mixes settle for a week at a time, the way Apple Music's do: the track
    /// list is captured once and reused until the week turns over, so a mix
    /// doesn't reshuffle every time the tab is opened.
    private static var weekKey: String {
        let calendar = Calendar(identifier: .iso8601)
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(parts.yearForWeekOfYear ?? 0)-W\(parts.weekOfYear ?? 0)"
    }

    private var cacheKey: String { "music.mix.\(kind.rawValue)" }
    private var stampKey: String { "music.mix.\(kind.rawValue).week" }

    /// This week's saved track ids, or nil when the week has turned.
    private var cachedIDs: [String]? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: stampKey) == Self.weekKey,
              let ids = defaults.stringArray(forKey: cacheKey), !ids.isEmpty
        else { return nil }
        return ids
    }

    private func cache(_ tracks: [MediaItem]) {
        let defaults = UserDefaults.standard
        defaults.set(tracks.map(\.id), forKey: cacheKey)
        defaults.set(Self.weekKey, forKey: stampKey)
    }

    /// Wipe every mix's snapshot, so the next visit rebuilds them.
    static func refreshNow() {
        let defaults = UserDefaults.standard
        for kind in Kind.allCases {
            defaults.removeObject(forKey: "music.mix.\(kind.rawValue).week")
        }
    }

    /// This mix's tracks, held steady for the week. Recently Played is the one
    /// exception — it's meant to be live, so it always reflects right now.
    func load(from source: MusicSource) async -> [MediaItem] {
        let fresh = await fetch(from: source)
        guard kind != .recentlyPlayed else { return fresh }

        // Reuse this week's selection when we still have those songs.
        if let ids = cachedIDs {
            let byID = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let kept = ids.compactMap { byID[$0] }
            // Only honour the snapshot while most of it still exists; a library
            // that changed a lot deserves a rebuild.
            if kept.count >= max(1, ids.count / 2) { return kept }
        }
        cache(fresh)
        return fresh
    }

    /// Fetches this mix's tracks from whichever backend is active.
    private func fetch(from source: MusicSource) async -> [MediaItem] {
        switch kind {
        case .onRepeat:
            return (try? await source.mostPlayedSongs()) ?? []
        case .discovery:
            return (try? await source.discoverySongs()) ?? []
        case .favorites:
            var songs = (try? await source.favoriteSongs()) ?? []
            songs.shuffle()
            return songs
        case .recentlyPlayed:
            return (try? await source.recentlyPlayedSongs()) ?? []
        }
    }
}
