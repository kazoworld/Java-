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

/// How a library grid is ordered. Recently Added is the default.
enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyAdded, alphabetical
    var id: String { rawValue }
    var label: String { self == .recentlyAdded ? "Recently Added" : "A–Z" }
    var icon: String { self == .recentlyAdded ? "clock.fill" : "textformat" }
    var sortBy: String { self == .recentlyAdded ? "DateCreated,SortName" : "SortName" }
    var sortOrder: String { self == .recentlyAdded ? "Descending" : "Ascending" }
}

/// Contents of a single library, rendered as an adaptive poster grid with a
/// sort control (Recently Added / A–Z).
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
        return [GridItem(.adaptive(minimum: minWidth, maximum: minWidth * 1.4), spacing: Spacing.lg)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                sortBar
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
                } else {
                    LazyVGrid(columns: columns, spacing: Spacing.lg) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item, style: .poster, fillWidth: true)
                            }
                            .mediaCardButtonStyle()
                        }
                    }
                }
            }
            .padding(Spacing.lg)
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

    /// A row of circular sort buttons, trailing-aligned, with the active one
    /// highlighted in the accent color.
    private var sortBar: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()
            ForEach(LibrarySort.allCases) { option in
                sortButton(option)
            }
        }
    }

    private func sortButton(_ option: LibrarySort) -> some View {
        let active = sort == option
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { sort = option }
        } label: {
            Image(systemName: option.icon)
                .font(.system(size: sortIconSize, weight: .semibold))
                .foregroundStyle(active ? .white : UltrafinColors.primaryText)
                .frame(width: sortDiameter, height: sortDiameter)
                .background {
                    if active {
                        Circle().fill(settings.theme.accent.color.gradient)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Circle().strokeBorder(active ? Color.clear : UltrafinColors.separator, lineWidth: 1))
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.12, lift: false))
        .accessibilityLabel("Sort by \(option.label)")
    }

    private var sortIconSize: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }
    private var sortDiameter: CGFloat {
        #if os(tvOS)
        58
        #else
        42
        #endif
    }
}
