import SwiftUI

/// A horizontally-scrolling row of media cards. Two layouts: tall posters and
/// wide landscape (used for resume items so progress is visible).
struct MediaRail: View {
    enum Style { case poster, landscape }

    let title: String
    let items: [MediaItem]
    var style: Style = .poster

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(Typography.sectionTitle)
                .foregroundStyle(UltrafinColors.primaryText)
                .padding(.horizontal, Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Spacing.md) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaCard(item: item, style: style)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .scrollClipDisabled()
        }
    }
}

/// A single tappable media card with artwork, title, and resume progress.
struct MediaCard: View {
    @Environment(AppState.self) private var appState

    let item: MediaItem
    var style: MediaRail.Style = .poster

    @ScaledMetric private var posterWidth: CGFloat = 130

    private var width: CGFloat { style == .poster ? posterWidth : posterWidth * 1.6 }
    private var height: CGFloat { style == .poster ? width * 1.5 : width * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: artworkURL)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous))

                if let progress = item.playbackProgress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.4))
                            Capsule()
                                .fill(UltrafinColors.accent)
                                .frame(width: geo.size.width * progress)
                        }
                        .frame(height: 4)
                    }
                    .frame(height: 4)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )

            Text(item.name)
                .font(Typography.cardTitle)
                .foregroundStyle(UltrafinColors.primaryText)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(UltrafinColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }

    private var subtitle: String? {
        if let series = item.seriesName { return series }
        if let year = item.productionYear { return String(year) }
        return nil
    }

    private var artworkURL: URL? {
        let kind: JellyfinClient.ImageKind = style == .landscape ? .backdrop : .primary
        let tag = style == .landscape ? item.backdropImageTags?.first : item.imageTags?["Primary"]
        return appState.client?.imageURL(itemID: item.id, kind: kind, tag: tag, maxWidth: Int(width * 2))
    }
}
