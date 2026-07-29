import Foundation
import Network
import Observation

/// Watches whether the device is on an expensive link, so downloads can respect
/// the "download over cellular" preference instead of quietly burning data.
final class NetworkCost: @unchecked Sendable {
    static let shared = NetworkCost()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var expensive = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.expensive = path.isExpensive || path.isConstrained
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "com.ultrafin.network-cost"))
    }

    /// True on cellular or a personal hotspot / low-data connection.
    var isExpensive: Bool {
        lock.lock(); defer { lock.unlock() }
        return expensive
    }
}

/// On-device music storage with two tiers:
///
/// * **Downloads** — songs and albums the user explicitly kept. Pinned; never
///   removed automatically.
/// * **Cache** — songs that earn their place by being played. After a few
///   plays a song is quietly kept on disk; if it then goes unplayed for two
///   weeks it's evicted to give the space back.
///
/// iPhone/iPad only — a TV is always on the network and has little room to
/// spare, so every call is a no-op there and the UI isn't offered.
@Observable
@MainActor
final class MusicLibraryCache {
    static let shared = MusicLibraryCache()

    /// Downloads only make sense where the device leaves the network.
    static var isSupported: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// Plays before a song earns a place in the cache.
    private static let autoCacheThreshold = 3
    /// How long a cached (unpinned) song survives without being played.
    private static let staleInterval: TimeInterval = 14 * 24 * 60 * 60

    // MARK: - Index

    /// What we know about one stored song. Enough metadata to render it while
    /// offline, without a round trip.
    struct Entry: Codable, Sendable, Identifiable {
        var trackID: String
        var fileName: String
        var bytes: Int64
        /// True for an explicit download — exempt from eviction.
        var isPinned: Bool
        var playCount: Int
        var lastPlayed: Date
        var title: String
        var artist: String?
        var album: String?
        var albumID: String?
        var runTimeTicks: Int64?
        /// How many songs the parent release has in total, when we knew it at
        /// download time. Lets the UI say "3 of 12" instead of implying a whole
        /// album is here when only one song is.
        var albumTotal: Int?

        var id: String { trackID }
    }

    /// What's actually on the device for one release.
    struct AlbumSummary: Identifiable, Sendable {
        let albumID: String
        let title: String
        let artist: String?
        let storedCount: Int
        let total: Int?
        let bytes: Int64
        /// A representative track, for artwork lookup.
        let sampleTrackID: String

        var id: String { albumID }

        /// True when the release is a single — one song, and that's all there is.
        var isSingle: Bool { total == 1 }
        /// True when every song of a multi-track album is here.
        var isComplete: Bool {
            guard let total else { return false }
            return storedCount >= total && total > 1
        }

        /// "Single" · "Album · 12 songs" · "3 of 12 songs".
        var subtitle: String {
            if isSingle { return "Single" }
            guard let total else {
                return "\(storedCount) song\(storedCount == 1 ? "" : "s")"
            }
            if storedCount >= total { return "Album · \(total) songs" }
            return "\(storedCount) of \(total) songs"
        }
    }

    private(set) var entries: [String: Entry] = [:]

    /// Live progress for a running bulk job (download-all or sync).
    private(set) var jobLabel: String?
    private(set) var jobProgress: Double = 0
    var isWorking: Bool { jobLabel != nil }

    /// Track IDs currently being fetched, so the UI can show a spinner per row.
    private(set) var inFlight: Set<String> = []

    /// Set when a download was skipped because the device is on cellular and
    /// the user hasn't allowed it — the storage screen surfaces this.
    var lastBlockedByCellular = false

    // MARK: - Paths

    private let root: URL
    private let audioDirectory: URL
    private let indexURL: URL

    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = base.appendingPathComponent("UltrafinMusic", isDirectory: true)
        audioDirectory = root.appendingPathComponent("Audio", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        loadIndex()
    }

    // MARK: - Lookup

    /// A playable local file for this track, or nil if it isn't stored.
    func localURL(for trackID: String) -> URL? {
        guard let entry = entries[trackID] else { return nil }
        let url = audioDirectory.appendingPathComponent(entry.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Index drifted from disk (user cleared storage) — forget it.
            entries[trackID] = nil
            saveIndex()
            return nil
        }
        return url
    }

