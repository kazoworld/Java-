import SwiftUI

/// Theme, card sizing, motion, and accent.
struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Theme", selection: $settings.appearance.mode) {
                    ForEach(AppearancePreferences.Mode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Card size", selection: $settings.appearance.cardDensity) {
                    ForEach(CardDensity.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Rich motion & parallax", isOn: $settings.appearance.richMotion)
            }

            Section {
                Toggle("OLED mode", isOn: $settings.appearance.oledMode)
                Toggle("Ambient background", isOn: $settings.appearance.ambientBackground)
                    .disabled(settings.appearance.oledMode)
            } header: {
                Text("Display")
            } footer: {
                Text("OLED mode uses true black for deeper contrast and lower power. Turn off the ambient background to reduce on-screen effects.")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Appearance")
        .tint(settings.theme.accent.color)
    }

}
