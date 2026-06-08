import SwiftUI

/// Player engine policy and playback behavior.
struct PlaybackSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Player engine", selection: $settings.playback.enginePolicy) {
                    ForEach(PlaybackPreferences.EnginePolicy.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("Hybrid uses AVPlayer for the smoothest path and falls back to VLCKit for formats it can't decode.")
            }

            Section {
                Toggle("Auto-resume", isOn: $settings.playback.autoResume)
                Picker("Skip interval", selection: $settings.playback.seekInterval) {
                    ForEach([5, 10, 15, 30, 45, 60], id: \.self) { Text("\($0)s").tag($0) }
                }
                Picker("Max buffer", selection: $settings.playback.maxBufferSeconds) {
                    ForEach([10, 30, 60, 90, 120], id: \.self) { Text("\($0)s").tag($0) }
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
