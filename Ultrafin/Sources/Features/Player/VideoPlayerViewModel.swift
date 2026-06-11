import Foundation
import Combine
import Observation

/// A user-selectable streaming quality. `auto` direct-plays when possible; the
/// rest cap the stream at the given bitrate (transcoding when needed).
enum QualityOption: String, CaseIterable, Identifiable, Codable {
    case auto, highest, high, medium, low
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "Auto · Recommended"
        case .highest: "4K · Highest"
        case .high: "1080p · High"
        case .medium: "720p · Medium"
        case .low: "480p · Data Saver"
        }
    }
    var bitrate: Int? {
        switch self {
        case .auto: nil               // adaptive / direct play
        case .highest: 120_000_000    // 4K, effectively uncapped
        case .high: 20_000_000
        case .medium: 4_000_000
        case .low: 1_500_000
        }
    }
}

/// A contextual "Skip Intro" / "Skip Credits" prompt derived from media segments.
struct SkipAction: Equatable {
    let label: String
    let target: Double
}

/// Drives the player screen. Owns a queue of items (so episodes can advance),
/// resolves each stream, picks the engine per policy, mirrors engine state, and
/// reports progress back to the server.
@Observable
@MainActor
final class VideoPlayerViewModel {
    private(set) var state = PlaybackState()
    private(set) var engine: PlaybackEngine?
    private(set) var activeEngineName = ""
    var errorMessage: String?

    /// Bumped whenever the engine/track/quality selection changes, so SwiftUI
    /// panels re-read live values from the engine.
    private(set) var revision = 0

    private(set) var queue: [MediaItem]
    private(set) var index: Int
    private(set) var quality: QualityOption = .auto
    private(set) var segments: [MediaSegment] = []

    // Episode browser (in-player season/episode picker for TV shows).
    private(set) var browseSeasons: [MediaItem] = []
    private(set) var browseSeasonID: String?
    private(set) var browseEpisodes: [MediaItem] = []

    private let userID: String
    private let client: JellyfinClient
    private let settings: PlaybackPreferences
    private let captionMode: SubtitlePreferences.CaptionMode
    /// When false, ignore any saved resume position and start from 0.
    private let resumeEnabled: Bool

    private var cancellable: AnyCancellable?
    private var resolution: PlaybackResolution?
    private var lastReportedSecond: Int = -1
    private var appliedCaptions = false
    private var captionDisengageTask: Task<Void, Never>?

    init(queue: [MediaItem], startIndex: Int, userID: String, client: JellyfinClient,
         settings: PlaybackPreferences, captionMode: SubtitlePreferences.CaptionMode,
         defaultQuality: QualityOption = .auto, resume: Bool = true) {
        self.queue = queue.isEmpty ? [] : queue
        self.index = min(max(0, startIndex), max(0, queue.count - 1))
        self.userID = userID
        self.client = client
        self.settings = settings
        self.captionMode = captionMode
        self.quality = defaultQuality
        self.resumeEnabled = resume
    }

    // MARK: - Derived

    var currentItem: MediaItem? { queue.indices.contains(index) ? queue[index] : nil }
    var hasNext: Bool { index < queue.count - 1 }
    var hasPrevious: Bool { index > 0 }
    var seekInterval: Double { Double(settings.seekInterval) }

    var subtitleTracks: [MediaTrack] { engine?.subtitleTracks ?? [] }
    var currentSubtitleID: Int? { engine?.currentSubtitleID }

    /// True when the current item is a TV episode, so the in-player episode
    /// browser button should appear.
    var isEpisode: Bool { currentItem?.type == .episode && currentItem?.seriesId != nil }

    // MARK: - Episode browser

    nonisolated func episodeImageURL(_ item: MediaItem) -> URL? {
        let tag = item.imageTags?["Primary"]
        return client.imageURL(itemID: item.id, kind: .primary, tag: tag, maxWidth: 320)
    }

