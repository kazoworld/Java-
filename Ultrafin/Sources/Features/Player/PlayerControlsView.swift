import SwiftUI

/// Transport overlay: title, progress, a focusable liquid-glass button bar
/// (play/pause, skip, previous/next episode, captions, quality), and the
/// selection panels. Focus is shared with the host view so the remote can move
/// between the video and the controls reliably on tvOS.
struct PlayerControlsView: View {
    @Bindable var model: VideoPlayerViewModel
    var skipFeedback: Int?
    @Binding var panel: PlayerPanel
    var focus: FocusState<PlayerFocusTarget?>.Binding

    let onPlayPause: () -> Void
    let onSkip: (Double) -> Void
    let onSeekProgress: (Double) -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onToggleCaptions: () -> Void

    @Environment(SettingsStore.self) private var settings
    @FocusState private var panelFocus: Int?
    @FocusState private var episodeFocus: String?
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    private var accent: Color { settings.theme.accent.color }

    var body: some View {
        ZStack {
            // Soft gradients at the very top and bottom for legibility — the
            // video stays clear and the controls float directly over it (no
            // boxed-in control bar).
            VStack {
                LinearGradient(colors: [.black.opacity(0.45), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if panel == .none {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    centerState
                    Spacer()
                    glassBar
                }
                .padding(platformPadding)
                // Land focus on Play/Pause when the controls first appear
                // (instead of the focus engine defaulting to the leftmost button).
                .onAppear { if focus.wrappedValue == nil { focus.wrappedValue = .playPause } }
            } else if panel == .episodes {
                episodesPanel
            } else {
                selectionPanel
            }
        }
    }

    private var platformPadding: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.lg
        #endif
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titlePrimary)
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let sub = titleSecondary {
                    Text(sub).font(Typography.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            Label(model.activeEngineName, systemImage: "cpu")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Series name for episodes (e.g. "The Office"), otherwise the item title.
    private var titlePrimary: String {
        guard let item = model.currentItem else { return "" }
        if item.type == .episode { return item.seriesName ?? item.name }
        return item.name
    }

    /// For episodes: "Season 3: EP 1 - Weight Loss".
    private var titleSecondary: String? {
        guard let item = model.currentItem, item.type == .episode else { return nil }
        let s = item.parentIndexNumber.map { "Season \($0)" }
        let e = item.indexNumber.map { "EP \($0)" }
        let prefix = [s, e].compactMap { $0 }.joined(separator: ": ")
        return prefix.isEmpty ? item.name : "\(prefix) - \(item.name)"
    }

    // MARK: - Center

    @ViewBuilder
    private var centerState: some View {
        if model.state.status == .buffering {
            ProgressView().tint(.white).scaleEffect(centerScale)
        } else if let skipFeedback {
            Label("\(skipFeedback > 0 ? "+" : "")\(skipFeedback)s",
                  systemImage: skipFeedback > 0 ? "goforward" : "gobackward")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(Spacing.lg)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var centerScale: CGFloat {
        #if os(tvOS)
        2.0
        #else
        1.4
        #endif
    }

    // MARK: - Bottom: liquid glass control bar

    private var glassBar: some View {
        VStack(spacing: Spacing.md) {
            #if os(tvOS)
            ProgressTrack(progress: model.state.progress, buffered: bufferedFraction, height: 14)
            #else
            Scrubber(progress: isScrubbing ? scrubProgress : model.state.progress,
                     buffered: bufferedFraction,
                     trickplay: model.trickplaySource,
                     duration: model.state.duration,
                     onScrubChanged: { isScrubbing = true; scrubProgress = $0 },
                     onScrubEnded: { onSeekProgress($0); isScrubbing = false })
            #endif

            HStack {
                Text(timecode(model.state.currentTime))
                Spacer()
                Text("-" + timecode(max(0, model.state.duration - model.state.currentTime)))
            }
            .font(Typography.monoTimecode)
            .foregroundStyle(.white.opacity(0.85))

            buttonBar
        }
    }

    private var buttonBar: some View {
        HStack(spacing: buttonSpacing) {
            if model.hasPrevious {
                glassButton("backward.end.fill", target: .previous) { onPrevious() }
            }
            glassButton("gobackward", target: .back) { onSkip(-model.seekInterval) }
            glassButton(model.state.status == .playing ? "pause.fill" : "play.fill",
                        target: .playPause, prominent: true) { onPlayPause() }
            glassButton("goforward", target: .forward) { onSkip(model.seekInterval) }
            if model.hasNext {
                glassButton("forward.end.fill", target: .next) { onNext() }
            }

            Spacer()

            glassButton(model.captionsOn ? "captions.bubble.fill" : "captions.bubble",
                        target: .captions, active: model.captionsOn) { onToggleCaptions() }
            if model.isEpisode {
                glassButton("rectangle.stack.fill", target: .episodes) {
                    panel = .episodes
                }
            }
            glassButton("slider.horizontal.3", target: .quality) { panel = .quality }
        }
        .padding(.top, Spacing.xs)
    }

    private func glassButton(_ system: String, target: PlayerFocusTarget, prominent: Bool = false,
                             active: Bool = false, action: @escaping () -> Void) -> some View {
        // Highlighted (focused) buttons turn into a bright, glowing "shiny" pill
        // so it's obvious which control you're about to press while moving the
        // remote.
        let isFocused = (focus.wrappedValue == target)
        return Button(action: action) {
            Image(systemName: system)
                .font(.system(size: prominent ? buttonSize + 8 : buttonSize, weight: .semibold))
                .foregroundStyle(isFocused ? .black : (active && !prominent ? accent : .white))
                .frame(width: buttonDiameter, height: buttonDiameter)
                .background {
                    if isFocused {
                        Circle().fill(Color.white)
                            .overlay(
                                Circle().fill(
                                    LinearGradient(colors: [.white, .white.opacity(0.7)],
                                                   startPoint: .top, endPoint: .bottom))
                            )
                    } else if prominent {
                        Circle().fill(accent.gradient)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Circle().strokeBorder(
                    isFocused ? .white : (active ? accent : .white.opacity(0.18)),
                    lineWidth: isFocused ? 2.5 : (active ? 2 : 1)))
                .shadow(color: isFocused ? .white.opacity(0.65) : .clear,
                        radius: isFocused ? 18 : 0)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.2, lift: true))
        .focused(focus, equals: target)
    }

    // MARK: - Selection panel (captions / quality)

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Quality")
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ForEach(Array(QualityOption.allCases.enumerated()), id: \.offset) { idx, option in
                panelRow(index: idx, title: option.label, selected: model.quality == option) {
                    Task { await model.setQuality(option) }
                    panel = .none
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: barRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { panelFocus = 0 }
    }

    private func panelRow(index: Int, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(accent).font(.system(size: 20, weight: .bold))
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.04, lift: false))
        .focused($panelFocus, equals: index)
    }

    // MARK: - Episodes panel

    /// A compact, scrollable episode browser that floats over the video. The
    /// season selector sits at the top; scroll the list to any episode and pick
    /// it to start playing. Back dismisses it (handled by the host).
    private var episodesPanel: some View {
        ZStack {
            // Dim the video so the list reads; tapping it dismisses on iOS
            // (tvOS dismisses with the Back/Menu button, handled by the host).
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                #if os(iOS)
                .onTapGesture { panel = .none }
                #endif

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                episodesPanelCard
            }
        }
    }

    private var episodesPanelCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(model.currentItem?.seriesName ?? "Episodes")
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if model.browseSeasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(model.browseSeasons) { season in
                            Button { Task { await model.selectBrowseSeason(season.id) } } label: {
                                Text(season.name)
                                    .font(.system(size: seasonFont, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.xs)
                                    .background(Capsule().fill(season.id == model.browseSeasonID
                                                               ? accent.opacity(0.9) : Color.white.opacity(0.08)))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(model.browseEpisodes) { episode in
                            Button {
                                Task { await model.playBrowsedEpisode(episode); panel = .none }
                            } label: {
                                episodeRow(episode)
                            }
                            .buttonStyle(UltrafinButtonStyle(focusScale: 1.02, lift: false))
                            .focused($episodeFocus, equals: episode.id)
                            .id(episode.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: episodesMaxHeight)
                .onChange(of: episodeFocus) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: episodesPanelWidth, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: barRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: barRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .padding(platformPadding)
        .task {
            await model.loadEpisodeBrowserIfNeeded()
            episodeFocus = model.currentItem?.id ?? model.browseEpisodes.first?.id
        }
    }

    private func episodeRow(_ episode: MediaItem) -> some View {
        let isCurrent = episode.id == model.currentItem?.id
        return HStack(spacing: Spacing.md) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: model.episodeImageURL(episode))
                    .frame(width: epThumbWidth, height: epThumbWidth * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if let progress = episode.playbackProgress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.5))
                            Capsule().fill(accent).frame(width: geo.size.width * progress)
                        }
                        .frame(height: 3)
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(episodeTitle(episode))
                    .font(.system(size: episodeTitleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let runtime = episode.runtimeText {
                    Text(runtime)
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
        .padding(Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isCurrent ? accent.opacity(0.22) : Color.white.opacity(0.05)))
        .contentShape(Rectangle())
    }

    private func episodeTitle(_ episode: MediaItem) -> String {
        if let n = episode.indexNumber { return "\(n). \(episode.name)" }
        return episode.name
    }

    private var seasonFont: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }
    private var episodeTitleSize: CGFloat {
        #if os(tvOS)
        22
        #else
        15
        #endif
    }
    private var epThumbWidth: CGFloat {
        #if os(tvOS)
        180
        #else
        120
        #endif
    }
    private var episodesPanelWidth: CGFloat {
        #if os(tvOS)
        680
        #else
        420
        #endif
    }
    private var episodesMaxHeight: CGFloat {
        #if os(tvOS)
        620
        #else
        360
        #endif
    }

    // MARK: - Helpers

    private var bufferedFraction: Double {
        model.state.duration > 0 ? model.state.bufferedTime / model.state.duration : 0
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Metrics

    private var titleSize: CGFloat {
        #if os(tvOS)
        34
        #else
        18
        #endif
    }
    private var buttonSize: CGFloat {
        #if os(tvOS)
        28
        #else
        20
        #endif
    }
    private var buttonDiameter: CGFloat {
        #if os(tvOS)
        66
        #else
        46
        #endif
    }
    private var buttonSpacing: CGFloat {
        #if os(tvOS)
        Spacing.lg
        #else
        Spacing.md
        #endif
    }
    private var barPadding: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.lg
        #endif
    }
    private var barRadius: CGFloat {
        #if os(tvOS)
        32
        #else
        24
        #endif
    }
}

/// Display-only progress bar with a buffered track (tvOS, and reused by the iOS
/// scrubber).
struct ProgressTrack: View {
    let progress: Double
    let buffered: Double
    var height: CGFloat = 6

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white.opacity(0.3)).frame(width: width * buffered.clamped01())
                Capsule().fill(settings.theme.accent.color).frame(width: width * progress.clamped01())
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: max(height, 24))
    }
}

#if !os(tvOS)
/// A draggable progress bar for touch platforms, with a Trickplay preview frame
/// that follows the thumb while scrubbing.
private struct Scrubber: View {
    let progress: Double
    let buffered: Double
    var trickplay: TrickplaySource? = nil
    var duration: Double = 0
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var dragging = false
    @State private var dragProgress: Double = 0
    @Environment(SettingsStore.self) private var settings

    private let previewWidth: CGFloat = 200

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white.opacity(0.3)).frame(width: width * buffered.clamped01())
                Capsule().fill(settings.theme.accent.color).frame(width: width * progress.clamped01())
                Circle().fill(.white).frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: width * progress.clamped01() - 9)
            }
            .frame(height: 10)
            .frame(maxHeight: .infinity, alignment: .center)
            .overlay(alignment: .topLeading) {
                if dragging, let trickplay {
                    TrickplayThumbnail(source: trickplay, time: dragProgress * duration, width: previewWidth)
                        .offset(x: min(max(0, width * dragProgress - previewWidth / 2), max(0, width - previewWidth)),
                                y: -130)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged {
                        dragging = true
                        dragProgress = ($0.location.x / width).clamped01()
                        onScrubChanged(dragProgress)
                    }
                    .onEnded {
                        onScrubEnded(($0.location.x / width).clamped01())
                        dragging = false
                    }
            )
        }
        .frame(height: 34)
    }
}
#endif

private extension Double {
    func clamped01() -> Double { Swift.max(0, Swift.min(1, self)) }
}
