import Foundation

/// A synthetic broadcast schedule built from the library.
///
/// Jellyfin has no live television, so there is nothing to read a listing from —
/// the guide has to invent one. It does that deterministically: every channel
/// runs its lineup end to end on a loop from a fixed epoch, so the same title is
/// "on" at the same moment on every device, across relaunches, without anything
/// being stored. What makes it feel live is only the clock moving through it.
///
/// Slots are rounded up to the half hour the way a real listing is. That isn't
/// decoration — it's what lets every block in the grid land on a column boundary
/// instead of drifting a few pixels out of alignment down the page.
enum GuideSchedule {
    /// The half-hour grid all listings snap to.
    static let slot: TimeInterval = 30 * 60

    /// A fixed, arbitrary Sunday midnight UTC. Any constant on a half-hour
    /// boundary works; it only has to never change.
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// How long a title occupies the air: its own runtime, rounded up to the
    /// next half hour, and never less than one slot.
    static func airtime(for item: MediaItem) -> TimeInterval {
        let runtime = Double(item.runTimeTicks ?? 0) / 10_000_000
        // Series have no runtime of their own — an hour is the honest guess for
        // "a show", and it keeps a channel of them from becoming a wall of
        // identical half-hour blocks.
        let assumed = runtime > 0 ? runtime : (item.type == .series ? 45 * 60 : 90 * 60)
        return max(slot, (assumed / slot).rounded(.up) * slot)
    }
}

/// One programme in the grid: a library item placed at a time.
struct GuideProgram: Identifiable, Hashable, Sendable {
    let channelID: String
    let item: MediaItem
    let start: Date
    let duration: TimeInterval

    /// Unique per airing, not per title — the same film shows up again later in
    /// the loop and the two must not collapse into one focus target.
    var id: String { "\(channelID)@\(Int(start.timeIntervalSince1970))" }
    var end: Date { start.addingTimeInterval(duration) }

    func isOnAir(at moment: Date) -> Bool { moment >= start && moment < end }
}

/// A channel: a themed lineup with a number and a callsign, like a real one.
struct GuideChannel: Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let callsign: String
    let name: String
    let lineup: [MediaItem]

    /// How long the whole lineup takes to play through once.
    var cycle: TimeInterval {
        lineup.reduce(0) { $0 + GuideSchedule.airtime(for: $1) }
    }

    /// Everything airing between `from` and `to`, including a programme already
    /// under way when the window opens — that one is what you're watching now,
    /// so leaving it out would be the one omission you'd notice.
    func programs(from: Date, to: Date) -> [GuideProgram] {
        let cycle = self.cycle
        guard cycle > 0, !lineup.isEmpty, to > from else { return [] }

        // Rewind to the start of the loop the window opens in, then walk forward.
        let elapsed = from.timeIntervalSince(GuideSchedule.epoch)
        let loops = (elapsed / cycle).rounded(.down)
        var cursor = GuideSchedule.epoch.addingTimeInterval(loops * cycle)
        var index = 0
        var out: [GuideProgram] = []

        // The lineup can't be walked more than a couple of times over a window
        // this size; the cap is a backstop against a pathological cycle, not a
        // real limit.
        while cursor < to && out.count < 400 {
            let item = lineup[index % lineup.count]
            let airtime = GuideSchedule.airtime(for: item)
            if cursor.addingTimeInterval(airtime) > from {
                out.append(GuideProgram(channelID: id, item: item,
                                        start: cursor, duration: airtime))
            }
            cursor.addTimeInterval(airtime)
            index += 1
        }
        return out
    }

    /// What's on right now.
    func nowPlaying(at moment: Date) -> GuideProgram? {
        programs(from: moment, to: moment.addingTimeInterval(1)).first { $0.isOnAir(at: moment) }
    }
}

/// Builds the channel lineup out of whatever the library holds.
enum GuideLineup {
    /// Channels need enough titles to be worth watching; below this a genre is
    /// folded into the catch-all rather than becoming a channel that loops every
    /// twenty minutes.
    private static let minimumTitles = 4
    private static let maximumChannels = 12

    /// Genre channels, newest-first house channels either side.
    ///
    /// Ordering is by title count, so the library's real centre of gravity ends
    /// up near the top of the guide where the remote lands first.
    static func channels(from items: [MediaItem]) -> [GuideChannel] {
        let watchable = items.filter { $0.type == .movie || $0.type == .series }
        guard !watchable.isEmpty else { return [] }

        var byGenre: [String: [MediaItem]] = [:]
        var ungrouped: [MediaItem] = []
        for item in watchable {
            if let genre = item.genres?.first, !genre.isEmpty {
                byGenre[genre, default: []].append(item)
            } else {
                ungrouped.append(item)
            }
        }

        let strong = byGenre
            .filter { $0.value.count >= minimumTitles }
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
            .prefix(maximumChannels)

        // Genres too thin to stand alone still deserve to air somewhere.
        let leftovers = ungrouped + byGenre.filter { $0.value.count < minimumTitles }
            .flatMap(\.value)

        var channels: [GuideChannel] = []
        var number = 101

        let mixed = watchable.count > 1 ? shuffled(watchable, salt: "ultra") : watchable
        channels.append(GuideChannel(id: "ultra", number: 100, callsign: "ULTRA",
                                     name: "Ultrafin Mix", lineup: mixed))
        for (genre, titles) in strong {
            channels.append(GuideChannel(id: genre, number: number,
                                         callsign: callsign(for: genre), name: genre,
                                         lineup: shuffled(titles, salt: genre)))
            number += 1
        }
        if leftovers.count >= minimumTitles {
            channels.append(GuideChannel(id: "mixed", number: number, callsign: "MIX",
                                         name: "Everything Else",
                                         lineup: shuffled(leftovers, salt: "mixed")))
        }
        return channels
    }

    /// A four-letter callsign, the way a real channel wears its name.
    private static func callsign(for genre: String) -> String {
        let letters = genre.uppercased().filter { $0.isLetter }
        guard letters.count > 4 else { return String(letters) }
        // Drop vowels after the first letter — ACTION becomes ACTN, the trick
        // every broadcaster uses to fit a name into four characters.
        var out = [letters.first!]
        for ch in letters.dropFirst() where !"AEIOU".contains(ch) {
            out.append(ch)
            if out.count == 4 { break }
        }
        while out.count < 4, let filler = letters.dropFirst(out.count).first { out.append(filler) }
        return String(out.prefix(4))
    }

    /// A stable shuffle. `Array.shuffled()` would reorder on every launch and
    /// the schedule has to be the same every time it's built, or "what's on now"
    /// changes each time you open the guide.
    private static func shuffled(_ items: [MediaItem], salt: String) -> [MediaItem] {
        items.sorted { hash(salt + $0.id) < hash(salt + $1.id) }
    }

    private static func hash(_ string: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325 // FNV-1a
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100000001b3
        }
        return value
    }
}
