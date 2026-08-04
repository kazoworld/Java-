import SwiftUI

/// A generated mix opened as a playlist: its cover, what it is, when it next
/// refreshes, then the songs — so you can see what's inside before committing
/// to playing it.
struct SmartMixDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    let mix: SmartMix

    @State private var tracks: [MediaItem] = []
    @State private var isLoading = true

    private var player: MusicPlayer { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                trackList
            }
            .padding(.horizontal, edgePadding)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .musicCanvas()
        #if os(iOS)
        .navigationTitle(mix.title)
        .navigationBarTitleDisplayMode(.inline)
        .adaptsChromeOnScroll()
        #endif
        .tvPopsOnMenu()
        .task {
            guard let source = appState.musicSource else { isLoading = false; return }
            tracks = await mix.load(from: source)
            isLoading = false
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.lg) {
            SmartMixArtwork(mix: mix, side: artSide,
                            covers: tracks.prefix(4).compactMap {
                                appState.musicSource?.artworkURL(for: $0, maxWidth: 300)
                            })
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 26, y: 14)

            VStack(spacing: 5) {
                Text(mix.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .multilineTextAlignment(.center)
                Text(mix.subtitle)
                    .font(.system(size: titleSize * 0.62, weight: .regular))
                    .foregroundStyle(UltrafinColors.secondaryText)
                    .multilineTextAlignment(.center)
                Text(detailLine)
                    .font(.system(size: titleSize * 0.55, weight: .regular))
                    .foregroundStyle(UltrafinColors.tertiaryText)
            }

            HStack(spacing: Spacing.md) {
                actionPill("Play", icon: "play.fill") { start(shuffled: false) }
                actionPill("Shuffle", icon: "shuffle") { start(shuffled: true) }
            }
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    /// "24 songs · Updates weekly" — makes the refresh cadence plain.
    private var detailLine: String {
        var parts: [String] = []
        if !tracks.isEmpty {
            parts.append("\(tracks.count) song\(tracks.count == 1 ? "" : "s")")
        }
        parts.append(mix.kind == .recentlyPlayed ? "Always up to date" : "Updates weekly")
        return parts.joined(separator: " · ")
    }

    private func actionPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.medium)
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: pillFont, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm + 3)
                .background(settings.theme.accent.color, in: Capsule())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))
        .disabled(tracks.isEmpty)
    }

    // MARK: - Tracks

    @ViewBuilder
    private var trackList: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xl)
        } else if tracks.isEmpty {
            Text("Nothing here yet — play some music and this fills in.")
                .font(Typography.body)
                .foregroundStyle(UltrafinColors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.xl)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { position, track in
                    Button {
                        guard let source = appState.musicSource else { return }
                        Haptics.play(.selection)
                        player.play(tracks: tracks, startAt: position, source: source,
                                    context: mix.title)
                    } label: {
                        TrackRow(track: track, position: position + 1,
                                 isCurrent: player.currentTrack?.id == track.id,
                                 showsArt: true)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.01, lift: false))
                    if position < tracks.count - 1 {
                        Divider().overlay(UltrafinColors.separator).padding(.leading, 62)
                    }
                }
            }
        }
    }

    private func start(shuffled: Bool) {
        guard let source = appState.musicSource, !tracks.isEmpty else { return }
        player.play(tracks: tracks, startAt: 0, source: source,
                    shuffled: shuffled, context: mix.title)
    }

    // MARK: - Metrics

    private var artSide: CGFloat {
        #if os(tvOS)
        320
        #else
        240
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        40
        #else
        24
        #endif
    }
    private var pillFont: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        60
        #else
        20
        #endif
    }
    private var contentMaxWidth: CGFloat {
        #if os(tvOS)
        1100
        #else
        .infinity
        #endif
    }
}

/// The mix's cover: a four-up collage of what's inside over its own colours,
/// with the mix glyph on top. Shared by the shelf card and the detail header.
struct SmartMixArtwork: View {
    let mix: SmartMix
    let side: CGFloat
    let covers: [URL]

    var body: some View {
        ZStack {
            LinearGradient(colors: mix.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if covers.count >= 4 {
                let half = side / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        RemoteImage(url: covers[0]).frame(width: half, height: half).clipped()
                        RemoteImage(url: covers[1]).frame(width: half, height: half).clipped()
                    }
                    HStack(spacing: 0) {
                        RemoteImage(url: covers[2]).frame(width: half, height: half).clipped()
                        RemoteImage(url: covers[3]).frame(width: half, height: half).clipped()
                    }
                }
            } else if let first = covers.first {
                RemoteImage(url: first).frame(width: side, height: side).clipped()
            }

            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)

            Image(systemName: mix.systemImage)
                .font(.system(size: side * 0.24, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        }
        .frame(width: side, height: side)
    }
}
