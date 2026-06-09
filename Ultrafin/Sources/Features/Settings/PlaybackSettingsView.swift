import SwiftUI

/// Playback hub — drills into focused Video / Audio / Subtitles / Downloads
/// pages, matching the premium structure of the rest of Settings.
struct PlaybackSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                NavigationLink { VideoPlaybackSettingsView() } label: {
                    SettingsRowLabel(title: "Video", subtitle: "Engine, quality, HDR",
                                     systemImage: "play.rectangle.fill", tint: .orange)
                }
                NavigationLink { AudioSettingsView() } label: {
                    SettingsRowLabel(title: "Audio", subtitle: "Normalization, dialogue, language",
                                     systemImage: "speaker.wave.2.fill", tint: .pink)
                }
                NavigationLink { SubtitleSettingsView() } label: {
                    SettingsRowLabel(title: "Subtitles", subtitle: "Captions, size, color",
                                     systemImage: "captions.bubble.fill", tint: .blue)
                }
                NavigationLink { DownloadSettingsView() } label: {
                    SettingsRowLabel(title: "Offline Downloads", subtitle: "Quality and storage",
                                     systemImage: "arrow.down.circle.fill", tint: .green)
                }
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Playback")
        .tint(settings.theme.accent.color)
    }
}
