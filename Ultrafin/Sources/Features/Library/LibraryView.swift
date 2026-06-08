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

    // Grid sizing tracks the Card size setting so the whole grid grows/shrinks.
    private var columns: [GridItem] {
        let scale = settings.appearance.cardDensity.scale
        return [GridItem(.adaptive(minimum: 150 * scale, maximum: 200 * scale), spacing: Spacing.md)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.lg) {
                ForEach(model.libraries) { library in
                    NavigationLink(value: library) {
                        MediaCard(item: library, style: .poster)
                    }
                    .mediaCardButtonStyle()
                }
            }
            .padding(Spacing.lg)
        }
        .background(UltrafinColors.background.ignoresSafeArea())
        .navigationTitle("Library")
        .navigationDestination(for: MediaItem.self) { item in
            if item.type == .collectionFolder || item.type == .folder {
                LibraryContentsView(library: item)
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
        return [GridItem(.adaptive(minimum: 130 * scale, maximum: 180 * scale), spacing: Spacing.md)]
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(.top, Spacing.xxl)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.lg) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaCard(item: item, style: .poster)
                        }
                        .mediaCardButtonStyle()
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .background(UltrafinColors.background.ignoresSafeArea())
        .navigationTitle(library.name)
        .task {
            guard let session, let client = appState.client else { return }
            items = (try? await client.items(in: library.id, userID: session.userID)) ?? []
            isLoading = false
        }
    }
}
