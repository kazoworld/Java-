import SwiftUI

/// Audio enhancements and output preferences.
struct AudioSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Loudness normalization", isOn: $settings.audio.loudnessNormalization)
                Picker("Dialogue enhancement", selection: $settings.audio.dialogueEnhancement) {
                    ForEach(AudioPreferences.DialogueEnhancement.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Enhancements")
            } footer: {
                Text("Even out loud and quiet scenes, and boost dialogue clarity — like Sonos Speech Enhancement.")
            }

            Section {
                Toggle("Play in English by default", isOn: Binding(
                    get: { settings.preferEnglishAudio },
                    set: { settings.preferEnglishAudio = $0 }
                ))
                Toggle("Surround passthrough", isOn: $settings.audio.passthrough)
                Picker("Preferred language", selection: $settings.audio.preferredLanguage) {
                    ForEach(MediaLanguage.options, id: \.code) { Text($0.label).tag($0.code) }
                }
            } header: {
                Text("Output")
            } footer: {
                Text("Auto-select an English audio track when a title has one. Set a specific Preferred language to override, or pass Dolby/DTS straight to your receiver.")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Audio")
        .tint(settings.theme.accent.color)
    }
}
