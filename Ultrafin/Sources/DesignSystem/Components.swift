import SwiftUI
import UIKit

// MARK: - Glass surface

/// A frosted, slightly elevated container used for cards, sheets and controls.
/// Now backed by the ``LiquidGlass`` layer — material + top sheen + rim light +
/// soft lift — so it reads as a lit pane of glass without expensive blur on tvOS.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = Spacing.cornerRadius

    func body(content: Content) -> some View {
        content.liquidGlass(cornerRadius: cornerRadius)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Spacing.cornerRadius) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Liquid Glass row backgrounds for Forms/Lists shown over the ambient —
    /// real system glass with the brand rim, no lift shadow (rows shouldn't
    /// float). Propagates to every row in the list.
    func glassRows() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return listRowBackground(
            Color.clear
                .glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(LiquidGlass.rim(0.7), lineWidth: 1))
                .padding(.vertical, 2)
        )
    }
}

// MARK: - tvOS focus plumbing

extension View {
    /// Makes a non-interactive row reachable by the tvOS focus engine. Without
    /// at least a path of focusable rows, an information-only Form can't scroll
    /// and a Menu press falls through to the system (exiting the app). No-op on
    /// iOS, where touch scrolling needs no focus.
    @ViewBuilder
    func tvFocusable() -> some View {
        #if os(tvOS)
        self.focusable()
        #else
        self
        #endif
    }

    /// tvOS: make Menu/Back pop this *pushed* screen. Without it, a screen whose
    /// content the focus engine doesn't own lets the exit command fall through to
    /// the system, which quits to the Apple TV Home Screen instead of going back.
    /// No-op on iOS, where the navigation bar's back button handles it.
    @ViewBuilder
    func tvPopsOnMenu() -> some View {
        #if os(tvOS)
        modifier(TVPopOnMenu())
        #else
        self
        #endif
    }
}

#if os(tvOS)
/// Wires the remote's Menu button to dismiss (pop) the current pushed view.
private struct TVPopOnMenu: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.onExitCommand { dismiss() }
    }
}
#endif

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
            .background {
                let shape = RoundedRectangle(cornerRadius: Spacing.md, style: .continuous)
                let accent = settings.accent
                shape
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.82)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(shape.fill(LiquidGlass.sheen))
                    .overlay(shape.strokeBorder(LiquidGlass.rim(0.7), lineWidth: 1))
                    .shadow(color: accent.opacity(0.4), radius: 12, y: 6)
            }
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
    /// Album art also lands on disk, so covers survive a relaunch instead of
    /// being re-downloaded every cold start. Capped and pruned oldest-first.
    private let diskDirectory: URL?
    private static let diskBudget: Int64 = 220 * 1024 * 1024

    private init() {
        cache.countLimit = 240
        let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
        diskDirectory = base?.appendingPathComponent("UltrafinArtwork", isDirectory: true)
        if let diskDirectory {
            try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        }
    }

    /// Returns a decoded image for `url`: memory first, then disk, then network.
    func image(for url: URL) async -> UIImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }

        let task: Task<UIImage?, Never> = {
            lock.lock()
            defer { lock.unlock() }
            if let existing = inFlight[key] { return existing }
            let new = Task<UIImage?, Never> { [weak self] in
                guard let self else { return nil }
                if let onDisk = self.readDisk(url) {
                    self.cache.setObject(onDisk, forKey: key)
                    self.finish(key)
                    return onDisk
                }
                let image = await Self.download(url)
                if let image {
                    self.cache.setObject(image, forKey: key)
                    self.writeDisk(image, for: url)
                }
                self.finish(key)
                return image
            }
            inFlight[key] = new
            return new
        }()

        return await task.value
    }

    // MARK: - Disk layer

    private func diskURL(for url: URL) -> URL? {
        guard let diskDirectory else { return nil }
        // A stable, filesystem-safe name from the full URL (which already
        // carries the server's image tag, so it changes when the art changes).
        var hash: UInt64 = 5381
        for byte in Array(url.absoluteString.utf8) {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return diskDirectory.appendingPathComponent(String(hash, radix: 36) + ".jpg")
    }

    private func readDisk(_ url: URL) -> UIImage? {
        guard let path = diskURL(for: url),
              let data = try? Data(contentsOf: path),
              let image = UIImage(data: data)?.preparingForDisplay()
        else { return nil }
        // Touch it so pruning treats it as recently used.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        return image
    }

    private func writeDisk(_ image: UIImage, for url: URL) {
        guard let path = diskURL(for: url), let data = image.jpegData(compressionQuality: 0.86) else { return }
        try? data.write(to: path, options: .atomic)
        pruneDiskIfNeeded()
    }

    /// Trim the artwork cache to its budget, oldest-touched first.
    private func pruneDiskIfNeeded() {
        guard let diskDirectory else { return }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskDirectory, includingPropertiesForKeys: keys) else { return }
        var total: Int64 = 0
        var described: [(url: URL, size: Int64, date: Date)] = []
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            let size = Int64(values.fileSize ?? 0)
            total += size
            described.append((file, size, values.contentModificationDate ?? .distantPast))
        }
        guard total > Self.diskBudget else { return }
        for item in described.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: item.url)
            total -= item.size
            if total <= Self.diskBudget * 3 / 4 { break }
        }
    }

    /// Drop every cached cover from disk and memory (Settings → Storage).
    func clearArtworkCache() {
        cache.removeAllObjects()
        guard let diskDirectory else { return }
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    /// Bytes currently held by cached artwork.
    func artworkCacheBytes() -> Int64 {
        guard let diskDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: diskDirectory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return files.reduce(0) { sum, file in
            sum + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
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
    /// What VoiceOver should call this. Artwork is almost always decorative —
    /// the title sits right beside it — so the default is to stay silent rather
    /// than announce "image" over and over down a list.
    var voiceOverLabel: String? = nil

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
        .accessibilityLabel(voiceOverLabel ?? "")
        .accessibilityHidden(voiceOverLabel == nil)
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
    /// A placeholder pulsing forever is ambient motion by definition — under
    /// Reduce Motion the surface simply sits there until content arrives.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // .clipped() instead of .mask(Rectangle()) — same clip, no offscreen
            // mask-compositing pass.
            .clipped()
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
