import SwiftUI

/// Editor for the Home row order and visibility.
///
/// Uses a custom focusable layout (plain VStack of buttons, not a `List`) so
/// every control — move up, move down, show/hide — is independently reachable
/// with the Siri Remote on tvOS, where multiple controls inside a list row
/// would collapse into a single focus target.
struct HomeLayoutEditorView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                ForEach(Array(settings.homeLayout.rows.enumerated()), id: \.element.kind) { index, config in
                    rowEditor(index: index, config: config)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AmbientBackground())
        .navigationTitle("Home Layout")
    }

    private func rowEditor(index: Int, config: HomeRowConfig) -> some View {
        let count = settings.homeLayout.rows.count
        return HStack(spacing: Spacing.md) {
            Image(systemName: config.kind.systemImage)
                .foregroundStyle(config.isEnabled ? settings.theme.accent.color : UltrafinColors.tertiaryText)
                .frame(width: 32)
            Text(config.kind.title)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(config.isEnabled ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
            Spacer()
            iconButton("chevron.up", enabled: index > 0) {
                settings.moveHomeRow(config.kind, up: true)
            }
            iconButton("chevron.down", enabled: index < count - 1) {
                settings.moveHomeRow(config.kind, up: false)
            }
            iconButton(config.isEnabled ? "eye.fill" : "eye.slash", enabled: true) {
                toggle(config.kind)
            }
        }
        .padding(Spacing.md)
        .glassCard()
    }

    private func iconButton(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .foregroundStyle(enabled ? UltrafinColors.primaryText : UltrafinColors.tertiaryText)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.12, lift: false))
        .disabled(!enabled)
    }

    private func toggle(_ kind: HomeRowKind) {
        guard let i = settings.homeLayout.rows.firstIndex(where: { $0.kind == kind }) else { return }
        settings.homeLayout.rows[i].isEnabled.toggle()
    }
}
