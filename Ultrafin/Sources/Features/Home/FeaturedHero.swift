import SwiftUI
import Combine

/// A large, auto-rotating hero banner for the top of Home — the "media bar".
///
/// On tvOS this is the signature Apple TV look: full-bleed backdrop, title,
/// synopsis, and focusable Play / More Info actions. It cross-fades through a
/// handful of featured items and pauses rotation while focused so it never
/// moves out from under the remote.
struct FeaturedHero: View {
    let items: [MediaItem]
    let autoAdvance: Bool
    let onPlay: (MediaItem) -> Void

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var index = 0
    @State private var isFocused = false
    @FocusState private var focus: HeroFocus?

    private enum HeroFocus: Hashable { case play, info }

    private let rotation: Publishers.Autoconnect<Timer.TimerPublisher>

    init(items: [MediaItem], rotationSeconds: Int = 8, autoAdvance: Bool = true,
         onPlay: @escaping (MediaItem) -> Void) {
        self.items = items
        self.autoAdvance = autoAdvance
        self.onPlay = onPlay
        self.rotation = Timer.publish(every: TimeInterval(max(3, rotationSeconds)), on: .main, in: .common)
            .autoconnect()
    }

    private var current: MediaItem? {
        guard items.indices.contains(index) else { return items.first }
        return items[index]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            scrim
            content
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .onReceive(rotation) { _ in advance() }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // MARK: - Layers

    private var accent: Color { settings.theme.accent.color }

    /// Opaque at the top, transparent at the bottom — used to dissolve the hero
    /// into the page so there's no hard seam against the rows below.
    private var bottomFade: LinearGradient {
        LinearGradient(stops: [
            .init(color: .black, location: 0.0),
            .init(color: .black, location: 0.6),
            .init(color: .clear, location: 1.0)
        ], startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let current {
            RemoteImage(url: backdropURL(for: current))
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .clipped()
                .id(current.id) // drive the cross-fade
                .transition(.opacity)
                .mask(bottomFade) // fade the artwork into the page at the bottom
        } else {
            UltrafinColors.elevatedSurface.mask(bottomFade)
        }
    }

    private var scrim: some View {
        ZStack {
            // Vertical legibility backing that also fades to clear at the very
            // bottom, so the hero blends seamlessly into the content below.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: UltrafinColors.background.opacity(0.0), location: 0.35),
                .init(color: UltrafinColors.background.opacity(0.6), location: 0.82),
                .init(color: .clear, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            // Left-side contrast for the text, faded at the bottom edge.
            LinearGradient(colors: [UltrafinColors.background.opacity(0.7), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .mask(bottomFade)

            // Accent wash so the media bar re-tints when the theme changes.
            LinearGradient(colors: [.clear, accent.opacity(0.28)],
                           startPoint: .center, endPoint: .bottom)
                .mask(bottomFade)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let current {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("FEATURED")
                    .font(.system(size: eyebrowSize, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(accent)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)

                Text(current.name)
                    .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 4)

                metadata(for: current)

                if let overview = current.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: overviewSize, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                        .frame(maxWidth: overviewWidth, alignment: .leading)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                }

                HStack(spacing: Spacing.md) {
                    Button { onPlay(current) } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: actionFont, weight: .bold, design: .rounded))
                            .padding(.horizontal, Spacing.xl)
                            .padding(.vertical, Spacing.md)
                            .background(settings.theme.accent.color, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: true))
                    .focused($focus, equals: .play)

                    NavigationLink(value: current) {
                        Label("More Info", systemImage: "info.circle")
                            .font(.system(size: actionFont, weight: .semibold, design: .rounded))
                            .padding(.horizontal, Spacing.xl)
                            .padding(.vertical, Spacing.md)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: true))
                    .focused($focus, equals: .info)

                    Spacer()
                    pageDots
                }
                .padding(.top, Spacing.sm)
                // Pause rotation while the user is interacting with the hero.
                .onChange(of: focus) { _, newValue in isFocused = (newValue != nil) }
            }
            .padding(heroPadding)
        }
    }

    private func metadata(for item: MediaItem) -> some View {
        HStack(spacing: Spacing.sm) {
            if let community = item.communityRating {
                chip(String(format: "★ %.1f", community), accentColor: true)
            }
            if let year = item.productionYear { dot(); chip(String(year)) }
            if let runtime = item.runtimeText { dot(); chip(runtime) }
            if let rating = item.officialRating {
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
            .foregroundStyle(accentColor ? accent : .white.opacity(0.9))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
    }

    private func dot() -> some View {
        Circle().fill(.white.opacity(0.5)).frame(width: 4, height: 4)
    }

    private var pageDots: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(items.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? settings.theme.accent.color : UltrafinColors.tertiaryText)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Behavior

    private func advance() {
        guard autoAdvance, items.count > 1, !isFocused else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            index = (index + 1) % items.count
        }
    }

    private func backdropURL(for item: MediaItem) -> URL? {
        let tag = item.backdropImageTags?.first ?? item.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = (item.backdropImageTags?.isEmpty == false) ? .backdrop : .primary
        return appState.client?.imageURL(itemID: item.id, kind: kind, tag: tag, maxWidth: 1920)
    }

    // MARK: - Platform metrics

    private var heroHeight: CGFloat {
        #if os(tvOS)
        640
        #else
        460
        #endif
    }
    private var eyebrowSize: CGFloat {
        #if os(tvOS)
        22
        #else
        13
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        74
        #else
        40
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
    private var heroPadding: EdgeInsets {
        #if os(tvOS)
        EdgeInsets(top: 0, leading: 60, bottom: 56, trailing: 60)
        #else
        EdgeInsets(top: 0, leading: 20, bottom: 28, trailing: 20)
        #endif
    }
    private var overviewWidth: CGFloat {
        #if os(tvOS)
        1000
        #else
        .infinity
        #endif
    }
}
