import SwiftUI

@Observable
@MainActor
final class SearchViewModel {
    var query = ""
    var results: [MediaItem] = []
    var isSearching = false
    /// The user's last few searches, newest first (persisted).
    private(set) var recentSearches: [String]
    private var task: Task<Void, Never>?

    private static let recentKey = "search.recent"
    private static let recentLimit = 8

    init() {
        recentSearches = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

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
            // A search that found something is worth remembering.
            if !items.isEmpty { remember(q) }
        }
    }

    private func remember(_ term: String) {
        var recents = recentSearches.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recents.insert(term, at: 0)
        recentSearches = Array(recents.prefix(Self.recentLimit))
        UserDefaults.standard.set(recentSearches, forKey: Self.recentKey)
    }

    func clearRecents() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: Self.recentKey)
    }
}

/// What kind of results to show — a quick client-side lens over one search.
private enum SearchScope: String, CaseIterable, Identifiable {
    case all = "All"
    case movies = "Movies"
    case shows = "TV Shows"
    var id: String { rawValue }

    func matches(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .movies: return item.type == .movie
        case .shows: return item.type == .series || item.type == .episode
        }
    }
}

/// Full-library search across movies, shows and episodes, with recent searches
/// and quick Movies/TV filters.
struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var model = SearchViewModel()
    @State private var scope: SearchScope = .all

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    private var filteredResults: [MediaItem] {
        model.results.filter { scope.matches($0) }
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
            if model.query.isEmpty {
                recentsSection
            } else if model.isSearching && model.results.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
            } else if model.results.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    scopePills
                    if filteredResults.isEmpty {
                        Text("No \(scope.rawValue.lowercased()) match “\(model.query)”")
                            .font(Typography.body)
                            .foregroundStyle(UltrafinColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Spacing.xxl)
                    } else {
                        LazyVGrid(columns: columns, spacing: Spacing.lg) {
                            ForEach(filteredResults) { item in
                                NavigationLink(value: item) {
                                    MediaCard(item: item, style: .poster, fillWidth: true)
                                }
                                .mediaCardButtonStyle()
                            }
                        }
                        .animation(.smooth(duration: 0.3), value: filteredResults)
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

    // MARK: - Scope filter

    private var scopePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(SearchScope.allCases) { option in
                    let active = scope == option
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { scope = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: pillFont, weight: .semibold, design: .rounded))
                            .foregroundStyle(active ? .white : UltrafinColors.primaryText)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background {
                                if active {
                                    Capsule().fill(settings.theme.accent.color.gradient)
                                } else {
                                    Capsule().fill(.ultraThinMaterial)
                                }
                                Capsule().fill(LiquidGlass.sheen)
                            }
                            .overlay(Capsule().strokeBorder(LiquidGlass.rim(active ? 0.6 : 0.4), lineWidth: 1))
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: false))
                }
            }
            .padding(.vertical, Spacing.xs)
        }
        .scrollClipDisabled()
    }

    // MARK: - Recents

    @ViewBuilder
    private var recentsSection: some View {
        if model.recentSearches.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Recent Searches")
                        .font(Typography.sectionTitle)
                        .foregroundStyle(UltrafinColors.primaryText)
                    Spacer()
                    Button("Clear") { withAnimation(.smooth(duration: 0.25)) { model.clearRecents() } }
                        .font(.system(size: pillFont, weight: .semibold, design: .rounded))
                        .foregroundStyle(settings.theme.accent.color)
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: false))
                }

                // Wrapping rows of tappable capsules — tap to re-run a search.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: recentMinWidth), spacing: Spacing.sm, alignment: .leading)],
                          alignment: .leading, spacing: Spacing.sm) {
                    ForEach(model.recentSearches, id: \.self) { term in
                        Button { model.query = term } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: pillFont * 0.85))
                                    .foregroundStyle(UltrafinColors.tertiaryText)
                                Text(term)
                                    .font(.system(size: pillFont, weight: .medium, design: .rounded))
                                    .foregroundStyle(UltrafinColors.primaryText)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background {
                                Capsule().fill(.ultraThinMaterial)
                                Capsule().fill(LiquidGlass.sheen)
                            }
                            .overlay(Capsule().strokeBorder(LiquidGlass.rim(0.4), lineWidth: 1))
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: false))
                    }
                }
            }
            .padding(Spacing.lg)
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

    // MARK: - Metrics

    private var pillFont: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }
    private var recentMinWidth: CGFloat {
        #if os(tvOS)
        260
        #else
        150
        #endif
    }
}
