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

            Section {
                Toggle("HDR & Dolby Vision", isOn: $settings.video.allowHDR)
                Toggle("Match content frame rate & range", isOn: $settings.video.matchContent)
            } header: {
                Text("Video")
            } footer: {
                Text("Pass through HDR10/Dolby Vision and match your TV to the show when supported.")
            }

            Section {
                Toggle("Loudness normalization", isOn: $settings.audio.loudnessNormalization)
                Picker("Dialogue enhancement", selection: $settings.audio.dialogueEnhancement) {
                    ForEach(AudioPreferences.DialogueEnhancement.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("Even out loud and quiet scenes, and boost dialogue clarity — like Sonos Speech Enhancement.")
            }

            Section {
                Picker("Closed captions", selection: $settings.subtitles.captionMode) {
                    ForEach(SubtitlePreferences.CaptionMode.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Subtitles")
            } footer: {
                Text("“Off unless engaged” briefly shows captions when you skip or rewind, then hides them.")
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
