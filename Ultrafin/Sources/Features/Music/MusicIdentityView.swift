import SwiftUI

/// "Music Identity" — a Replay-style look at how the user listens, fronted by a
/// generated signature card. The whole screen is computed locally from a sample
/// of their played songs, so it reads the same on Jellyfin and Navidrome.
struct MusicIdentityView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var insights = MusicInsights()
    @State private var isLoading = true
    @State private var cardColor: ArtworkColor?

    private var player: MusicPlayer { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                identityCard

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xl)
                } else if insights.isEmpty {
                    emptyState
                } else {
                    statStrip
                    if !insights.topGenres.isEmpty { genreSection }
                    if !insights.topArtists.isEmpty { artistSection }
                    if !insights.topSongs.isEmpty { topSongsSection }
                }
            }
            .padding(.horizontal, edgePadding)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ArtworkBackground(color: cardColor))
        .environment(\.colorScheme, .dark)
        #if os(iOS)
        .navigationTitle("Music Identity")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    // MARK: - Identity card

    private var identityCard: some View {
        let tint = cardColor?.color ?? settings.theme.accent.color
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("YOUR MUSIC IDENTITY")
                .font(.system(size: kickerSize, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .tracking(2)
            Text(insights.personality)
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Text(insights.tagline)
                .font(.system(size: taglineSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)

            if !isLoading && !insights.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "waveform")
                    Text(focusPhrase)
                }
                .font(.system(size: taglineSize * 0.82, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .background {
            ZStack {
                LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // A soft light sweep so the card catches the eye like glass.
                LinearGradient(colors: [.white.opacity(0.22), .clear],
                               startPoint: .top, endPoint: .center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .strokeBorder(LiquidGlass.rim(0.6), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.5), radius: 30, y: 16)
    }

    private var focusPhrase: String {
        switch insights.focusScore {
        case 70...: "You go deep before you go wide"
        case 45..<70: "A clear sound, with room to roam"
        case 25..<45: "Always a few new corners to explore"
        default: "You'll try anything once"
        }
    }

    // MARK: - Stats

    private var statStrip: some View {
        HStack(spacing: Spacing.md) {
            statTile(value: playsText, label: "Plays", icon: "play.circle.fill")
            statTile(value: listeningText, label: "Listened", icon: "clock.fill")
            statTile(value: "\(insights.distinctArtists)", label: "Artists", icon: "person.2.fill")
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: statIcon, weight: .semibold))
                .foregroundStyle(settings.theme.accent.color)
            Text(value)
                .font(.system(size: statValue, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: statLabel, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .liquidGlass(cornerRadius: 18)
    }

    private var playsText: String {
        insights.totalPlays >= 1000
            ? String(format: "%.1fk", Double(insights.totalPlays) / 1000)
            : "\(insights.totalPlays)"
    }
    private var listeningText: String {
        let h = insights.estimatedMinutes / 60
        return h > 0 ? "\(h)h" : "\(insights.estimatedMinutes)m"
    }

    // MARK: - Genres

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Top Genres")
            let maxPlays = insights.topGenres.map(\.plays).max() ?? 1
            VStack(spacing: Spacing.sm) {
                ForEach(Array(insights.topGenres.enumerated()), id: \.element.id) { i, genre in
                    genreBar(rank: i + 1, genre: genre, fraction: Double(genre.plays) / Double(maxPlays))
                }
            }
        }
    }

    private func genreBar(rank: Int, genre: MusicInsights.Ranked, fraction: Double) -> some View {
        HStack(spacing: Spacing.md) {
            Text("\(rank)")
                .font(.system(size: rowNumber, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: rowNumber * 1.6, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(genre.name)
                    .font(.system(size: rowTitle, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [settings.theme.accent.color,
                                                          settings.theme.accent.color.opacity(0.5)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * fraction))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Artists

    private var artistSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Top Artists")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: railSpacing) {
                    ForEach(Array(insights.topArtists.enumerated()), id: \.element.id) { i, artist in
                        VStack(spacing: Spacing.sm) {
                            ZStack {
                                Circle().fill(settings.theme.accent.color.opacity(0.18))
                                Text(initials(artist.name))
                                    .font(.system(size: avatarSide * 0.34, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: avatarSide, height: avatarSide)
                            .overlay(Circle().strokeBorder(LiquidGlass.rim(0.5), lineWidth: 1))
                            .overlay(alignment: .topLeading) { rankBadge(i + 1) }
                            Text(artist.name)
                                .font(.system(size: rowTitle * 0.9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(width: avatarSide + 24)
                        }
                    }
                }
                .padding(.vertical, focusInset)
            }
            .scrollClipDisabled()
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.system(size: avatarSide * 0.2, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(avatarSide * 0.08)
            .frame(minWidth: avatarSide * 0.32)
            .background(settings.theme.accent.color, in: Circle())
    }

    // MARK: - Top songs

    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Songs on Repeat")
            LazyVStack(spacing: 2) {
                ForEach(Array(insights.topSongs.enumerated()), id: \.element.id) { i, song in
                    Button {
                        guard let source = appState.musicSource else { return }
                        Haptics.play(.selection)
                        player.play(tracks: insights.topSongs, startAt: i, source: source)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Text("\(i + 1)")
                                .font(.system(size: rowNumber, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(settings.theme.accent.color)
                                .frame(width: rowNumber * 1.6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.name)
                                    .font(.system(size: rowTitle, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if let artist = song.artistText {
                                    Text(artist)
                                        .font(.system(size: rowTitle * 0.8))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: Spacing.md)
                            if song.playCount > 0 {
                                Text("\(song.playCount)×")
                                    .font(.system(size: rowTitle * 0.82, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm + 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.01, lift: false))
                }
            }
        }
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: sectionSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.5))
            Text("Play some music to build your identity")
                .font(.system(size: taglineSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Text("As you listen, Ultrafin learns your taste and fills this in.")
                .font(Typography.body)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "♪" : letters.uppercased()
    }

    // MARK: - Data

    private func load() async {
        guard let source = appState.musicSource else { isLoading = false; return }
        let songs = (try? await source.songsForInsights()) ?? []
        insights = MusicInsights.compute(from: songs)
        isLoading = false
        // Tint the whole screen from the user's most-played record.
        if let top = insights.topSongs.first,
           let url = source.artworkURL(for: top, maxWidth: 240) {
            cardColor = await ImageColor.vibrant(from: url)
        }
    }

    // MARK: - Metrics

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
    private var kickerSize: CGFloat {
        #if os(tvOS)
        20
        #else
        13
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        68
        #else
        40
        #endif
    }
    private var taglineSize: CGFloat {
        #if os(tvOS)
        28
        #else
        18
        #endif
    }
    private var cardPadding: CGFloat {
        #if os(tvOS)
        48
        #else
        26
        #endif
    }
    private var cardCorner: CGFloat {
        #if os(tvOS)
        36
        #else
        26
        #endif
    }
    private var sectionSize: CGFloat {
        #if os(tvOS)
        34
        #else
        22
        #endif
    }
    private var statIcon: CGFloat {
        #if os(tvOS)
        30
        #else
        20
        #endif
    }
    private var statValue: CGFloat {
        #if os(tvOS)
        40
        #else
        26
        #endif
    }
    private var statLabel: CGFloat {
        #if os(tvOS)
        20
        #else
        13
        #endif
    }
    private var rowNumber: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var rowTitle: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var avatarSide: CGFloat {
        #if os(tvOS)
        160
        #else
        92
        #endif
    }
    private var railSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.md
        #endif
    }
    private var focusInset: CGFloat {
        #if os(tvOS)
        Spacing.lg
        #else
        0
        #endif
    }
}
