import SwiftUI

/// Music → Theme. The listening side sits on a flat surface rather than the
/// media side's ambient wash: true black (the default) or pure white, or matched
/// to the device's own light/dark setting.
struct MusicThemeSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(MusicTheme.allCases) { theme in
                    row(theme)
                }
            } header: {
                Text("Background")
            } footer: {
                Text("Music screens stay a single flat colour so album artwork is the only colour on screen. Black is true #000000 — what OLED panels want.")
            }
        }
        .glassRows()
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .musicCanvas()
        .navigationTitle("Theme")
        .tvPopsOnMenu()
        .tint(settings.accent)
        .animation(.smooth(duration: 0.3), value: settings.musicTheme)
    }

    private func row(_ theme: MusicTheme) -> some View {
        Button {
            Haptics.play(.selection)
            settings.musicTheme = theme
        } label: {
            HStack(spacing: Spacing.md) {
                swatch(theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.label)
                        .foregroundStyle(UltrafinColors.primaryText)
                    Text(theme.detail)
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.secondaryText)
                }
                Spacer(minLength: Spacing.sm)
                if settings.musicTheme == theme {
                    Image(systemName: "checkmark")
                        .font(.system(size: checkSize, weight: .bold))
                        .foregroundStyle(settings.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    /// A little preview of the surface the option produces.
    @ViewBuilder
    private func swatch(_ theme: MusicTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            switch theme {
            case .black:
                shape.fill(.black)
            case .white:
                shape.fill(.white)
            case .system:
                // Half and half — it follows whatever the device is doing.
                shape.fill(LinearGradient(stops: [
                    .init(color: .black, location: 0.5),
                    .init(color: .white, location: 0.5)
                ], startPoint: .leading, endPoint: .trailing))
            }
        }
        .frame(width: swatchSide, height: swatchSide)
        .overlay(shape.strokeBorder(UltrafinColors.separator, lineWidth: 1))
    }

    private var swatchSide: CGFloat {
        #if os(tvOS)
        48
        #else
        34
        #endif
    }
    private var checkSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
}
