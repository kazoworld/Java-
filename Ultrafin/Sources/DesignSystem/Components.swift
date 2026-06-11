import SwiftUI
import UIKit

// MARK: - Glass surface

/// A frosted, slightly elevated container used for cards, sheets and controls.
/// The material + thin stroke reads as "glass" without expensive blur on tvOS.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = Spacing.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(UltrafinColors.separator, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Spacing.cornerRadius) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Frosted-glass row backgrounds for Forms/Lists shown over the ambient.
    /// Propagates to every row in the list.
    func glassRows() -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(UltrafinColors.separator, lineWidth: 1)
                )
                .padding(.vertical, 2)
        )
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(settings.theme.accent.color, in: RoundedRectangle(cornerRadius: Spacing.md, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))
        .disabled(isLoading)
    }
}

// MARK: - Cached image loader

/// A shared, in-memory image cache + de-duplicating downloader.
///
/// `AsyncImage`'s built-in cache is tiny and per-view, so as `LazyVStack`/
/// `LazyVGrid` recycle cells it re-downloads art — that's the source of the
/// "sometimes it loads, sometimes it doesn't" flicker and the scroll jank from
/// repeated decodes. This keeps decoded `UIImage`s around (keyed by URL) and
/// coalesces concurrent requests for the same URL into one network task, so a
/// cell that scrolls back into view paints instantly with no work on the main
/// thread.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let lock = NSLock()
    private var inFlight: [NSURL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 240
    }

    /// Returns a decoded image for `url`, hitting the in-memory cache first.
    func image(for url: URL) async -> UIImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }

        let task: Task<UIImage?, Never> = {
            lock.lock()
            defer { lock.unlock() }
            if let existing = inFlight[key] { return existing }
            let new = Task<UIImage?, Never> { [weak self] in
                let image = await Self.download(url)
                if let image, let self { self.cache.setObject(image, forKey: key) }
                self?.finish(key)
                return image
            }
            inFlight[key] = new
            return new
        }()

        return await task.value
    }

    /// Synchronous cache peek — lets a view paint immediately if the art is
    /// already decoded (no flash of placeholder on scroll-back).
    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    private func finish(_ key: NSURL) {
        lock.lock(); defer { lock.unlock() }
        inFlight[key] = nil
    }

    private static func download(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        // Decode off the main thread so scrolling never stalls on it.
        return UIImage(data: data)?.preparingForDisplay()
    }
}

// MARK: - Async image with graceful placeholder

/// Lightweight remote image backed by ``ImageLoader``'s shared cache, so
/// scrolling grids never block the main thread on decode and recycled cells
/// repaint instantly instead of re-downloading.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail {
                placeholder.overlay(Image(systemName: "photo").foregroundStyle(UltrafinColors.tertiaryText))
            } else {
                placeholder.shimmer()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { didFail = true; return }
        // Instant paint when already decoded — no placeholder flash on scroll-back.
        if let hit = ImageLoader.shared.cached(url) {
            image = hit
            return
        }
        image = nil
        didFail = false
        let loaded = await ImageLoader.shared.image(for: url)
        guard !Task.isCancelled else { return }
        if let loaded {
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        } else {
            didFail = true
        }
    }

    private var placeholder: some View {
        UltrafinColors.elevatedSurface
    }
}

// MARK: - Shimmer

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.12), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.5)
                .offset(x: phase * geo.size.width * 1.5)
            }
            .mask(Rectangle())
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
