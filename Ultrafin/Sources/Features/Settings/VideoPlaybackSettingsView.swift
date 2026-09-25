import SwiftUI

/// Engine, quality, HDR, and core playback behavior.
struct VideoPlaybackSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Player engine", selection: $settings.playback.enginePolicy) {
                    ForEach(PlaybackPreferences.EnginePolicy.allCases) { Text($0.label).tag($0) }
                }
                Picker("Default quality", selection: $settings.video.defaultQuality) {
                    ForEach(QualityOption.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Engine & Quality")
            } footer: {
                Text("Hybrid uses AVPlayer for the smoothest path and falls back to VLCKit for formats it can't decode. “4K · Highest” streams the best available.")
            }

            Section {
                Toggle("HDR & Dolby Vision", isOn: $settings.video.allowHDR)
                Toggle("Match content frame rate & range", isOn: $settings.video.matchContent)
            } header: {
                Text("Video")
            } footer: {
                Text("Pass through HDR10/Dolby Vision and match your TV to the show when supported.")
            }

            Section {
                Toggle("Auto-resume", isOn: $settings.playback.autoResume)
                Toggle("Autoplay next episode", isOn: $settings.autoplayNextEpisode)
                Picker("Skip interval", selection: $settings.playback.seekInterval) {
                    ForEach([5, 10, 15, 30, 45, 60], id: \.self) { Text("\($0)s").tag($0) }
                }
                Picker("Max buffer", selection: $settings.playback.maxBufferSeconds) {
                    ForEach([10, 30, 60, 90, 120], id: \.self) { Text("\($0)s").tag($0) }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("With autoplay off, the Up Next card still appears over the credits but waits for you to press it.")
            }

            Section {
                Toggle("Theater mode", isOn: $settings.theaterMode)
                Toggle("Theme music", isOn: $settings.themeMusic)
            } header: {
                Text("Detail Pages")
            } footer: {
                Text("Theater mode plays a muted highlight of the title behind the cover art, like a trailer; theme music plays the show's theme when your server has one. Both stay silent until you tap the volume button.")
            }

            Section {
                Toggle("Hide watched from Home", isOn: $settings.hideWatched)
            } header: {
                Text("Library")
            } footer: {
                Text("Keeps fully-watched titles out of the Recently Added and Hidden Gems rows. Favorites and Continue Watching are never filtered.")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Video")
        .tint(settings.accent)
    }
}
