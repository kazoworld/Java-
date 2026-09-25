import SwiftUI

#if os(tvOS)
/// The Guide: the library laid out as a broadcast grid, in the shape of the
/// satellite guides this is modelled on — channels down the left, time across
/// the top, the highlighted programme described in a banner above.
///
/// Nothing here is really live. ``GuideSchedule`` invents a listing that loops
/// deterministically from a fixed epoch, so what's "on now" is a function of the
/// clock and nothing has to be stored. Landing on a block holds for a beat and
/// then rolls the title behind the banner, the same muted highlight the detail
/// pages use.
struct LiveGuideView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var channels: [GuideChannel] = []
    @State private var isLoading = true
    /// Left edge of the visible window, always on a half hour.
    @State private var windowStart = Date.now.floored(to: GuideSchedule.slot)
    /// Re-read once a minute so the clock and the on-air marker stay honest.
    @State private var now = Date.now
    @State private var focusedProgram: GuideProgram?
    @State private var playing: MediaItem?
    /// A series block was clicked — there's no single episode to start, so its
    /// page opens instead.
    @State private var opened: MediaItem?

    @State private var theater = TheaterController()
    /// The pending 1.6-second hold before a highlight starts rolling.
    @State private var previewHold: Task<Void, Never>?

    @FocusState private var focus: String?

    /// How much of the day the grid shows at once. Six half-hour columns fills
    /// the width of a television without the blocks becoming unreadable.
    private static let columns = 6
    private var windowEnd: Date {
        windowStart.addingTimeInterval(GuideSchedule.slot * Double(Self.columns))
    }

    private var session: UserSession? {
        if case .authenticated(let session) = appState.phase { return session }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            banner
            timeRuler
            grid
            footer
        }
        .background(backdrop)
        .environment(\.colorScheme, .dark)
        .tvPopsOnMenu()
        .task { await load() }
        // A minute is the resolution the clock is displayed at; anything finer
        // is redrawing the whole grid for nothing.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
            }
        }
        .onDisappear {
            previewHold?.cancel()
            theater.stop()
        }
        .onChange(of: focus) { _, id in
            let program = id.flatMap(program(withID:))
            focusedProgram = program
            startHold(for: program)
        }
        .navigationDestination(item: $opened) { item in
            SeriesDetailView(series: item)
        }
        .fullScreenCover(item: $playing) { item in
            if let session {
                VideoPlayerView(item: item, userID: session.userID,
                                resume: settings.playback.autoResume)
            }
        }
        .onChange(of: playing?.id) { _, current in
            // Real playback takes the audio and the screen; the highlight can't
            // be left running underneath it.
            if current != nil { theater.stop() }
        }
    }

    private var backdrop: some View {
        ZStack {
            UltrafinColors.background
            LinearGradient(colors: [settings.accent.opacity(0.22), .clear],
                           startPoint: .topLeading, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    // MARK: - Banner

    /// The description panel above the grid: what's highlighted, when it airs,
    /// and a window that rolls the title once you've rested on it.
    private var banner: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
                    Text("GUIDE")
                        .font(.system(size: 30, weight: .light))
                        .tracking(10)
                        .foregroundStyle(settings.accent)
                    Text(focusedProgram?.item.name ?? "—")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(spacing: Spacing.lg) {
                    Text(now.guideClock)
                        .foregroundStyle(.white.opacity(0.6))
                    if let program = focusedProgram {
                        Text("\(program.start.guideTime) – \(program.end.guideTime)")
                            .foregroundStyle(.white)
                        if program.isOnAir(at: now) {
                            Text("ON NOW")
                                .font(.system(size: 17, weight: .heavy))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(settings.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        if let rating = program.item.officialRating {
                            Text(rating).foregroundStyle(.white.opacity(0.6))
                        }
                        if let year = program.item.productionYear {
                            Text(String(year)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .font(.system(size: 22, weight: .medium))

                Text(focusedProgram?.item.overview ?? " ")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            previewWindow
        }
        .padding(.horizontal, edgePadding)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
        .frame(height: 260, alignment: .top)
    }

    /// Still art, with the muted highlight crossfading over it once it rolls.
    private var previewWindow: some View {
        ZStack {
            RemoteImage(url: previewArtURL, contentMode: .fill)
            if theater.videoActive {
                PlayerSurface(view: theater.layerView)
                    .transition(.opacity)
            }
        }
        .frame(width: 380, height: 214)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .specularRim(cornerRadius: 10, intensity: 0.6)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .overlay(alignment: .bottomTrailing) {
            if theater.videoActive || theater.hasAudio {
                TheaterVolumeButton(controller: theater).padding(10)
            }
        }
    }

    private var previewArtURL: URL? {
        guard let item = focusedProgram?.item, let client = appState.client else { return nil }
        let tag = item.backdropImageTags?.first
        return client.imageURL(itemID: item.id, kind: tag != nil ? .backdrop : .primary,
                               tag: tag, maxWidth: 760)
    }

    // MARK: - Ruler

    private var timeRuler: some View {
        HStack(spacing: 0) {
            Text(windowStart.guideDay)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: channelWidth, alignment: .leading)

            ForEach(0..<Self.columns, id: \.self) { column in
                Text(windowStart.addingTimeInterval(GuideSchedule.slot * Double(column)).guideTime)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: columnWidth, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, edgePadding)
        .padding(.vertical, Spacing.sm)
        .background(.white.opacity(0.06))
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if channels.isEmpty {
            Text("Nothing in the library to schedule yet.")
                .font(.system(size: 26))
                .foregroundStyle(UltrafinColors.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(channels) { channel in
                        channelRow(channel)
                    }
                }
                .padding(.horizontal, edgePadding)
                .padding(.vertical, Spacing.md)
            }
            .scrollClipDisabled()
        }
    }

    private func channelRow(_ channel: GuideChannel) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(channel.number)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(channel.callsign)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: channelWidth, height: rowHeight, alignment: .leading)

            ForEach(channel.programs(from: windowStart, to: windowEnd)) { program in
                programBlock(program)
            }
            Spacer(minLength: 0)
        }
        .frame(height: rowHeight)
    }

    private func programBlock(_ program: GuideProgram) -> some View {
        // A programme already under way when the window opens is clipped to the
        // left edge and marked, the way a listing shows one running in.
        let visibleStart = max(program.start, windowStart)
        let visibleEnd = min(program.end, windowEnd)
        let width = max(60, CGFloat(visibleEnd.timeIntervalSince(visibleStart) / GuideSchedule.slot) * columnWidth)
        let runningIn = program.start < windowStart
        let isFocused = focus == program.id
        let onAir = program.isOnAir(at: now)

        return Button {
            open(program)
        } label: {
            HStack(spacing: 6) {
                if runningIn {
                    Image(systemName: "chevron.compact.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(program.item.name)
                    .font(.system(size: 23, weight: onAir ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isFocused ? .black : .white)
            .padding(.horizontal, Spacing.md)
            .frame(width: width - 4, height: rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(blockFill(isFocused: isFocused, onAir: onAir))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(onAir && !isFocused ? 0.35 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focused($focus, equals: program.id)
        .frame(width: width, height: rowHeight)
        .animation(.smooth(duration: 0.18), value: isFocused)
    }

    private func blockFill(isFocused: Bool, onAir: Bool) -> Color {
        // The highlight is the guide's whole navigation model, so it's the one
        // saturated thing on screen — as on the satellite guides this follows.
        if isFocused { return settings.accent }
        return .white.opacity(onAir ? 0.16 : 0.07)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Spacing.lg) {
            pageButton("−3 hrs", icon: "chevron.left") { page(by: -3) }
            pageButton("Now", icon: "dot.radiowaves.left.and.right") {
                windowStart = Date.now.floored(to: GuideSchedule.slot)
                now = .now
            }
            pageButton("+3 hrs", icon: "chevron.right") { page(by: 3) }
            Spacer()
            Text("Press Play to watch · Menu to leave")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, edgePadding)
        .padding(.vertical, Spacing.md)
        .background(.white.opacity(0.06))
        .focusSection()
    }

    private func pageButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .glassCapsule(dim: 0.15)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: false))
    }

    private func page(by hours: Int) {
        withAnimation(.smooth(duration: 0.25)) {
            windowStart = windowStart.addingTimeInterval(Double(hours) * 3600)
        }
    }

    // MARK: - Behaviour

    /// Resting on a block for a beat rolls the title behind the banner. The
    /// delay is the whole point: without it, sweeping the remote down a column
    /// would open and tear down a video stream per row.
    private func startHold(for program: GuideProgram?) {
        previewHold?.cancel()
        theater.stop()
        guard let program, settings.theaterMode,
              program.item.type == .movie || program.item.type == .episode,
              let client = appState.client else { return }

        previewHold = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled,
                  let url = await client.previewStreamURL(itemID: program.item.id),
                  !Task.isCancelled else { return }
            theater.startVideo(url: url, startAt: Self.previewOffset, window: 240)
        }
    }

    /// Two minutes in: past the studio logos and titles, so the window looks
    /// like a channel already running rather than a film about to start.
    private static let previewOffset: Double = 120

    /// Clicking a block does the obvious thing for what's in it: a film starts,
    /// a series opens — there's no single episode a series block could play.
    private func open(_ program: GuideProgram) {
        theater.stop()
        previewHold?.cancel()
        if program.item.type == .series {
            opened = program.item
        } else {
            playing = program.item
        }
    }

    /// The programme a focus id names. Ids carry the channel and start time, so
    /// this is a lookup rather than a search through every airing.
    private func program(withID id: String) -> GuideProgram? {
        for channel in channels {
            if let hit = channel.programs(from: windowStart, to: windowEnd).first(where: { $0.id == id }) {
                return hit
            }
        }
        return nil
    }

    private func load() async {
        guard let session, let client = appState.client else { isLoading = false; return }
        let items = (try? await client.guideLibrary(userID: session.userID)) ?? []
        channels = GuideLineup.channels(from: items)
        isLoading = false
        // Land on what's actually airing on the first channel, so the guide
        // opens on "now" rather than at some arbitrary corner of the grid.
        if let first = channels.first, let onNow = first.nowPlaying(at: .now) {
            focus = onNow.id
        }
    }

    // MARK: - Metrics

    private var edgePadding: CGFloat { 80 }
    private var channelWidth: CGFloat { 200 }
    private var rowHeight: CGFloat { 68 }
    /// Whatever's left after the channel column, split into half-hour columns.
    private var columnWidth: CGFloat {
        (1920 - edgePadding * 2 - channelWidth) / CGFloat(Self.columns)
    }
}

/// Hosts ``LiveGuideView`` in its own stack so a series block can push a detail
/// page, and keeps the focus binding for the grid out of the navigation.
struct GuideTabView: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            LiveGuideView()
        }
    }
}

private extension Date {
    /// Round down to a grid boundary — the guide only ever starts on the hour or
    /// the half hour.
    func floored(to interval: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 / interval).rounded(.down) * interval)
    }

    /// "5:30a" — the compact listing style, not the system's "5:30 AM".
    var guideTime: String {
        let calendar = Calendar.current
        let hour24 = calendar.component(.hour, from: self)
        let minute = calendar.component(.minute, from: self)
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d%@", hour, minute, hour24 < 12 ? "a" : "p")
    }

    /// "Mon 5:46a" — the clock in the banner.
    var guideClock: String {
        "\(formatted(.dateTime.weekday(.abbreviated))) \(guideTime)"
    }

    /// "Mon 9/13" — the grid's date stamp.
    var guideDay: String {
        let calendar = Calendar.current
        return "\(formatted(.dateTime.weekday(.abbreviated))) "
            + "\(calendar.component(.month, from: self))/\(calendar.component(.day, from: self))"
    }
}
#endif
