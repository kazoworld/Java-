import SwiftUI

// MARK: - Confirmation HUD

/// The small confirmation that floats up when you queue something from a
/// menu — "Playing Next", "Added to Queue" — so an action taken without
/// opening the player still visibly lands somewhere.
@Observable
@MainActor
final class MusicHUD {
    static let shared = MusicHUD()

    struct Message: Equatable {
        let id = UUID()
        let text: String
        let systemImage: String
    }

    private(set) var message: Message?

    func show(_ text: String, systemImage: String) {
        Haptics.play(.success)
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
            message = Message(text: text, systemImage: systemImage)
        }
    }

    fileprivate func dismiss(_ id: UUID) {
        guard message?.id == id else { return }
        withAnimation(.smooth(duration: 0.3)) { message = nil }
    }
}

private struct MusicHUDOverlay: ViewModifier {
    @State private var hud = MusicHUD.shared

    func body(content: Content) -> some View {
        content.overlay {
            if let message = hud.message {
                MusicHUDView(message: message)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .task(id: message.id) {
                        try? await Task.sleep(for: .seconds(1.4))
                        hud.dismiss(message.id)
                    }
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct MusicHUDView: View {
    let message: MusicHUD.Message

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: message.systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .symbolEffect(.bounce, value: message.id)
            Text(message.text)
                .font(.system(size: textSize, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.primary)
        .padding(Spacing.lg)
        .frame(minWidth: side, minHeight: side)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
    }

    private var side: CGFloat {
        #if os(tvOS)
        220
        #else
        140
        #endif
    }
    private var iconSize: CGFloat {
        #if os(tvOS)
        56
        #else
        38
        #endif
    }
    private var textSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
}

extension View {
    /// Host the music confirmation HUD over this view (once, near the root).
    func musicHUD() -> some View {
        modifier(MusicHUDOverlay())
    }
}

// MARK: - Album / playlist long-press

/// Long-press on an album or playlist tile: play it, shuffle it or queue it
/// without opening it first — the Apple Music context menu. The songs are
/// fetched when an action is chosen, not when the menu opens, so browsing a
/// shelf costs nothing.
private struct MusicContainerMenu: ViewModifier {
    @Environment(AppState.self) private var appState
    let item: MediaItem

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { run(.play) } label: { Label("Play", systemImage: "play.fill") }
            Button { run(.shuffle) } label: { Label("Shuffle", systemImage: "shuffle") }
            Divider()
            Button { run(.next) } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button { run(.later) } label: { Label("Add to Queue", systemImage: "text.append") }
        }
    }

    private enum Action { case play, shuffle, next, later }

    private func run(_ action: Action) {
        guard let source = appState.musicSource else { return }
        let item = item
        Task { @MainActor in
            let tracks: [MediaItem]
            if item.type == .playlist {
                tracks = (try? await source.playlistTracks(playlistID: item.id)) ?? []
            } else {
                tracks = (try? await source.albumTracks(albumID: item.id)) ?? []
            }
            guard !tracks.isEmpty else { return }
            let player = MusicPlayer.shared
            switch action {
            case .play:
                player.play(tracks: tracks, source: source, context: item.name)
            case .shuffle:
                player.play(tracks: tracks, source: source, shuffled: true, context: item.name)
            case .next:
                player.playNext(tracks: tracks, source: source)
                MusicHUD.shared.show("Playing Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            case .later:
                player.addToQueue(tracks: tracks, source: source)
                MusicHUD.shared.show("Added to Queue", systemImage: "text.append")
            }
        }
    }
}

extension View {
    /// Attach the play / shuffle / queue long-press menu for an album or
    /// playlist.
    func musicContainerMenu(_ item: MediaItem) -> some View {
        modifier(MusicContainerMenu(item: item))
    }
}

// MARK: - Loading shelves

/// What Home shows while it loads: the shape of the shelves that are coming,
/// shimmering quietly, instead of a lone spinner over an empty page — so the
/// content arrives *into* a layout rather than replacing a void.
struct MusicShelfSkeleton: View {
    var tile: CGFloat
    var edgePadding: CGFloat
    var circular = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(UltrafinColors.elevatedSurface)
                .frame(width: tile * 1.1, height: tile * 0.15)
                .shimmer()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(.horizontal, edgePadding)
            HStack(alignment: .top, spacing: Spacing.md) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Group {
                            if circular {
                                Circle().fill(UltrafinColors.elevatedSurface)
                            } else {
                                RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                                    .fill(UltrafinColors.elevatedSurface)
                            }
                        }
                        .frame(width: tile, height: tile)
                        .shimmer()
                        .clipShape(RoundedRectangle(cornerRadius: circular ? tile / 2 : Spacing.posterCornerRadius,
                                                    style: .continuous))
                        Capsule()
                            .fill(UltrafinColors.elevatedSurface)
                            .frame(width: tile * 0.7, height: 9)
                        Capsule()
                            .fill(UltrafinColors.elevatedSurface.opacity(0.6))
                            .frame(width: tile * 0.45, height: 9)
                    }
                }
            }
            .padding(.horizontal, edgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - See all

/// "See All" behind a shelf's chevron: the whole shelf as a grid.
struct MusicShelfGridView: View {
    let title: String
    let items: [MediaItem]

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVGrid(columns: MusicGrid.columns, alignment: .leading, spacing: MusicGrid.spacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                    NavigationLink(value: item) {
                        if item.type == .musicArtist {
                            ArtistCard(artist: item)
                        } else {
                            GridAlbumCard(album: item)
                        }
                    }
                    .musicCardButtonStyle()
                    .cardZoomSource(item.id)
                    .modifier(ContainerMenuIfAlbum(item: item))
                    // The first screenful settles in one after another rather
                    // than all at once.
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 14)
                    .animation(.smooth(duration: 0.45).delay(Double(min(position, 11)) * 0.03),
                               value: appeared)
                }
            }
            .padding(MusicGrid.edgePadding)
        }
        .musicCanvas()
        .onAppear { appeared = true }
        #if os(iOS)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .adaptsChromeOnScroll()
        #endif
    }
}

/// Artists have no tracks to queue; only albums and playlists get the menu.
private struct ContainerMenuIfAlbum: ViewModifier {
    let item: MediaItem
    func body(content: Content) -> some View {
        if item.type == .musicArtist {
            content
        } else {
            content.musicContainerMenu(item)
        }
    }
}
