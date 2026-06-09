import SwiftUI

@Observable
@MainActor
final class LibraryViewModel {
    var libraries: [MediaItem] = []
    var isLoading = true

    func load(client: JellyfinClient, userID: String) async {
        isLoading = true
        defer { isLoading = false }
        libraries = (try? await client.userViews(userID: userID)) ?? []
    }
}

/// Top-level libraries grid; tapping one drills into its contents.
struct LibraryRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var model = LibraryViewModel()

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    // Library cards are wide banners; columns are sized per platform and scale
    // with the Card size setting. Cards fill their cell so nothing clips.
    private var columns: [GridItem] {
        let scale = settings.appearance.cardDensity.scale
        #if os(tvOS)
        let minWidth = 360.0 * scale
        #else
        let minWidth = 240.0 * scale
        #endif
        return [GridItem(.adaptive(minimum: minWidth, maximum: minWidth * 1.4), spacing: Spacing.lg)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.lg) {
                ForEach(model.libraries) { library in
                    NavigationLink(value: library) {
                        MediaCard(item: library, style: .landscape, fillWidth: true)
                    }
                    .mediaCardButtonStyle()
                }
            }
            .padding(Spacing.lg)
        }
        .background(AmbientBackground())
        .navigationTitle("Library")
        .navigationDestination(for: MediaItem.self) { item in
            if item.type == .collectionFolder || item.type == .folder {
                LibraryContentsView(library: item)
            } else if item.type == .series {
                SeriesDetailView(series: item)
            } else {
                ItemDetailView(item: item)
            }
        }
        .task {
            guard let session, let client = appState.client else { return }
            await model.load(client: client, userID: session.userID)
        }
    }
}

/// Contents of a single library, rendered as an adaptive poster grid.
struct LibraryContentsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    let library: MediaItem

    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    private var columns: [GridItem] {
        let scale = settings.appearance.cardDensity.scale
        #if os(tvOS)
        let minWidth = 200.0 * scale
        #else
        let minWidth = 130.0 * scale
        #endif
        return [GridItem(.adaptive(minimum: minWidth, maximum: minWidth * 1.4), spacing: Spacing.lg)]
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(.top, Spacing.xxl)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.lg) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaCard(item: item, style: .poster, fillWidth: true)
                        }
                        .mediaCardButtonStyle()
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .background(AmbientBackground())
        .navigationTitle(library.name)
        .task {
            guard let session, let client = appState.client else { return }
            items = (try? await client.items(in: library.id, userID: session.userID)) ?? []
            isLoading = false
        }
    }
}
