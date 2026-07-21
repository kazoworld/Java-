import SwiftUI
import AVFoundation
import Observation

/// The app-wide music engine: one queue, one player, alive across every tab.
///
/// Handles the whole listening session — queue with shuffle and repeat,
/// gapless-ish advance, synced lyrics, system Now Playing (Control Center /
/// lock screen / the TV's transport), and Jellyfin play reporting — so views
/// only ever render its state.
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

    private(set) var queue: [MediaItem] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var lyrics: [LyricLine] = []
    var shuffleOn = false
    var repeatMode: RepeatMode = .off

    var currentTrack: MediaItem? { queue.indices.contains(index) ? queue[index] : nil }
    var hasQueue: Bool { !queue.isEmpty }
    var progress: Double { duration > 0 ? currentTime / duration : 0 }

    /// The lyric line the song is currently on (synced lyrics only). Stored and
    /// refreshed once per playback tick — a computed scan here made the lyrics
    /// list O(n²) per body evaluation, twice a second.
    private(set) var currentLyricIndex: Int?

    // MARK: - Internals

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var originalQueue: [MediaItem] = []
    private var client: JellyfinClient?
    private var userID: String?
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
                self.pushNowPlaying()
            }
        }
    }

    // MARK: - Session

    /// Starts a fresh listening session from a list of songs.
    func play(tracks: [MediaItem], startAt startIndex: Int = 0,
              client: JellyfinClient, userID: String, shuffled: Bool = false) {
        self.client = client
        self.userID = userID
        originalQueue = tracks
        shuffleOn = shuffled
        if shuffled {
            var rest = tracks
            let first = rest.indices.contains(startIndex) ? rest.remove(at: startIndex) : nil
            rest.shuffle()
            queue = (first.map { [$0] } ?? []) + rest
            index = 0
        } else {
            queue = tracks
            index = min(max(0, startIndex), max(0, tracks.count - 1))
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

    /// Jump straight to a song in the visible queue.
    func jump(to track: MediaItem) {
        guard let target = queue.firstIndex(where: { $0.id == track.id }) else { return }
        reportStopped()
        index = target
        loadCurrent(autoplay: true)
    }

    func toggleShuffle() {
        shuffleOn.toggle()
        guard let current = currentTrack else { return }
        if shuffleOn {
            var rest = queue.filter { $0.id != current.id }
            rest.shuffle()
            queue = [current] + rest
            index = 0
        } else {
            queue = originalQueue
            index = queue.firstIndex(where: { $0.id == current.id }) ?? 0
        }
    }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        repeatMode = all[(all.firstIndex(of: repeatMode)! + 1) % all.count]
    }

    /// Reorder the up-next portion of the queue (from the queue sheet).
    func moveQueueItems(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if let current = currentTrack, let i = queue.firstIndex(where: { $0.id == current.id }) {
            index = i
        }
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
        nowPlaying.clear()
    }

    // MARK: - Loading

    private func loadCurrent(autoplay: Bool) {
        guard let track = currentTrack, let client, let userID else { return }
        loadGeneration += 1
        let generation = loadGeneration
        currentTime = 0
        duration = Double(track.runTimeTicks ?? 0) / 10_000_000
        lyrics = []
        currentLyricIndex = nil
        artworkImage = nil

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }

        Task {
            guard let url = await client.audioStreamURL(itemID: track.id, userID: userID),
                  generation == loadGeneration else { return }
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

            // Lyrics + lock-screen artwork ride in behind the audio.
            let lines = await client.lyrics(itemID: track.id)
            if generation == loadGeneration { lyrics = lines }
            if let artURL = artworkURL(for: track, maxWidth: 600),
               let image = await ImageLoader.shared.image(for: artURL),
               generation == loadGeneration {
                artworkImage = image
                pushNowPlaying()
            }
        }
    }

    /// Album art for a song (falls back to the track's own primary image).
    func artworkURL(for track: MediaItem, maxWidth: Int = 800) -> URL? {
        guard let client else { return nil }
        if let albumId = track.albumId {
            return client.imageURL(itemID: albumId, kind: .primary,
                                   tag: track.albumPrimaryImageTag, maxWidth: maxWidth)
        }
        return client.imageURL(itemID: track.id, kind: .primary,
                               tag: track.imageTags?["Primary"], maxWidth: maxWidth)
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

    // MARK: - Jellyfin reporting (play counts / last-played)

    private func reportStarted(_ track: MediaItem) {
        guard let client else { return }
        Task { await client.reportPlaybackStarted(itemID: track.id, positionTicks: 0, playSessionID: nil) }
    }

    private func reportStopped() {
        guard let client, let track = currentTrack else { return }
        let ticks = Int64(currentTime * 10_000_000)
        Task { await client.reportPlaybackStopped(itemID: track.id, positionTicks: ticks, playSessionID: nil) }
    }
}
