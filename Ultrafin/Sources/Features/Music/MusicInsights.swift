import SwiftUI

/// A snapshot of the user's listening — the data behind the Music Identity
/// screen. Computed locally from a sample of played songs (with play counts,
/// genres and artists) so it works the same on Jellyfin and Navidrome.
struct MusicInsights: Sendable {
    struct Ranked: Identifiable, Sendable {
        let name: String
        let plays: Int
        var id: String { name }
    }

    var totalPlays: Int = 0
    var estimatedMinutes: Int = 0
    var distinctArtists: Int = 0
    var distinctGenres: Int = 0
    var topArtists: [Ranked] = []
    var topGenres: [Ranked] = []
    var topSongs: [MediaItem] = []
    /// The genre the user leans into most.
    var signatureGenre: String?
    /// A rough era label from the years of their most-played music.
    var eraLabel: String?
    /// 0–100: how far the taste tips toward a signature vs. spread wide. High =
    /// a defined, concentrated identity; low = an eclectic, everything listener.
    var focusScore: Int = 0

    var isEmpty: Bool { topSongs.isEmpty && totalPlays == 0 }

    /// A short, human "identity" line derived from focus + breadth.
    var personality: String {
        if isEmpty { return "Just getting started" }
        switch focusScore {
        case 70...: return "The Devotee"
        case 45..<70: return "The Curator"
        case 25..<45: return "The Explorer"
        default: return "The Omnivore"
        }
    }

    /// The signature summed up in one line for the identity card.
    var tagline: String {
        var parts: [String] = []
        if let signatureGenre { parts.append(signatureGenre) }
        if let eraLabel { parts.append(eraLabel) }
        return parts.isEmpty ? "A world of your own" : parts.joined(separator: " · ")
    }

    // MARK: - Compute

    static func compute(from songs: [MediaItem]) -> MusicInsights {
        var out = MusicInsights()
        guard !songs.isEmpty else { return out }

        var artistPlays: [String: Int] = [:]
        var genrePlays: [String: Int] = [:]
        var yearWeight: [Int: Int] = [:]
        var totalPlays = 0
        var minutes = 0.0

        for song in songs {
            // Weight by plays, but let a played-but-uncounted song (some servers
            // report 0) still register once so it isn't invisible.
            let plays = max(song.playCount, 1)
            totalPlays += song.playCount
            minutes += Double(plays) * song.runtimeSeconds / 60.0

            if let artist = song.primaryArtist {
                artistPlays[artist, default: 0] += plays
            }
            for genre in song.genres ?? [] where !genre.isEmpty {
                genrePlays[genre, default: 0] += plays
            }
            if let year = song.productionYear, year > 1900 {
                yearWeight[year, default: 0] += plays
            }
        }

        out.totalPlays = totalPlays
        out.estimatedMinutes = Int(minutes.rounded())
        out.distinctArtists = artistPlays.count
        out.distinctGenres = genrePlays.count

        out.topArtists = artistPlays
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(8).map { Ranked(name: $0.key, plays: $0.value) }
        out.topGenres = genrePlays
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(6).map { Ranked(name: $0.key, plays: $0.value) }
        // The sample is already play-count sorted, so the leaders are the top songs.
        out.topSongs = Array(songs.prefix(10))
        out.signatureGenre = out.topGenres.first?.name

        // Era: the play-weighted average year, bucketed to a decade.
        let weightTotal = yearWeight.values.reduce(0, +)
        if weightTotal > 0 {
            let weightedYear = yearWeight.reduce(0) { $0 + $1.key * $1.value } / weightTotal
            let decade = (weightedYear / 10) * 10
            out.eraLabel = decade >= 1950 ? "\(decade)s" : nil
        }

        // Focus: how much of all listening the single top genre commands.
        if let topGenre = out.topGenres.first, weightForGenres(genrePlays) > 0 {
            let share = Double(topGenre.plays) / Double(weightForGenres(genrePlays))
            out.focusScore = min(100, Int((share * 100).rounded()))
        } else if let topArtist = out.topArtists.first, totalPlays > 0 {
            let share = Double(topArtist.plays) / Double(totalPlays)
            out.focusScore = min(100, Int((share * 100).rounded()))
        }

        return out
    }

    private static func weightForGenres(_ genrePlays: [String: Int]) -> Int {
        genrePlays.values.reduce(0, +)
    }
}
