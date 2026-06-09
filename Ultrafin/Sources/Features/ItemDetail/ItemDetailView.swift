import SwiftUI

/// Cinematic detail screen for a movie (or any single playable item): a
/// full-bleed backdrop hero with title, metadata, synopsis, and a prominent
/// Play button — in the style of Netflix / Hulu / Peacock.
struct ItemDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    let item: MediaItem

    @State private var detail: MediaItem?
    @State private var presentPlayer = false

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    private var displayed: MediaItem { detail ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                hero
            }
            .padding(.bottom, Spacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
        .background(AmbientBackground())
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard let session, let client = appState.client else { return }
            detail = try? await client.itemDetail(item.id, userID: session.userID)
        }
        .fullScreenCoverCompat(isPresented: $presentPlayer) {
            if let session {
                VideoPlayerView(item: displayed, userID: session.userID)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: backdropURL)
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(UltrafinColors.heroScrim)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(displayed.name)
                    .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 4)

                metadata

                if let overview = displayed.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: overviewSize, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                        .frame(maxWidth: 1000, alignment: .leading)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                }

                playButton
            }
            .padding(.horizontal, edgePadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    private var metadata: some View {
        HStack(spacing: Spacing.sm) {
            if let community = displayed.communityRating {
                chip(String(format: "★ %.1f", community), accentColor: true)
            }
            if let year = displayed.productionYear { dot(); chip(String(year)) }
            if let runtime = displayed.runtimeText { dot(); chip(runtime) }
            if let rating = displayed.officialRating {
                dot()
                chip(rating)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.5), lineWidth: 1))
            }
        }
    }

    private func chip(_ text: String, accentColor: Bool = false) -> some View {
        Text(text)
            .font(.system(size: metaSize, weight: .semibold, design: .rounded))
            .foregroundStyle(accentColor ? settings.theme.accent.color : .white.opacity(0.9))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
    }

    private func dot() -> some View {
        Circle().fill(.white.opacity(0.5)).frame(width: 4, height: 4)
    }

    private var playButton: some View {
        Button { presentPlayer = true } label: {
            Label(playButtonTitle, systemImage: "play.fill")
                .font(.system(size: actionFont, weight: .bold, design: .rounded))
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(settings.theme.accent.color, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: true))
        .padding(.top, Spacing.sm)
    }

    private var playButtonTitle: String {
        if settings.playback.autoResume, let p = displayed.playbackProgress, p > 0.01, p < 0.95 {
            return "Resume"
        }
        return "Play"
    }

    private var backdropURL: URL? {
        let tag = displayed.backdropImageTags?.first ?? displayed.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = displayed.backdropImageTags?.isEmpty == false ? .backdrop : .primary
        return appState.client?.imageURL(itemID: displayed.id, kind: kind, tag: tag, maxWidth: 1920)
    }

    // MARK: - Metrics

    private var heroHeight: CGFloat {
        #if os(tvOS)
        620
        #else
        420
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        62
        #else
        34
        #endif
    }
    private var metaSize: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }
    private var overviewSize: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var actionFont: CGFloat {
        #if os(tvOS)
        28
        #else
        17
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        60
        #else
        20
        #endif
    }
}

// MARK: - Cross-platform full-screen presentation

extension View {
    /// `fullScreenCover` exists on iOS/tvOS; this wrapper keeps call sites tidy.
    @ViewBuilder
    func fullScreenCoverCompat<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        self.fullScreenCover(isPresented: isPresented, content: content)
    }
}
