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

    /// Fetches this mix's tracks from whichever backend is active.
    func load(from source: MusicSource) async -> [MediaItem] {
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
