import SwiftUI

/// Settings hub. Everything here writes through `SettingsStore`, so changes to
/// accent, appearance, motion, and playback engine apply across the app live.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance.mode) {
                    ForEach(AppearancePreferences.Mode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Card size", selection: $settings.appearance.cardDensity) {
                    ForEach(CardDensity.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Rich motion & parallax", isOn: $settings.appearance.richMotion)

                accentPicker
            }

            Section {
                NavigationLink {
                    HomeLayoutEditorView()
                } label: {
                    Label("Home Layout", systemImage: "rectangle.3.group")
                }
            } header: {
                Text("Home")
            } footer: {
                Text("Reorder and show/hide the rows on your Home screen.")
            }

            Section("Playback") {
                Picker("Player engine", selection: $settings.playback.enginePolicy) {
                    ForEach(PlaybackPreferences.EnginePolicy.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Auto-resume", isOn: $settings.playback.autoResume)
                // Pickers (not Steppers) so the control works on tvOS too.
                Picker("Skip interval", selection: $settings.playback.seekInterval) {
                    ForEach([5, 10, 15, 30, 45, 60], id: \.self) { Text("\($0)s").tag($0) }
                }
                Picker("Max buffer", selection: $settings.playback.maxBufferSeconds) {
                    ForEach([10, 30, 60, 90, 120], id: \.self) { Text("\($0)s").tag($0) }
                }
            }

            Section("Account") {
                if case .authenticated(let session) = appState.phase {
                    LabeledContent("Signed in as", value: session.username)
                    LabeledContent("Server", value: session.server.name)
                    if let version = session.server.version {
                        LabeledContent("Server version", value: version)
                    }
                }
                Button(role: .destructive) {
                    appState.signOut()
                } label: {
                    Text("Sign Out")
                }
            }

            Section {
                LabeledContent("Ultrafin", value: "1.0.0")
                LabeledContent("Playback core", value: VLCPlaybackEngine.isAvailable ? "AVFoundation + VLCKit" : "AVFoundation")
            } header: {
                Text("About")
            } footer: {
                Text("Ultrafin is a Jellyfin client. Jellyfin and the Swiftfin media core are open source.")
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden) // unavailable on tvOS
        #endif
        .background(UltrafinColors.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .tint(settings.theme.accent.color)
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Accent")
                .font(Typography.caption)
                .foregroundStyle(UltrafinColors.secondaryText)
            HStack(spacing: Spacing.md) {
                ForEach(AccentColor.allCases) { accent in
                    Circle()
                        .fill(accent.color)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle().strokeBorder(.white, lineWidth: settings.theme.accent == accent ? 3 : 0)
                        )
                        .scaleEffect(settings.theme.accent == accent ? 1.1 : 1)
                        .onTapGesture {
                            withAnimation(.smooth) { settings.theme.accent = accent }
                        }
                        .accessibilityLabel(accent.displayName)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
