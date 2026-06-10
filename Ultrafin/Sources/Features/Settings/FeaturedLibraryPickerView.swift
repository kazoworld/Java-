import SwiftUI

/// Multi-select of which libraries feed the media bar. Empty selection = all.
struct FeaturedLibraryPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var libraries: [MediaItem] = []
    @State private var isLoading = true

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    var body: some View {
        Form {
            Section {
                Toggle("All libraries", isOn: Binding(
                    get: { settings.featured.sourceLibraryIDs.isEmpty },
                    set: { if $0 { settings.featured.sourceLibraryIDs = [] } }
                ))
            } footer: {
                Text("When off, choose specific libraries below.")
            }

            if isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                Section("Choose libraries") {
                    ForEach(libraries) { library in
                        Button { toggle(library.id) } label: {
                            HStack {
                                Text(library.name).foregroundStyle(UltrafinColors.primaryText)
                                Spacer()
                                if settings.featured.sourceLibraryIDs.contains(library.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(settings.theme.accent.color)
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Libraries")
        .tint(settings.theme.accent.color)
        .task { await loadLibraries() }
    }

    private func toggle(_ id: String) {
        var ids = settings.featured.sourceLibraryIDs
        if let idx = ids.firstIndex(of: id) { ids.remove(at: idx) } else { ids.append(id) }
        settings.featured.sourceLibraryIDs = ids
    }

    private func loadLibraries() async {
        guard let session, let client = appState.client else { return }
        libraries = (try? await client.userViews(userID: session.userID)) ?? []
        isLoading = false
    }
}
