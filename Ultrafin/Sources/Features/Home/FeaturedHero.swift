import SwiftUI
import Combine

/// The "media bar" hero at the top of Home. Its colors come from the **artwork**
/// (a vivid color sampled from each title's backdrop), not the app theme — so it
/// stays unique to the movie/show and is unaffected by accent or theme changes.
struct FeaturedHero: View {
    let items: [MediaItem]
    let autoAdvance: Bool
    let onPlay: (MediaItem) -> Void
    /// Optional "Play Something" shuffle action shown as an extra hero button.
    let onShuffle: (() -> Void)?

    @Environment(AppState.self) private var appState

    @State private var index = 0
    @State private var isFocused = false
    @State private var artColor: ArtworkColor?
    /// Per-item color cache so rotating back to a title never re-downloads or
    /// re-samples its art — that repeated work was a big part of the Home lag.
    @State private var colorCache: [String: ArtworkColor] = [:]
    @FocusState private var focus: HeroFocus?

    private enum HeroFocus: Hashable { case play, info, shuffle, prev, next }

    private let rotation: Publishers.Autoconnect<Timer.TimerPublisher>

    init(items: [MediaItem], rotationSeconds: Int = 8, autoAdvance: Bool = true,
         onPlay: @escaping (MediaItem) -> Void, onShuffle: (() -> Void)? = nil) {
        self.items = items
        self.autoAdvance = autoAdvance
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.rotation = Timer.publish(every: TimeInterval(max(3, rotationSeconds)), on: .main, in: .common)
            .autoconnect()
    }

    private var current: MediaItem? {
        guard items.indices.contains(index) else { return items.first }
        return items[index]
    }

