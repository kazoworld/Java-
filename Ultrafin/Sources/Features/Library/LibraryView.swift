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
            if item.type == .collectionFolder || item.type == .folder || item.type == .boxSet {
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

/// How a library grid is ordered. Recently Added (newest first) is the default.
enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyAdded, alphabetical, releaseYear, topRated
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .alphabetical: "A–Z"
        case .releaseYear: "Year"
        case .topRated: "Top Rated"
        }
    }
    var icon: String {
        switch self {
        case .recentlyAdded: "clock"
        case .alphabetical: "textformat"
        case .releaseYear: "calendar"
        case .topRated: "star.fill"
        }
    }
    var sortBy: String {
        switch self {
        case .recentlyAdded: "DateCreated,SortName"
        case .alphabetical: "SortName"
        case .releaseYear: "ProductionYear,PremiereDate,SortName"
        case .topRated: "CommunityRating,SortName"
        }
    }
    var sortOrder: String { self == .alphabetical ? "Ascending" : "Descending" }
}

/// Contents of a single library, rendered as an adaptive poster grid with a
/// labeled sort control (Recently Added / A–Z / Year / Top Rated).
struct LibraryContentsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    let library: MediaItem

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var sort: LibrarySort = .recentlyAdded

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
        // Generous spacing so posters and their titles never crowd the next row.
        return [GridItem(.adaptive(minimum: minWidth, maximum: minWidth * 1.4), spacing: gridSpacing)]
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        Spacing.xl
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                sortBar
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
                } else {
                    LazyVGrid(columns: columns, spacing: gridSpacing) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item, style: .poster, fillWidth: true)
                            }
                            .mediaCardButtonStyle()
                        }
                    }
                    .animation(.smooth(duration: 0.45), value: items)
                }
            }
            .padding(Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(AmbientBackground())
        .navigationTitle(library.name)
        .task(id: sort) {
            guard let session, let client = appState.client else { return }
            isLoading = items.isEmpty
            items = (try? await client.items(in: library.id, userID: session.userID,
                                             sortBy: sort.sortBy, sortOrder: sort.sortOrder)) ?? []
            isLoading = false
        }
    }

    /// A scrollable row of labeled sort pills — the active one fills with accent.
    private var sortBar: some View {
        HStack(spacing: Spacing.md) {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .font(.system(size: pillTextSize, weight: .semibold, design: .rounded))
                .foregroundStyle(UltrafinColors.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(LibrarySort.allCases) { sortPill($0) }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func sortPill(_ option: LibrarySort) -> some View {
        let active = sort == option
        return Button {
            withAnimation(.smooth(duration: 0.3)) { sort = option }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: option.icon)
                    .font(.system(size: pillIconSize, weight: .semibold))
                Text(option.label)
                    .font(.system(size: pillTextSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? .white : UltrafinColors.primaryText)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background {
                if active {
                    Capsule().fill(settings.theme.accent.color.gradient)
                    Capsule().fill(LiquidGlass.sheen)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(LiquidGlass.sheen)
                }
            }
            .overlay(Capsule().strokeBorder(active ? LiquidGlass.rim(0.6) : LiquidGlass.rim(0.4), lineWidth: 1))
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: false))
        .accessibilityLabel("Sort by \(option.label)")
    }

    private var pillIconSize: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }
    private var pillTextSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
}