    /// Loads the seasons/episodes for the current series the first time the
    /// browser is opened (or after the season changes).
    func loadEpisodeBrowserIfNeeded() async {
        guard let item = currentItem, let seriesID = item.seriesId else { return }
        if browseSeasons.isEmpty {
            browseSeasons = (try? await client.seasons(seriesID: seriesID, userID: userID)) ?? []
        }
        let target = browseSeasonID ?? item.seasonId ?? browseSeasons.first?.id
        if let target, browseSeasonID != target || browseEpisodes.isEmpty {
            browseSeasonID = target
            browseEpisodes = (try? await client.episodes(seriesID: seriesID, seasonID: target, userID: userID)) ?? []
        }
    }

    func selectBrowseSeason(_ id: String) async {
        guard let seriesID = currentItem?.seriesId, id != browseSeasonID else { return }
        browseSeasonID = id
        browseEpisodes = (try? await client.episodes(seriesID: seriesID, seasonID: id, userID: userID)) ?? []
    }

    /// Switches playback to the chosen episode, making its season the new queue
    /// so previous/next continue to work from there.
    func playBrowsedEpisode(_ episode: MediaItem) async {
        guard let idx = browseEpisodes.firstIndex(where: { $0.id == episode.id }) else { return }
        if episode.id == currentItem?.id { return }
        await reportStopped()
        queue = browseEpisodes
        index = idx
        await loadCurrent(startAt: resumeSeconds())
    }

    // MARK: - Lifecycle

    func start() async {
        await loadCurrent(startAt: resumeSeconds())
    }

    /// Tears down any current engine and (re)loads the current queue item.
    private func loadCurrent(startAt seconds: Double) async {
        guard let item = currentItem else { return }
        engine?.teardown()
        cancellable?.cancel()
        appliedCaptions = false
        errorMessage = nil
        state = PlaybackState()

        do {
            let resolution = try await client.resolvePlayback(for: item, userID: userID, maxBitrate: quality.bitrate)
            self.resolution = resolution
            let engine = makeEngine(for: resolution)
            bind(to: engine)
            self.engine = engine
            revision += 1
            engine.load(url: resolution.streamURL, startAt: seconds)
            engine.play()
            // Intro/outro segments for the Skip Intro button (best-effort).
            segments = await client.mediaSegments(itemID: item.id)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Couldn't start playback."
        }
    }

    /// The contextual skip prompt for the current playback position, if any.
    var activeSkip: SkipAction? {
        let t = state.currentTime
        guard t > 0.5 else { return nil }
        for seg in segments where t >= seg.start && t < seg.end - 1 {
            switch seg.kind {
            case .intro: return SkipAction(label: "Skip Intro", target: seg.end)
            case .outro: return SkipAction(label: "Skip Credits", target: seg.end)
            case .other: continue
            }
        }
        return nil
    }

    func skipCurrentSegment() {
        guard let target = activeSkip?.target else { return }
        engine?.seek(to: target)
    }

    private func makeEngine(for resolution: PlaybackResolution) -> PlaybackEngine {
        switch settings.enginePolicy {
        case .nativeOnly:
            activeEngineName = "AVPlayer"
            return AVPlaybackEngine()
        case .vlcOnly:
            activeEngineName = "VLCKit"
            return VLCPlaybackEngine()
        case .hybrid:
            if resolution.isDirectPlay || !VLCPlaybackEngine.isAvailable {
                activeEngineName = "AVPlayer"
                return AVPlaybackEngine()
            } else {
                activeEngineName = "VLCKit"
                return VLCPlaybackEngine()
            }
        }
    }

