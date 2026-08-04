import SwiftUI
import AVFoundation
import Observation

/// One slot in the play queue.
///
/// Identity is per-slot, not per-song, so the same track can legitimately sit
/// in the queue more than once — a playlist that repeats a song, or the same
/// song queued twice by hand — and dragging a row moves the row you grabbed
/// rather than the first one that happens to share its id.
struct QueueEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let track: MediaItem
    /// Added by hand rather than coming from the album or playlist being
    /// played. Hand-picked songs jump ahead of the record and drain as they go.
    var isManual: Bool

    init(_ track: MediaItem, isManual: Bool = false) {
        self.id = UUID()
        self.track = track
        self.isManual = isManual
    }
}

/// The app-wide music engine: one queue, one player, alive across every tab.
///
/// Handles the whole listening session — queue with shuffle and repeat,
/// gapless-ish advance, synced lyrics, system Now Playing (Control Center /
/// lock screen / the TV's transport), and play reporting to whichever backend
/// (Jellyfin or Navidrome) the queue came from — so views only render state.
@Observable
@MainActor
final class MusicPlayer {
    static let shared = MusicPlayer()

    enum RepeatMode: CaseIterable {
        case off, all, one
        var icon: String {
            switch self {
            case .off, .all: "repeat"
            case .one: "repeat.1"
            }
        }
    }

    // MARK: - Published state

    private(set) var queue: [QueueEntry] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var lyrics: [LyricLine] = []
    var shuffleOn = false
    var repeatMode: RepeatMode = .off
    /// Bumps every time a NEW listening session starts (not on track changes),
    /// so the UI can auto-present the full-screen player.
    private(set) var sessionStamp = 0
    /// What the queue is playing from — "American Teen", "On Repeat". The queue
    /// sheet labels the tail "Next from …" so it's always clear where the songs
    /// after your hand-picked ones are coming from.
    private(set) var contextTitle: String?

    var currentEntry: QueueEntry? { queue.indices.contains(index) ? queue[index] : nil }
    var currentTrack: MediaItem? { currentEntry?.track }
    /// The backend the current queue streams from — views need it to favorite
    /// the playing song without re-deriving the source.
    var activeSource: MusicSource? { source }
    var hasQueue: Bool { !queue.isEmpty }
    var progress: Double { duration > 0 ? currentTime / duration : 0 }

    // MARK: - Up next

    /// Everything still to play. What's behind the playhead stays in the queue
    /// so Back keeps working, but it's history — no screen shows it.
    var upcoming: [QueueEntry] {
        guard queue.indices.contains(index) else { return [] }
        return Array(queue[(index + 1)...])
    }

    var upNext: [MediaItem] { upcoming.map(\.track) }

    /// Songs added by hand. They sit directly after the current one and play
    /// before the record resumes — Spotify's "Next in queue".
    var manualUpNext: [QueueEntry] { upcoming.filter(\.isManual) }

    /// The rest of the album, playlist or mix the session started from.
    var contextUpNext: [QueueEntry] { upcoming.filter { !$0.isManual } }

    /// The lyric line the song is currently on (synced lyrics only). Stored and
    /// refreshed once per playback tick — a computed scan here made the lyrics
    /// list O(n²) per body evaluation, twice a second.
    private(set) var currentLyricIndex: Int?

    // MARK: - Internals

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var originalQueue: [QueueEntry] = []
    /// The backend the current queue streams from (Jellyfin or Navidrome) —
    /// captured at play time so a source switch in Settings never strands a
    /// half-played queue against the wrong server.
    private var source: MusicSource?
    private let nowPlaying = NowPlayingController()
    private var artworkImage: UIImage?
    private var loadGeneration = 0

