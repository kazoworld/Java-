import Foundation
#if os(iOS)
import CarPlay
import UIKit

/// Ultrafin in the car.
///
/// CarPlay is not a smaller version of the app — it's a fixed set of templates
/// the system draws itself, and the only real design work is deciding which
/// four or five things are worth reaching for at 70mph. That's: what you were
/// already playing, what you play most, what you added recently, and your
/// playlists. Everything else is a menu too deep to use while driving.
///
/// **This will not activate until Apple grants the `carplay-audio`
/// entitlement.** That's a request you make to Apple per-app, and adding the
/// entitlement to the project before it's granted breaks device signing — so
/// the code and the scene declaration are here, and the entitlement isn't.
/// Once Apple approves it, add `com.apple.developer.carplay-audio` to the
/// target's entitlements and this begins working with no other change.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect controller: CPInterfaceController) {
        interfaceController = controller
        controller.setRootTemplate(rootTemplate(), animated: false, completion: nil)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController controller: CPInterfaceController) {
        interfaceController = nil
    }

    // MARK: - Templates

    private func rootTemplate() -> CPTabBarTemplate {
        let tabs = [
            listTemplate(title: "Recent", image: UIImage(systemName: "clock"), source: .recentlyPlayed),
            listTemplate(title: "Albums", image: UIImage(systemName: "square.stack"), source: .albums),
            listTemplate(title: "Playlists", image: UIImage(systemName: "music.note.list"), source: .playlists)
        ]
        return CPTabBarTemplate(templates: tabs)
    }

    /// What a tab draws. Loading is deferred to `willAppear` rather than done up
    /// front: the car connects before the app has necessarily reached its
    /// server, and a tab that fills itself when shown is right either way.
    private enum Shelf { case recentlyPlayed, albums, playlists }

    private func listTemplate(title: String, image: UIImage?, source: Shelf) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabImage = image
        template.emptyViewSubtitleVariants = ["Nothing here yet."]
        Task { @MainActor in
            let items = await load(source)
            template.updateSections([CPListSection(items: items.map(row))])
        }
        return template
    }

    @MainActor
    private func load(_ shelf: Shelf) async -> [MediaItem] {
        guard let musicSource = AppState.shared?.musicSource else { return [] }
        switch shelf {
        case .recentlyPlayed: return (try? await musicSource.recentlyPlayedSongs()) ?? []
        case .albums: return (try? await musicSource.allAlbums()) ?? []
        case .playlists: return (try? await musicSource.playlists()) ?? []
        }
    }

    /// One row. Tapping a song plays it; tapping a container opens its tracks,
    /// because a car is the last place to guess what a title contains.
    @MainActor
    private func row(_ item: MediaItem) -> CPListItem {
        let row = CPListItem(text: item.name, detailText: item.artistText)
        row.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.open(item)
                completion()
            }
        }
        return row
    }

    @MainActor
    private func open(_ item: MediaItem) async {
        guard let musicSource = AppState.shared?.musicSource else { return }
        switch item.type {
        case .audio:
            MusicPlayer.shared.play(tracks: [item], source: musicSource, context: item.album)
            interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
        default:
            let tracks: [MediaItem]
            if item.type == .playlist {
                tracks = (try? await musicSource.playlistTracks(playlistID: item.id)) ?? []
            } else {
                tracks = (try? await musicSource.albumTracks(albumID: item.id)) ?? []
            }
            guard !tracks.isEmpty else { return }
            let list = CPListTemplate(title: item.name,
                                      sections: [CPListSection(items: tracks.map(trackRow(tracks)))])
            interfaceController?.pushTemplate(list, animated: true, completion: nil)
        }
    }

    /// A track inside a container starts the whole container from that point,
    /// which is what "play this song off this album" means everywhere else.
    @MainActor
    private func trackRow(_ tracks: [MediaItem]) -> (MediaItem) -> CPListItem {
        { track in
            let row = CPListItem(text: track.name, detailText: track.artistText)
            row.handler = { _, completion in
                Task { @MainActor in
                    if let musicSource = AppState.shared?.musicSource,
                       let start = tracks.firstIndex(where: { $0.id == track.id }) {
                        MusicPlayer.shared.play(tracks: tracks, startAt: start, source: musicSource)
                    }
                    completion()
                }
            }
            return row
        }
    }
}
#endif