    private func bind(to engine: PlaybackEngine) {
        cancellable = engine.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.state = newState
                // Subtitle tracks are only known once playback starts.
                if newState.status == .playing, !self.appliedCaptions {
                    self.appliedCaptions = true
                    self.applyCaptionDefault()
                }
                self.reportProgressIfNeeded(newState)
            }
    }

    // MARK: - Transport

    func togglePlayPause() {
        guard let engine else { return }
        if state.status == .playing { engine.pause() } else { engine.play() }
    }

    func skip(by seconds: Double) {
        let target = max(0, min(state.duration, state.currentTime + seconds))
        engine?.seek(to: target)
        engageCaptionsIfNeeded()
    }

    func seek(toProgress progress: Double) {
        engine?.seek(to: progress * state.duration)
        engageCaptionsIfNeeded()
    }

    func playNext() async {
        guard hasNext else { return }
        await reportStopped()
        index += 1
        await loadCurrent(startAt: 0)
    }

    func playPrevious() async {
        guard hasPrevious else { return }
        await reportStopped()
        index -= 1
        await loadCurrent(startAt: 0)
    }

    /// Called when the current item ends — advance, or report end-of-queue.
    /// Returns true if it advanced.
    func handlePlaybackEnded() async -> Bool {
        if hasNext {
            await playNext()
            return true
        }
        return false
    }

    func stop() {
        captionDisengageTask?.cancel()
        engine?.teardown()
        cancellable?.cancel()
        Task { await reportStopped() }
    }

    // MARK: - Quality & subtitles

    func setQuality(_ option: QualityOption) async {
        guard option != quality else { return }
        quality = option
        await loadCurrent(startAt: state.currentTime)
    }

    func setSubtitle(id: Int?) {
        engine?.selectSubtitle(id: id)
        revision += 1
    }

    /// Single-press captions toggle: off → preferred (English) track, on → off.
    func toggleCaptions() {
        guard let engine else { return }
        if engine.currentSubtitleID != nil {
            engine.selectSubtitle(id: nil)
        } else if let track = preferredSubtitleTrack() {
            engine.selectSubtitle(id: track.id)
        }
        revision += 1
    }

    var captionsOn: Bool { engine?.currentSubtitleID != nil }

    private func preferredSubtitleTrack() -> MediaTrack? {
        let tracks = engine?.subtitleTracks ?? []
        let code = SettingsStore.shared.subtitles.preferredLanguage
        let label = MediaLanguage.options.first(where: { $0.code == code })?.label ?? "English"
        let target = (code.isEmpty ? "english" : label.lowercased())
        if let match = tracks.first(where: { $0.name.lowercased().contains(target) }) { return match }
        if let eng = tracks.first(where: { $0.name.lowercased().contains("eng") }) { return eng }
        return tracks.first
    }

    private func applyCaptionDefault() {
        guard let engine else { return }
        switch captionMode {
        case .off, .whenEngaged:
            engine.selectSubtitle(id: nil)
        case .always:
            engine.selectSubtitle(id: preferredSubtitleTrack()?.id)
        }
        revision += 1
    }

    /// "Off unless engaged": briefly enable captions while scrubbing, then hide.
    private func engageCaptionsIfNeeded() {
        guard captionMode == .whenEngaged, let engine,
              let first = engine.subtitleTracks.first else { return }
        engine.selectSubtitle(id: first.id)
        revision += 1
        captionDisengageTask?.cancel()
        captionDisengageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.engine?.selectSubtitle(id: nil)
            self?.revision += 1
        }
    }

    // MARK: - Progress reporting

    private func resumeSeconds() -> Double {
        guard resumeEnabled, settings.autoResume,
              let ticks = currentItem?.userData?.playbackPositionTicks, ticks > 0 else { return 0 }
        return Double(ticks) / 10_000_000.0
    }

    private func reportProgressIfNeeded(_ state: PlaybackState) {
        guard let item = currentItem else { return }
        let second = Int(state.currentTime)
        guard second != lastReportedSecond, second % 5 == 0, state.status == .playing else { return }
        lastReportedSecond = second
        let ticks = Int64(state.currentTime * 10_000_000)
        Task {
            await client.reportPlaybackProgress(
                itemID: item.id, positionTicks: ticks, isPaused: false, playSessionID: resolution?.playSessionID
            )
        }
    }

    private func reportStopped() async {
        guard let item = currentItem else { return }
        let ticks = Int64(state.currentTime * 10_000_000)
        await client.reportPlaybackProgress(
            itemID: item.id, positionTicks: ticks, isPaused: true, playSessionID: resolution?.playSessionID
        )
    }
}