    private init() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds
                if let total = self.player.currentItem?.duration.seconds, total.isFinite {
                    self.duration = total
                }
                self.refreshLyricIndex()
                // NOTE: deliberately does NOT push Now Playing every tick. iOS
                // extrapolates the lock-screen scrubber from elapsed + rate, so
                // we only push on real changes (track / play-pause / seek).
                // Rewriting the whole info dict twice a second stops the system
                // from committing to the full-screen immersive artwork.
            }
        }
    }

    // MARK: - Session

    /// Starts a fresh listening session from a list of songs. `context` names
    /// where they came from, for the queue sheet's "Next from …" heading.
    func play(tracks: [MediaItem], startAt startIndex: Int = 0,
              source: MusicSource, shuffled: Bool = false, context: String? = nil) {
        self.source = source
        contextTitle = context
        sessionStamp += 1
        let entries = tracks.map { QueueEntry($0) }
        originalQueue = entries
        shuffleOn = shuffled
        if shuffled {
            var rest = entries
            let first = rest.indices.contains(startIndex) ? rest.remove(at: startIndex) : nil
            rest.shuffle()
            queue = (first.map { [$0] } ?? []) + rest
            index = 0
        } else {
            queue = entries
            index = min(max(0, startIndex), max(0, entries.count - 1))
        }
        configureRemote()
        loadCurrent(autoplay: true)
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if isPlaying { player.pause() } else {
            AudioSession.ensureActive()
            player.play()
        }
        isPlaying.toggle()
        pushNowPlaying()
    }

    /// Video playback (or anything else) taking the stage — music yields.
    func pause() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        pushNowPlaying()
    }

    /// Video is starting: pause AND release the shared remote command center so
    /// video's transport handlers don't stack on top of music's (a stacked
    /// registration made a remote Play fire both — music blaring behind the
    /// movie).
    func yieldToVideo() {
        pause()
        nowPlaying.clear()
    }

    /// Video finished (its teardown wipes every target on the SHARED command
    /// center, music's included). If a queue is still loaded, take the remote
    /// back so the lock screen / Siri Remote control music again.
    func reclaimRemoteIfNeeded() {
        guard hasQueue else { return }
        configureRemote()
        pushNowPlaying()
    }

    func seek(toProgress value: Double) {
        guard duration > 0 else { return }
        let target = value * duration
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        pushNowPlaying()
    }

    func next() {
        guard hasQueue else { return }
        reportStopped()
        if index + 1 < queue.count {
            index += 1
        } else if repeatMode == .all {
            index = 0
        } else {
            // End of the queue — park on the last track, paused.
            player.pause()
            isPlaying = false
            pushNowPlaying()
            return
        }
        retireManual()
        loadCurrent(autoplay: true)
    }

    func previous() {
        guard hasQueue else { return }
        // A few seconds in, "previous" means restart — like every music app.
        if currentTime > 3 || index == 0 {
            player.seek(to: .zero)
            currentTime = 0
            return
        }
        reportStopped()
        index -= 1
        loadCurrent(autoplay: true)
    }

    /// Jump straight to a slot in the queue.
    func jump(to entry: QueueEntry) {
        guard let target = queue.firstIndex(where: { $0.id == entry.id }) else { return }
        reportStopped()
        index = target
        retireManual()
        loadCurrent(autoplay: true)
    }

    /// A hand-picked song stops being "next in queue" once it's had its turn. It
    /// stays in the list so Back still reaches it, but the queue sheet only ever
    /// shows what's still to come — so it reads as drained, like Spotify's.
    private func retireManual() {
        for i in queue.indices where i <= index && queue[i].isManual {
            queue[i].isManual = false
        }
    }

    func toggleShuffle() {
        shuffleOn.toggle()
        guard let current = currentEntry else { return }
        // Hand-picked songs are a promise: they keep their place at the head of
        // what's next either way. Only the record itself gets shuffled.
        let manual = manualUpNext
        if shuffleOn {
            var rest = queue.filter { $0.id != current.id && !$0.isManual }
            rest.shuffle()
            queue = [current] + manual + rest
            index = 0
        } else {
            var restored = originalQueue
            var at = restored.firstIndex(where: { $0.id == current.id })
            if at == nil {
                // The playing song was queued by hand, so it was never part of
                // the record — it stays at the head of what's left.
                restored.insert(current, at: 0)
                at = 0
            }
            let resume = at ?? 0
            restored.insert(contentsOf: manual, at: min(resume + 1, restored.count))
            queue = restored
            index = resume
        }
    }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        repeatMode = all[(all.firstIndex(of: repeatMode)! + 1) % all.count]
    }

    /// Slot a song in right ahead of everything ("Play Next"). If nothing is
    /// playing, it just starts.
    func playNext(_ track: MediaItem, source: MusicSource) {
        guard hasQueue else {
            play(tracks: [track], source: source)
            return
        }
        queue.insert(QueueEntry(track, isManual: true), at: min(index + 1, queue.count))
    }

    /// "Add to Queue": the song joins the end of the hand-picked block, so it
    /// plays after anything already queued but still before the record resumes.
    /// Adding the same song twice is allowed — that's what a queue is for.
    func addToQueue(_ track: MediaItem, source: MusicSource) {
        guard hasQueue else {
            play(tracks: [track], source: source)
            return
        }
        var at = index + 1
        while at < queue.count, queue[at].isManual { at += 1 }
        queue.insert(QueueEntry(track, isManual: true), at: at)
    }

    /// Queue a whole record or playlist at once, in order.
    func addToQueue(tracks: [MediaItem], source: MusicSource) {
        guard hasQueue else {
            play(tracks: tracks, source: source)
            return
        }
        for track in tracks { addToQueue(track, source: source) }
    }

    /// Drop a song from what's coming up. The one playing can't be removed —
    /// that's what Next is for.
    func remove(_ entry: QueueEntry) {
        guard let at = queue.firstIndex(where: { $0.id == entry.id }), at != index else { return }
        queue.remove(at: at)
        if at < index { index -= 1 }
    }

    /// Empty everything still to come, leaving the song that's playing.
    func clearUpNext() {
        guard queue.indices.contains(index), index + 1 < queue.count else { return }
        queue.removeSubrange((index + 1)...)
    }

    /// Reorder the hand-picked block. Offsets come from the queue sheet's own
    /// section, so they're relative to that block, not the whole queue.
    func moveManual(from offsets: IndexSet, to destination: Int) {
        moveSlice(offsets, to: destination, in: upcomingBlock(manual: true))
    }

    /// Reorder the rest of the record, below the hand-picked block.
    func moveContext(from offsets: IndexSet, to destination: Int) {
        moveSlice(offsets, to: destination, in: upcomingBlock(manual: false))
    }

    /// Where one of the two up-next blocks actually sits in the queue.
    ///
    /// Normally each block is a single run, but stepping BACK past a song that
    /// was queued by hand leaves a retired entry sitting among the ones still
    /// waiting, which splits the run. Rather than reorder the wrong rows on a
    /// guessed offset, this returns nil and the drag simply does nothing.
    private func upcomingBlock(manual: Bool) -> Range<Int>? {
        let start = index + 1
        guard start <= queue.count else { return nil }
        let matches = queue[start...].indices.filter { queue[$0].isManual == manual }
        guard let first = matches.first, let last = matches.last,
              last - first + 1 == matches.count else { return nil }
        return first ..< (last + 1)
    }

    private func moveSlice(_ offsets: IndexSet, to destination: Int, in range: Range<Int>?) {
        guard let range, !range.isEmpty, range.upperBound <= queue.count else { return }
        var slice = Array(queue[range])
        slice.move(fromOffsets: offsets, toOffset: destination)
        queue.replaceSubrange(range, with: slice)
    }

    /// Stop everything and clear the session (mini-player's ✕).
    func stop() {
        reportStopped()
        player.replaceCurrentItem(with: nil)
        queue = []
        originalQueue = []
        index = 0
        isPlaying = false
        currentTime = 0
        duration = 0
        lyrics = []
        artworkImage = nil
        contextTitle = nil
        nowPlaying.clear()
    }

    // MARK: - Loading

    private func loadCurrent(autoplay: Bool) {
        guard let track = currentTrack, let source else { return }
        loadGeneration += 1
        let generation = loadGeneration
        currentTime = 0
        duration = Double(track.runTimeTicks ?? 0) / 10_000_000
        lyrics = []
        currentLyricIndex = nil
        artworkImage = nil

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }

        // A stored copy (download or cache) plays straight off disk — instant,
        // and it works with no network at all.
        let offline = MusicLibraryCache.shared.localURL(for: track.id)
        MusicLibraryCache.shared.notePlay(of: track, source: source)

        Task {
            // `??` can't carry an `await` on its right-hand side, so resolve the
            // remote URL only when there's no local copy.
            let resolved: URL?
            if let offline {
                resolved = offline
            } else {
                resolved = await source.audioStreamURL(itemID: track.id)
            }
            guard let url = resolved, generation == loadGeneration else { return }
            let item = AVPlayerItem(url: url)
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.repeatMode == .one {
                        self.player.seek(to: .zero)
                        self.player.play()
                    } else {
                        self.next()
                    }
                }
            }
            player.replaceCurrentItem(with: item)
            if autoplay {
                AudioSession.ensureActive()
                player.play()
                isPlaying = true
            }
            pushNowPlaying()
            reportStarted(track)

            // Lyrics + lock-screen artwork ride in behind the audio. The
            // artwork is fetched large (1400²) so the iPhone lock screen can use
            // it as the full-screen immersive backdrop — the system's request
            // handler upscales from whatever we hand it, so the source must be
            // big enough to fill a phone screen without looking soft.
            let lines = await source.lyrics(for: track)
            if generation == loadGeneration { lyrics = lines }
            if let artURL = artworkURL(for: track, maxWidth: 1400),
               let image = await ImageLoader.shared.image(for: artURL),
               generation == loadGeneration {
                artworkImage = image
                pushNowPlaying()
            }
        }
    }

    /// Album art for a song, from whichever backend the queue plays from.
    func artworkURL(for track: MediaItem, maxWidth: Int = 800) -> URL? {
        source?.artworkURL(for: track, maxWidth: maxWidth)
    }

    private func refreshLyricIndex() {
        guard !lyrics.isEmpty else {
            if currentLyricIndex != nil { currentLyricIndex = nil }
            return
        }
        let now = currentTime + 0.2
        var latest: Int?
        for line in lyrics {
            guard let start = line.start else { continue }
            if start <= now { latest = line.id } else { break }
        }
        if latest != currentLyricIndex { currentLyricIndex = latest }
    }

    // MARK: - System integration

    private func configureRemote() {
        // A video session tearing down clears the SHARED remote command center,
        // taking music's targets with it — always re-register from scratch.
        nowPlaying.clear()
        nowPlaying.configure(
            onPlay: { [weak self] in if self?.isPlaying == false { self?.togglePlayPause() } },
            onPause: { [weak self] in if self?.isPlaying == true { self?.togglePlayPause() } },
            onToggle: { [weak self] in self?.togglePlayPause() },
            onSeek: { [weak self] seconds in
                guard let self, self.duration > 0 else { return }
                self.seek(toProgress: seconds / self.duration)
            }
        )
        nowPlaying.configureSkipCommands(
            onNext: { [weak self] in self?.next() },
            onPrevious: { [weak self] in self?.previous() }
        )
    }

    private func pushNowPlaying() {
        guard let track = currentTrack else { return }
        nowPlaying.update(title: track.name,
                          subtitle: track.artistText,
                          duration: duration,
                          elapsed: currentTime,
                          isPlaying: isPlaying,
                          album: track.album,
                          artwork: artworkImage)
    }

    // MARK: - Play reporting (play counts / last-played / scrobbles)

    private func reportStarted(_ track: MediaItem) {
        guard let source else { return }
        Task { await source.reportStarted(itemID: track.id) }
    }

    private func reportStopped() {
        guard let source, let track = currentTrack else { return }
        let ticks = Int64(currentTime * 10_000_000)
        Task { await source.reportStopped(itemID: track.id, positionTicks: ticks) }
    }
}
