import SwiftUI

/// Settings hub. Each row drills into a focused sub-page so the screen stays
/// tidy and every group has room to grow.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                NavigationLink { AppearanceSettingsView() } label: {
                    Label("Appearance", systemImage: "paintbrush.fill")
                }
                NavigationLink { FeaturedSettingsView() } label: {
                    Label("Media Bar", systemImage: "rectangle.on.rectangle.angled.fill")
                }
                NavigationLink { HomeLayoutEditorView() } label: {
                    Label("Home Layout", systemImage: "rectangle.3.group.fill")
                }
                NavigationLink { PlaybackSettingsView() } label: {
                    Label("Playback", systemImage: "play.rectangle.fill")
                }
            }

            Section {
                NavigationLink { AccountSettingsView() } label: {
                    Label("Account", systemImage: "person.crop.circle.fill")
                }
            }

            Section {
                LabeledContent("Ultrafin", value: "1.0.0")
                LabeledContent("Playback core",
                               value: VLCPlaybackEngine.isAvailable ? "AVFoundation + VLCKit" : "AVFoundation")
            } header: {
                Text("About")
            } footer: {
                Text("Ultrafin is a Jellyfin client. Jellyfin and the Swiftfin media core are open source.")
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Settings")
        .tint(settings.theme.accent.color)
    }
}
