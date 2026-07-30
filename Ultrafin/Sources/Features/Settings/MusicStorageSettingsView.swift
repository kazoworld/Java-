import SwiftUI

#if os(iOS)
/// Music → Downloads & Storage. Shows what's on the device, downloads or syncs
/// the whole library, and clears either tier. iPhone/iPad only — a TV is always
/// on the network, so there's nothing to take offline.
struct MusicStorageSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var store = MusicLibraryCache.shared
    @State private var artworkBytes: Int64 = 0
    @State private var confirmClearCache = false
    @State private var confirmRemoveDownloads = false
    @State private var job: Task<Void, Never>?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                NavigationLink { DownloadedMusicView() } label: {
                    storageRow(title: "Downloads",
                               detail: downloadsDetail,
                               bytes: store.downloadedBytes,
                               icon: "arrow.down.circle.fill", tint: .blue)
                }
                storageRow(title: "Cached",
                           detail: "\(store.cachedCount) songs",
                           bytes: store.cachedBytes,
                           icon: "clock.arrow.circlepath", tint: .orange)
                storageRow(title: "Album Art",
                           detail: "Covers kept on device",
                           bytes: artworkBytes,
                           icon: "photo.stack.fill", tint: .purple)
            } header: {
                Text("On this device")
            } footer: {
                Text("Downloads stay until you remove them. Cached songs are kept automatically after a few plays and are dropped once they go two weeks without one.")
            }

            if let label = store.jobLabel {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(label)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(UltrafinColors.primaryText)
                        ProgressView(value: store.jobProgress)
                            .tint(settings.theme.accent.color)
                    }
                    Button("Stop", role: .destructive) {
                        job?.cancel()
                        job = nil
                    }
                }
            }

            Section {
                Toggle("Keep frequently played songs", isOn: $settings.cacheFrequentSongs)
                Toggle("Download over cellular", isOn: $settings.downloadOverCellular)
                if store.lastBlockedByCellular && !settings.downloadOverCellular {
                    Label("Waiting for Wi-Fi — some downloads were skipped.",
                          systemImage: "wifi.exclamationmark")
                        .font(Typography.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Automatic")
            } footer: {
                Text("A song is kept on device after a few plays, so the music you actually listen to is always instant and available offline.")
            }

            Section {
                Button {
                    runJob { source in
                        await store.downloadEntireLibrary(source: source)
                    }
                } label: {
                    Label("Download Entire Library", systemImage: "arrow.down.circle")
                }
                .disabled(store.isWorking)

                Button {
                    runJob { source in
                        await store.sync(source: source)
                    }
                } label: {
                    Label("Sync Library", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isWorking)
            } header: {
                Text("Library")
            } footer: {
                Text("Syncing removes songs your server no longer has, re-downloads anything missing, and tidies up stale cache entries.")
            }

            Section {
                Button("Clear Cache", role: .destructive) { confirmClearCache = true }
                    .disabled(store.cachedBytes == 0 && artworkBytes == 0)
                Button("Remove All Downloads", role: .destructive) { confirmRemoveDownloads = true }
                    .disabled(store.downloadedCount == 0)
            } header: {
                Text("Free up space")
            }
        }
        .glassRows()
        .scrollContentBackground(.hidden)
        .musicCanvas()
        .navigationTitle("Downloads & Storage")
        .tint(settings.theme.accent.color)
        .task { refreshArtworkSize() }
        .onDisappear { job?.cancel() }
        .confirmationDialog("Clear cached songs and album art?",
                            isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) {
                store.clearCache()
                ImageLoader.shared.clearArtworkCache()
                refreshArtworkSize()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your downloads are kept. Cached songs and covers will be fetched again as you listen.")
        }
        .confirmationDialog("Remove all downloaded songs?",
                            isPresented: $confirmRemoveDownloads, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { store.removeAllDownloads() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll need to be downloaded again to play offline.")
        }
    }

    private func storageRow(title: String, detail: String, bytes: Int64,
                            icon: String, tint: Color) -> some View {
        HStack(spacing: Spacing.md) {
            SettingsRowLabel(title: title, subtitle: detail, systemImage: icon, tint: tint)
            Spacer(minLength: Spacing.sm)
            Text(StorageFormat.string(bytes))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(UltrafinColors.secondaryText)
                .monospacedDigit()
        }
    }

    /// "4 albums · 2 singles · 1 partial" — the shape of what's on the device.
    private var downloadsDetail: String {
        let albums = store.downloadedAlbums()
        guard !albums.isEmpty else { return "Nothing yet" }
        let singles = albums.filter(\.isSingle).count
        let complete = albums.filter(\.isComplete).count
        let partial = albums.count - singles - complete
        var parts: [String] = []
        if complete > 0 { parts.append("\(complete) album\(complete == 1 ? "" : "s")") }
        if singles > 0 { parts.append("\(singles) single\(singles == 1 ? "" : "s")") }
        if partial > 0 { parts.append("\(partial) partial") }
        return parts.joined(separator: " · ")
    }

    private func refreshArtworkSize() {
        artworkBytes = ImageLoader.shared.artworkCacheBytes()
    }

    /// Runs a bulk job against the active music source, cancellable from the UI.
    private func runJob(_ work: @escaping (MusicSource) async -> Void) {
        guard let source = appState.musicSource, !store.isWorking else { return }
        Haptics.play(.medium)
        job = Task {
            await work(source)
            refreshArtworkSize()
            job = nil
        }
    }
}
#endif
