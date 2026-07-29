import SwiftUI

/// Settings → Startup: what the app opens into. Mirrors the "Start here every
/// time" toggle on the vibe screen, so a default set there can be changed or
/// cleared without hunting.
struct StartupSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var preference = StartupPreference.current

    var body: some View {
        Form {
            Section {
                row(.ask, title: "Ask every time",
                    subtitle: "Show \"What's the vibe?\" on each launch",
                    icon: "questionmark.circle.fill", tint: .gray)
                row(.launch(.media), title: "Media",
                    subtitle: "Go straight to movies and shows",
                    icon: "film.stack.fill", tint: .blue)
                row(.launch(.music), title: "Music",
                    subtitle: "Go straight to albums and playlists",
                    icon: "music.note", tint: .pink)
            } header: {
                Text("Open at launch")
            } footer: {
                Text("Whichever you pick, the switcher in the tab bar still moves between Media and Music anytime.")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(AmbientBackground())
        .navigationTitle("Startup")
        .tvPopsOnMenu()
        .tint(settings.theme.accent.color)
        .animation(.smooth(duration: 0.25), value: preference)
    }

    private func row(_ value: StartupPreference, title: String, subtitle: String,
                     icon: String, tint: Color) -> some View {
        Button {
            Haptics.play(.selection)
            preference = value
            StartupPreference.set(value)
        } label: {
            HStack(spacing: Spacing.md) {
                SettingsRowLabel(title: title, subtitle: subtitle,
                                 systemImage: icon, tint: tint)
                Spacer(minLength: Spacing.sm)
                if preference == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: checkSize, weight: .bold))
                        .foregroundStyle(settings.theme.accent.color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var checkSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
}
