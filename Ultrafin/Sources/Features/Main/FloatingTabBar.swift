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

    private var accent: Color { settings.theme.accent.color }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 0) {
                ForEach(items) { item in tab(item) }
            }
            .padding(railPadding)
            .glassCapsule(dim: 0.14)

            switcher
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
                    .font(.system(size: 19, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold))
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
                    Capsule()
                        .fill(accent.opacity(0.16))
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
            .glassCircle(dim: 0.14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to \(switchTitle)")
    }

    private var railPadding: CGFloat { 5 }
    /// Matched to the tab pill's height so the two read as one row.
    private var switcherSide: CGFloat { 58 }
}
#endif
