import SwiftUI

@Observable
@MainActor
final class SearchViewModel {
    var query = ""
    var results: [MediaItem] = []
    var isSearching = false
    private var task: Task<Void, Never>?

    func search(client: JellyfinClient, userID: String) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; isSearching = false; return }
        isSearching = true
        task = Task {
            // Debounce so we don't fire a request on every keystroke.
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            let items = (try? await client.search(query: q, userID: userID)) ?? []
            if Task.isCancelled { return }
            results = items
            isSearching = false
        }
    }
}

/// Full-library search across movies, shows and episodes.
struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var model = SearchViewModel()

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
            if model.isSearching && model.results.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
            } else if model.results.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.lg) {
                    ForEach(model.results) { item in
                        NavigationLink(value: item) {
                            MediaCard(item: item, style: .poster, fillWidth: true)
                        }
                        .mediaCardButtonStyle()
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .searchable(text: $model.query, prompt: "Movies, shows, episodes")
        .onChange(of: model.query) { _, _ in
            guard let session, let client = appState.client else { return }
            model.search(client: client, userID: session.userID)
        }
        .background(AmbientBackground())
        .navigationTitle("Search")
        .navigationDestination(for: MediaItem.self) { item in
            if item.type == .collectionFolder || item.type == .folder || item.type == .boxSet {
                LibraryContentsView(library: item)
            } else if item.type == .series {
                SeriesDetailView(series: item)
            } else {
                ItemDetailView(item: item)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(UltrafinColors.tertiaryText)
            Text(model.query.isEmpty ? "Search your library" : "No results for “\(model.query)”")
                .font(Typography.body)
                .foregroundStyle(UltrafinColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl * 2)
    }
}