    /// Color sampled from the current artwork (falls back to neutral while loading).
    private var tint: Color { artColor?.color ?? Color.white.opacity(0.9) }
    private var playTextColor: Color { (artColor?.isDark ?? false) ? .white : .black }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop + scrim share a single bottom-fade mask (one offscreen
            // pass instead of three) so the hero stays cheap to composite while
            // the Home page scrolls.
            ZStack {
                backdrop
                scrim
            }
            .mask(bottomFade)

            content
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .onReceive(rotation) { _ in advance() }
        .task {
            await loadColor()
            prefetchBackdrops() // warm the cache so rotations don't hitch on decode
        }
        .onChange(of: index) { _, _ in
            Task { await loadColor() }
        }
        // Color updates instantly (no 0.4s of re-compositing the masked hero on
        // every rotation — that was a periodic Home hitch).
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // MARK: - Layers

    /// Opaque at the top, transparent at the bottom — dissolves the hero into the
    /// page so there's no hard seam against the rows below.
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
        } else {
            UltrafinColors.elevatedSurface
        }
    }

    private var scrim: some View {
        ZStack {
            // Dark legibility gradient (content-agnostic) so white text always
            // reads; fades to clear at the very bottom for the page blend.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.0), location: 0.30),
                .init(color: .black.opacity(0.72), location: 0.85),
                .init(color: .clear, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            // Content-color glow — the bar's color comes from the artwork. The
            // fades are baked into the gradient stops so neither layer needs its
            // own mask (the shared bottom-fade handles the page blend).
            LinearGradient(stops: [
                .init(color: .clear, location: 0.45),
                .init(color: tint.opacity(0.5), location: 0.9),
                .init(color: tint.opacity(0.2), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [tint.opacity(0.4), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: heroHeight * 0.95)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let current {
            VStack(alignment: .leading, spacing: Spacing.md) {
                TitleLogo(logoURL: logoURL(current), title: current.name,
                          fallbackFont: .system(size: titleSize, weight: .heavy, design: .rounded),
                          fallbackColor: .white, maxWidth: logoMaxWidth, maxHeight: logoMaxHeight)
                    .shadow(color: .black.opacity(0.6), radius: 16, y: 6)

                metadataRow(for: current)

                if let overview = current.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: overviewSize, weight: .regular))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .frame(maxWidth: overviewWidth, alignment: .leading)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                }

                actions(for: current)
            }
            .padding(heroPadding)
        }
    }

    private func metadataRow(for item: MediaItem) -> some View {
        HStack(spacing: Spacing.md) {
            if let rt = item.criticScoreText {
                HStack(spacing: 4) {
                    Text("🍅")
                    Text(rt).foregroundStyle(item.isFresh ? Color(hex: 0xFF6A52) : .white.opacity(0.85))
                }
                .font(.system(size: metaSize, weight: .bold, design: .rounded))
            }
            if let community = item.communityRating {
                Text(String(format: "★ %.1f", community))
                    .font(.system(size: metaSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xF5C518)) // IMDb gold
            }
            Text(metaLine(for: item))
                .font(.system(size: metaSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
    }

    private func actions(for current: MediaItem) -> some View {
        HStack(spacing: Spacing.md) {
            Button { onPlay(current) } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: actionFont, weight: .bold, design: .rounded))
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(tint, in: Capsule())
                    .foregroundStyle(playTextColor)
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: true))
            .focused($focus, equals: .play)

            NavigationLink(value: current) {
                Label("More Info", systemImage: "info.circle")
                    .font(.system(size: actionFont, weight: .semibold, design: .rounded))
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(.black.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .foregroundStyle(.white)
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: true))
            .focused($focus, equals: .info)

            if let onShuffle {
                Button { onShuffle() } label: {
                    Label("Play Something", systemImage: "shuffle")
                        .font(.system(size: actionFont, weight: .semibold, design: .rounded))
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                        .background(.black.opacity(0.35), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .foregroundStyle(.white)
                }
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: true))
                .focused($focus, equals: .shuffle)
            }

            Spacer()

            if items.count > 1 {
                chevron("chevron.left", target: .prev) { advanceManually(-1) }
                pageDots
                chevron("chevron.right", target: .next) { advanceManually(1) }
            } else {
                pageDots
            }
        }
        .padding(.top, Spacing.xs)
        .onChange(of: focus) { _, newValue in isFocused = (newValue != nil) }
    }

    private func chevron(_ system: String, target: HeroFocus, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: actionFont * 0.85, weight: .bold))
                .foregroundStyle(.white)
                .padding(Spacing.sm)
                .background(.black.opacity(0.3), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.18, lift: true))
        .focused($focus, equals: target)
    }

    private func advanceManually(_ delta: Int) {
        guard items.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            index = (index + delta + items.count) % items.count
        }
    }

    private func metaLine(for item: MediaItem) -> String {
        [item.productionYear.map(String.init), item.officialRating, item.genreText]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }

    private var pageDots: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(items.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? tint : Color.white.opacity(0.4))
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

    /// Pre-decode every hero backdrop into the shared cache so rotating to the
    /// next one is instant instead of spiking on a fresh decode.
    private func prefetchBackdrops() {
        for item in items {
            guard let url = backdropURL(for: item) else { continue }
            Task.detached(priority: .utility) { _ = await ImageLoader.shared.image(for: url) }
        }
    }

    private func loadColor() async {
        guard let current else { artColor = nil; return }
        if let cached = colorCache[current.id] {
            artColor = cached
            return
        }
        let color = await ImageColor.vibrant(from: colorURL(current))
        if let color { colorCache[current.id] = color }
        artColor = color
    }

    // MARK: - Image URLs

    private func logoURL(_ item: MediaItem) -> URL? {
        guard let tag = item.imageTags?["Logo"] else { return nil }
        return appState.client?.imageURL(itemID: item.id, kind: .logo, tag: tag, maxWidth: 800)
    }

    private func backdropURL(for item: MediaItem) -> URL? {
        let tag = item.backdropImageTags?.first ?? item.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = (item.backdropImageTags?.isEmpty == false) ? .backdrop : .primary
        return appState.client?.imageURL(itemID: item.id, kind: kind, tag: tag, maxWidth: 1280)
    }

    /// Small image used only for color sampling (keeps the download tiny).
    private func colorURL(_ item: MediaItem?) -> URL? {
        guard let item else { return nil }
        let tag = item.backdropImageTags?.first ?? item.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = (item.backdropImageTags?.isEmpty == false) ? .backdrop : .primary
        return appState.client?.imageURL(itemID: item.id, kind: kind, tag: tag, maxWidth: 240)
    }

    // MARK: - Platform metrics

    private var heroHeight: CGFloat {
        #if os(tvOS)
        720
        #else
        500
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
    private var logoMaxWidth: CGFloat {
        #if os(tvOS)
        720
        #else
        360
        #endif
    }
    private var logoMaxHeight: CGFloat {
        #if os(tvOS)
        150
        #else
        80
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
