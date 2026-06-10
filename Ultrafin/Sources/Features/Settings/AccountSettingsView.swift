import SwiftUI

/// Signed-in account + server info, and sign out.
struct AccountSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            if case .authenticated(let session) = appState.phase {
                Section {
                    LabeledContent("Signed in as", value: session.username)
                    LabeledContent("Server", value: session.server.name)
                    if let version = session.server.version {
                        LabeledContent("Server version", value: version)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    appState.signOut()
                } label: {
                    Text("Sign Out")
                }
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Account")
        .tint(settings.theme.accent.color)
    }
}
