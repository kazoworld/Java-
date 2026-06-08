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

            Section("Accent") {
                accentPicker
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Appearance")
        .tint(settings.theme.accent.color)
    }

    private var accentPicker: some View {
        HStack(spacing: Spacing.md) {
            ForEach(AccentColor.allCases) { accent in
                Button {
                    withAnimation(.smooth) { settings.theme.accent = accent }
                } label: {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle().strokeBorder(UltrafinColors.primaryText,
                                                  lineWidth: settings.theme.accent == accent ? 3 : 0)
                        )
                        .scaleEffect(settings.theme.accent == accent ? 1.12 : 1)
                }
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.18, lift: false))
                .accessibilityLabel(accent.displayName)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
