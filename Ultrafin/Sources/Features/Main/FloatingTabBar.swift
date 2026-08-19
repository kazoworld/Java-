import SwiftUI

#if os(iOS)
/// The app's own bottom bar on iPhone: a floating glass pill of tabs, with the
/// mode switcher riding beside it as its own circle.
///
/// It replaces the system tab bar rather than restyling it. The switcher is
/// deliberately *outside* the pill — it doesn't navigate anywhere, it swaps the
/// whole experience, and a control that changes everything shouldn't sit in the
/// same row as four that change one screen.
struct FloatingTabBar: View {
    struct Item: Identifiable {
        let tag: Int
        let title: String
        let icon: String
        var id: Int { tag }
    }

    let items: [Item]
    @Binding var selection: Int
    /// The mode the switcher offers — its label doubles as the accessibility
    /// name, since the glyph alone doesn't say which way it goes.
    let switchTitle: String
    let switchIcon: String
    let onSwitch: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Namespace private var highlight

    private var accent: Color { settings.accent }

    var body: some View {
        // One container for both pieces so the system treats them as a single
        // sheet of glass — they sample and light coherently instead of being two
        // unrelated blurs that happen to sit next to each other.
        GlassEffectContainer(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                HStack(spacing: 0) {
                    ForEach(items) { item in tab(item) }
                }
                .padding(railPadding)
                .barGlass(shape: Capsule())

                switcher
            }
        }
    }

    private func tab(_ item: Item) -> some View {
        let isSelected = selection == item.tag
        return Button {
            Haptics.play(.selection)
            // Assigned even when it hasn't changed: the binding's setter is what
            // returns a tab to its root, so re-tapping Home still goes home.
            withAnimation(.spring(duration: 0.35, bounce: 0.18)) {
                selection = item.tag
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 21, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? accent : UltrafinColors.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    // One capsule that slides between tabs rather than four that
                    // fade — the movement is what says "you went there".
                    //
                    // Neutral and light rather than a wash of accent: on glass
                    // the selected slot reads as a brighter pane with the tint
                    // left to the glyph, which is how it looks on the reference.
                    // A dim accent fill just made a slightly-less-black hole.
                    Capsule()
                        .fill(UltrafinColors.primaryText.opacity(0.14))
                        .overlay(Capsule().strokeBorder(LiquidGlass.rim(0.5), lineWidth: 0.5))
                        .matchedGeometryEffect(id: "selectedTab", in: highlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var switcher: some View {
        Button {
            onSwitch()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: switchIcon)
                    .font(.system(size: 17, weight: .semibold))
                Text(switchTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(accent)
            .frame(width: switcherSide, height: switcherSide)
            .barGlass(shape: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to \(switchTitle)")
    }

    private var railPadding: CGFloat { 6 }
    /// Matched to the tab pill's height so the two read as one row.
    private var switcherSide: CGFloat { 58 }
}
#endif
