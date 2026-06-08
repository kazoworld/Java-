import SwiftUI

/// Rich detail screen with a parallax backdrop, metadata, and a play button
/// that hands off to the hybrid player. Honors the "rich motion" setting.
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
                VStack(alignment: .leading, spacing: Spacing.md) {
                    metadataRow
                    PrimaryButton(title: playButtonTitle, systemImage: "play.fill") {
                        presentPlayer = true
                    }
                    .frame(maxWidth: 360)

                    if let overview = displayed.overview, !overview.isEmpty {
                        Text(overview)
                            .font(Typography.body)
                            .foregroundStyle(UltrafinColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .padding(.bottom, Spacing.xxl)
        }
        .background(UltrafinColors.background.ignoresSafeArea())
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

    private var hero: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let stretch = settings.appearance.richMotion ? max(0, minY) : 0
            RemoteImage(url: backdropURL)
                .frame(width: geo.size.width, height: 320 + stretch)
                .clipped()
                .offset(y: -stretch)
                .overlay(UltrafinColors.heroScrim)
        }
        .frame(height: 320)
    }

    private var metadataRow: some View {
        HStack(spacing: Spacing.md) {
            Text(displayed.name)
                .font(Typography.displayTitle)
                .foregroundStyle(UltrafinColors.primaryText)
                .lineLimit(2)
            Spacer()
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: Spacing.md) {
                if let year = displayed.productionYear { chip(String(year)) }
                if let runtime = displayed.runtimeText { chip(runtime) }
                if let rating = displayed.officialRating { chip(rating) }
                if let community = displayed.communityRating {
                    chip(String(format: "★ %.1f", community))
                }
            }
            .offset(y: 36)
        }
        .padding(.bottom, 36)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(UltrafinColors.secondaryText)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .glassCard(cornerRadius: Spacing.sm)
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
        return appState.client?.imageURL(itemID: displayed.id, kind: kind, tag: tag, maxWidth: 1280)
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
