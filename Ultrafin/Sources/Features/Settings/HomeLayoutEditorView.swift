import SwiftUI

/// Editor for the Home row order and visibility.
///
/// Uses a custom focusable layout (plain VStack of buttons, not a `List`) so
/// every control — move up, move down, show/hide — is independently reachable
/// with the Siri Remote on tvOS, where multiple controls inside a list row
/// would collapse into a single focus target.
struct HomeLayoutEditorView: View {
    @Environment(SettingsStore.self) private var settings

    /// The reorderable rows — everything except the pinned featured media bar
    /// (its visibility lives on the Media Bar page).
    private var editableRows: [HomeRowConfig] {
        settings.homeLayout.rows.filter { $0.kind != .featured && $0.kind != .comingUp }
    }

    var body: some View {
        @Bindable var settings = settings
        return ScrollView {
            VStack(spacing: Spacing.md) {
                ForEach(editableRows) { config in
                    rowEditor(config: config)
                }

                continueWatchingOrder(settings: settings)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AmbientBackground())
        .navigationTitle("Home Layout")
    }

    /// Toggle for whether Continue Watching leads with Next Up or in-progress.
    private func continueWatchingOrder(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: $settings.nextUpFirst) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Up first")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                    Text(settings.nextUpFirst
                         ? "Continue Watching leads with the next episode, then in-progress."
                         : "Continue Watching leads with in-progress, then the next episode.")
                        .font(.system(size: 13))
                        .foregroundStyle(UltrafinColors.secondaryText)
                }
            }
            .tint(settings.accent)
        }
        .padding(Spacing.md)
        .glassCard()
    }

    private func rowEditor(config: HomeRowConfig) -> some View {
        let rows = settings.homeLayout.rows
        let index = rows.firstIndex(where: { $0.kind == config.kind }) ?? 0
        let lower = rows.first?.kind == .featured ? 1 : 0
        return HStack(spacing: Spacing.md) {
            Image(systemName: config.kind.systemImage)
                .foregroundStyle(config.isEnabled ? settings.accent : UltrafinColors.tertiaryText)
                .frame(width: 32)
            Text(config.kind.title)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(config.isEnabled ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
            Spacer()
            iconButton("chevron.up", enabled: index > lower) {
                settings.moveHomeRow(config.kind, up: true)
            }
            iconButton("chevron.down", enabled: index < rows.count - 1) {
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
