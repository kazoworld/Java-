import SwiftUI

#if os(iOS)
/// "Add to Playlist" — pick an existing one, or type a name and make it.
///
/// The list loads from the server rather than from whatever the Library tab
/// happened to fetch: a playlist made on another device, or five minutes ago on
/// this one, should be here.
struct AddToPlaylistSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    /// The songs to file. One from a track menu; a whole record from an album.
    let songs: [MediaItem]

    @State private var playlists: [MediaItem] = []
    @State private var isLoading = true
    @State private var newName = ""
    @State private var isCreating = false
    /// Set while a write is in flight so the sheet can't be double-submitted.
    @State private var working = false
    @State private var failure: String?

    private var title: String {
        songs.count == 1 ? (songs.first?.name ?? "Song") : "\(songs.count) songs"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isCreating {
                        HStack {
                            TextField("Playlist name", text: $newName)
                                .submitLabel(.done)
                                .onSubmit { create() }
                            Button("Create", action: create)
                                .disabled(newName.trimmed.isEmpty || working)
                        }
                    } else {
                        Button {
                            withAnimation(.snappy) { isCreating = true }
                        } label: {
                            Label("New Playlist", systemImage: "plus")
                        }
                    }
                }

                Section {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if playlists.isEmpty {
                        Text("No playlists yet.")
                            .foregroundStyle(UltrafinColors.secondaryText)
                    } else {
                        ForEach(playlists) { playlist in
                            Button { add(to: playlist) } label: {
                                HStack(spacing: Spacing.md) {
                                    RemoteImage(url: appState.musicSource?
                                        .artworkURL(for: playlist, maxWidth: 120))
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    Text(playlist.name)
                                        .foregroundStyle(UltrafinColors.primaryText)
                                    Spacer(minLength: 0)
                                }
                            }
                            .disabled(working)
                        }
                    }
                } header: {
                    Text("Your Playlists")
                }

                if let failure {
                    Section {
                        Text(failure).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .tint(settings.accent)
        }
        .task { await load() }
    }

    private func load() async {
        guard let source = appState.musicSource else { isLoading = false; return }
        playlists = (try? await source.playlists()) ?? []
        isLoading = false
    }

    private func add(to playlist: MediaItem) {
        guard let source = appState.musicSource, !working else { return }
        working = true
        Task {
            let ok = await source.addToPlaylist(playlistID: playlist.id, songIDs: songs.map(\.id))
            working = false
            if ok {
                Haptics.play(.success)
                dismiss()
            } else {
                failure = "Couldn't add to \(playlist.name)."
            }
        }
    }

    private func create() {
        let name = newName.trimmed
        guard let source = appState.musicSource, !name.isEmpty, !working else { return }
        working = true
        Task {
            // Seeded at creation rather than created-then-filled: one round trip,
            // and no window where a half-made playlist exists if the second call
            // fails.
            let created = await source.createPlaylist(named: name, songIDs: songs.map(\.id))
            working = false
            if created {
                Haptics.play(.success)
                dismiss()
            } else {
                failure = "Couldn't create \"\(name)\"."
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif

#if os(iOS)
/// A songs payload with an identity, so `sheet(item:)` can present it.
///
/// `sheet(item:)` needs something Identifiable, and a bare `[MediaItem]` isn't.
/// The id is derived from the songs themselves so re-presenting the same
/// selection doesn't rebuild the sheet.
struct SongSelection: Identifiable {
    let songs: [MediaItem]
    var id: String { songs.map(\.id).joined(separator: "+") }

    init(_ songs: [MediaItem]) { self.songs = songs }
}
#endif
