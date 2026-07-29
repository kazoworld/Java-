import SwiftUI

/// Music mode's own settings hub. Deliberately separate from the media Settings
/// tab: only what a listening session cares about, so the two experiences never
/// share a settings screen.
struct MusicSettingsRootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                NavigationLink { MusicSettingsView() } label: {
                    SettingsRowLabel(title: "Source", subtitle: sourceSubtitle,
                                     systemImage: "server.rack", tint: .green)
                }
                NavigationLink { MusicIdentityView() } label: {
                    SettingsRowLabel(title: "Music Identity", subtitle: "How you listen",
                                     systemImage: "waveform", tint: .purple)
                }
                #if os(iOS)
                // Offline storage only makes sense where the device leaves the
                // network — the TV never does.
                NavigationLink { MusicStorageSettingsView() } label: {
                    SettingsRowLabel(title: "Downloads & Storage", subtitle: storageSubtitle,
                                     systemImage: "arrow.down.circle.fill", tint: .blue)
                }
                #endif
            } header: {
                Text("Your library, your way.")
                    .font(.system(size: sloganSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(settings.theme.accent.color)
                    .textCase(nil)
            }

            Section {
                NavigationLink { AudioSettingsView() } label: {
                    SettingsRowLabel(title: "Audio", subtitle: "Enhancements and output",
                                     systemImage: "speaker.wave.3.fill", tint: .orange)
                }
                NavigationLink { AppearanceSettingsView() } label: {
                    SettingsRowLabel(title: "Appearance", subtitle: "Theme, accent, display",
                                     systemImage: "paintbrush.fill", tint: .pink)
                }
                NavigationLink { StartupSettingsView() } label: {
                    SettingsRowLabel(title: "Startup", subtitle: StartupPreference.current.label,
                                     systemImage: "arrow.triangle.2.circlepath", tint: .blue)
                }
            } header: {
                Text("Playback & Look")
            }

            Section {
                NavigationLink { AccountSettingsView() } label: {
                    SettingsRowLabel(title: "Account", subtitle: "Server and sign out",
                                     systemImage: "person.crop.circle.fill", tint: .teal)
                }
                NavigationLink { LegalView() } label: {
                    SettingsRowLabel(title: "Legal", subtitle: "Open source, attribution, disclaimer",
                                     systemImage: "doc.text.fill", tint: .gray)
                }
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Music Settings")
        .tint(settings.theme.accent.color)
    }

    private var sourceSubtitle: String {
        settings.musicSource == .navidrome ? "Navidrome" : "Jellyfin"
    }

    #if os(iOS)
    private var storageSubtitle: String {
        let store = MusicLibraryCache.shared
        guard store.totalBytes > 0 else { return "Nothing stored yet" }
        return "\(StorageFormat.string(store.totalBytes)) on device"
    }
    #endif

    private var sloganSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
}
