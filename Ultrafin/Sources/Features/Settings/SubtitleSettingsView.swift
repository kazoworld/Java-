import SwiftUI

/// Closed-caption behavior and on-screen subtitle appearance.
struct SubtitleSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Closed captions", selection: $settings.subtitles.captionMode) {
                    ForEach(SubtitlePreferences.CaptionMode.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Closed Captions")
            } footer: {
                Text("“Off unless engaged” briefly shows captions when you skip or rewind, then hides them.")
            }

            Section {
                Picker("Text size", selection: $settings.subtitles.size) {
                    ForEach(SubtitlePreferences.Size.allCases) { Text($0.label).tag($0) }
                }
                Picker("Text color", selection: $settings.subtitles.textColor) {
                    ForEach(SubtitlePreferences.TextColor.allCases) { Text($0.label).tag($0) }
                }
                Picker("Preferred language", selection: $settings.subtitles.preferredLanguage) {
                    ForEach(MediaLanguage.options, id: \.code) { Text($0.label).tag($0.code) }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Applies to the VLCKit player; the native player uses your tvOS caption style.")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Subtitles")
        .tint(settings.theme.accent.color)
    }
}