    func isStored(_ trackID: String) -> Bool { localURL(for: trackID) != nil }
    func isDownloaded(_ trackID: String) -> Bool { entries[trackID]?.isPinned == true }
    func isFetching(_ trackID: String) -> Bool { inFlight.contains(trackID) }

    /// Bytes held by explicit downloads and by the automatic cache.
    var downloadedBytes: Int64 { entries.values.filter(\.isPinned).reduce(0) { $0 + $1.bytes } }
    var cachedBytes: Int64 { entries.values.filter { !$0.isPinned }.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { downloadedBytes + cachedBytes }
    var downloadedCount: Int { entries.values.filter(\.isPinned).count }
    var cachedCount: Int { entries.values.filter { !$0.isPinned }.count }

    /// How many songs of a given release are on the device.
    func storedCount(forAlbum albumID: String) -> Int {
        entries.values.filter { $0.albumID == albumID }.count
    }

    /// What's downloaded, grouped by release — so a single reads as a single and
    /// three songs off a twelve-track record read as "3 of 12", never as an
    /// album you own outright.
    func downloadedAlbums() -> [AlbumSummary] {
        let pinned = entries.values.filter(\.isPinned)
        let groups = Dictionary(grouping: pinned) { $0.albumID ?? "single:\($0.trackID)" }
        return groups.compactMap { key, items -> AlbumSummary? in
            guard let first = items.first else { return nil }
            return AlbumSummary(
                albumID: key,
                title: first.album ?? first.title,
                artist: first.artist,
                storedCount: items.count,
                // The largest recorded total wins; nil when we never learned it.
                total: items.compactMap(\.albumTotal).max(),
                bytes: items.reduce(0) { $0 + $1.bytes },
                sampleTrackID: first.trackID
            )
        }
        .sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// The individual pinned tracks of a release, in track order where known.
    func downloadedTracks(inAlbum albumID: String) -> [Entry] {
        entries.values
            .filter { $0.isPinned && ($0.albumID ?? "single:\($0.trackID)") == albumID }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Play tracking

    /// Called when a song starts. Records the play and, once a song has proven
    /// itself, quietly keeps a copy so the next listen is instant and offline.
    func notePlay(of track: MediaItem, source: MusicSource) {
        guard Self.isSupported else { return }
        if var entry = entries[track.id] {
            entry.playCount += 1
            entry.lastPlayed = Date()
            entries[track.id] = entry
            saveIndex()
            return
        }
        let count = (playCounts[track.id] ?? 0) + 1
        playCounts[track.id] = count
        guard SettingsStore.shared.cacheFrequentSongs, count >= Self.autoCacheThreshold else { return }
        Task { await store(track, source: source, pinned: false) }
    }

    /// Plays seen this run for songs not yet stored — the runway to caching.
    private var playCounts: [String: Int] = [:]

    // MARK: - Storing

    /// Download one song. `pinned` marks it an explicit download. `albumTotal`
    /// is the parent release's full track count when the caller knows it, so a
    /// partial album can be shown as partial rather than passing for complete.
    @discardableResult
    func store(_ track: MediaItem, source: MusicSource, pinned: Bool,
               albumTotal: Int? = nil) async -> Bool {
        guard Self.isSupported else { return false }
        // Already here: an explicit download promotes a cached copy, and a
        // newly-known album size fills in a blank.
        if var existing = entries[track.id] {
            var changed = false
            if pinned && !existing.isPinned { existing.isPinned = true; changed = true }
            if existing.albumTotal == nil, albumTotal != nil { existing.albumTotal = albumTotal; changed = true }
            if changed {
                entries[track.id] = existing
                saveIndex()
            }
            return true
        }
        // Respect the data preference — on cellular, wait for Wi-Fi.
        guard SettingsStore.shared.downloadOverCellular || !NetworkCost.shared.isExpensive else {
            lastBlockedByCellular = true
            return false
        }
        guard !inFlight.contains(track.id) else { return false }
        inFlight.insert(track.id)
        defer { inFlight.remove(track.id) }

        guard let remote = await source.audioStreamURL(itemID: track.id) else { return false }
        let ext = (track.container?.isEmpty == false ? track.container! : "m4a")
        let fileName = "\(track.id).\(ext)"
        let destination = audioDirectory.appendingPathComponent(fileName)

        do {
            let (temp, response) = try await URLSession.shared.download(from: remote)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: temp)
                return false
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            var bytes: Int64 = 0
            if let values = try? destination.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                bytes = Int64(size)
            }
            // The cache tier is reproducible from the server — keep it out of
            // the user's iCloud backup. Downloads are intentional, so they stay.
            if !pinned { excludeFromBackup(destination) }

            entries[track.id] = Entry(trackID: track.id, fileName: fileName, bytes: bytes,
                                      isPinned: pinned, playCount: playCounts[track.id] ?? 1,
                                      lastPlayed: Date(), title: track.name,
                                      artist: track.artistText, album: track.album,
                                      albumID: track.albumId, runTimeTicks: track.runTimeTicks,
                                      albumTotal: albumTotal)
            saveIndex()
            return true
        } catch {
            return false
        }
    }

    /// Download a whole album/playlist. Every track records the release's full
    /// size, so the result is recognisably a complete album (or a single).
    func store(tracks: [MediaItem], source: MusicSource, label: String,
               albumTotal: Int? = nil) async {
        guard Self.isSupported, !tracks.isEmpty else { return }
        jobLabel = label
        jobProgress = 0
        defer { jobLabel = nil; jobProgress = 0 }
        for (index, track) in tracks.enumerated() {
            if Task.isCancelled { return }
            await store(track, source: source, pinned: true, albumTotal: albumTotal)
            jobProgress = Double(index + 1) / Double(tracks.count)
        }
    }

    /// Download every song in the library.
    func downloadEntireLibrary(source: MusicSource) async {
        guard Self.isSupported else { return }
        jobLabel = "Preparing…"
        let songs = (try? await source.allSongs()) ?? []
        guard !songs.isEmpty else { jobLabel = nil; return }
        await store(tracks: songs, source: source, label: "Downloading library")
    }

    /// Reconcile with the server: drop songs that no longer exist, and re-fetch
    /// any download whose file went missing.
    func sync(source: MusicSource) async {
        guard Self.isSupported else { return }
        jobLabel = "Syncing…"
        jobProgress = 0
        defer { jobLabel = nil; jobProgress = 0 }

        let songs = (try? await source.allSongs()) ?? []
        guard !songs.isEmpty else { return }
        let live = Set(songs.map(\.id))
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Gone from the server — remove locally too.
        for id in entries.keys where !live.contains(id) { remove(id) }

        // Pinned downloads whose file vanished get fetched again.
        let missing = entries.values
            .filter { $0.isPinned && !FileManager.default.fileExists(
                atPath: audioDirectory.appendingPathComponent($0.fileName).path) }
            .compactMap { byID[$0.trackID] }

        for (index, track) in missing.enumerated() {
            if Task.isCancelled { return }
            entries[track.id] = nil
            await store(track, source: source, pinned: true)
            jobProgress = Double(index + 1) / Double(max(missing.count, 1))
        }
        evictStale()
    }

    // MARK: - Removing

    /// Drop songs the cache hasn't seen played in two weeks. Downloads are
    /// exempt — the user asked for those.
    func evictStale() {
        guard Self.isSupported else { return }
        let cutoff = Date().addingTimeInterval(-Self.staleInterval)
        let stale = entries.values.filter { !$0.isPinned && $0.lastPlayed < cutoff }
        guard !stale.isEmpty else { return }
        for entry in stale { remove(entry.trackID) }
    }

    /// Everything the cache put there — downloads survive.
    func clearCache() {
        for entry in entries.values where !entry.isPinned { remove(entry.trackID) }
        playCounts.removeAll()
    }

    /// Every explicit download — the cache survives.
    func removeAllDownloads() {
        for entry in entries.values where entry.isPinned { remove(entry.trackID) }
    }

    func removeEverything() {
        for id in Array(entries.keys) { remove(id) }
        playCounts.removeAll()
    }

    /// Un-download a single track (or un-cache it).
    func remove(_ trackID: String) {
        guard let entry = entries[trackID] else { return }
        let url = audioDirectory.appendingPathComponent(entry.fileName)
        try? FileManager.default.removeItem(at: url)
        entries[trackID] = nil
        saveIndex()
    }

    // MARK: - Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return }
        entries = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }
}

/// Human-readable byte counts for the storage UI.
enum StorageFormat {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
