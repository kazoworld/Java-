import SwiftUI

/// A row of metadata badges: ★ rating · year · rating-box · seasons/runtime.
struct DetailBadges: View {
    let item: MediaItem
    var seasonCount: Int? = nil
    /// When overlaid on a dark hero, force light text instead of adaptive colors.
    var onDark: Bool = false

    private var font: Font { .system(size: size, weight: .semibold, design: .rounded) }
    private var primary: Color { onDark ? .white : UltrafinColors.primaryText }
    private var secondary: Color { onDark ? .white.opacity(0.85) : UltrafinColors.secondaryText }
    private var tertiary: Color { onDark ? .white.opacity(0.55) : UltrafinColors.tertiaryText }
    private var separator: Color { onDark ? .white.opacity(0.45) : UltrafinColors.separator }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let rt = item.criticScoreText {
                HStack(spacing: 3) {
                    Text("🍅")
                    Text(rt).foregroundStyle(item.isFresh ? Color(hex: 0xFA5A3C) : secondary)
                }
                .font(font)
            }
            if let community = item.communityRating {
                if item.criticScoreText != nil { dot() }
                Text(String(format: "★ %.1f", community))
                    .font(font).foregroundStyle(primary)
            }
            if let year = item.productionYear { dot(); badge(String(year)) }
            if let rating = item.officialRating {
                dot()
                Text(rating)
                    .font(font)
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(separator, lineWidth: 1))
            }
            if let seasonCount, seasonCount > 0 {
                dot(); badge("\(seasonCount) Season\(seasonCount == 1 ? "" : "s")")
            } else if let runtime = item.runtimeText {
                dot(); badge(runtime)
            }
        }
        .shadow(color: onDark ? .black.opacity(0.5) : .clear, radius: 5, y: 2)
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(font).foregroundStyle(secondary)
    }
    private func dot() -> some View {
        Circle().fill(tertiary).frame(width: 4, height: 4)
    }

    private var size: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }
}

/// A focusable icon-over-label action (My List, Watched, …).
struct DetailActionButton: View {
    let title: String
    let systemImage: String
    var active: Bool = false
    /// When overlaid on a dark hero, force light text instead of adaptive colors.
    var onDark: Bool = false
    let action: () -> Void

    @Environment(SettingsStore.self) private var settings

    private var iconColor: Color {
        if active { return settings.theme.accent.color }
        return onDark ? .white : UltrafinColors.primaryText
    }
    private var labelColor: Color { onDark ? .white.opacity(0.85) : UltrafinColors.secondaryText }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundStyle(labelColor)
            }
            .shadow(color: onDark ? .black.opacity(0.45) : .clear, radius: 4, y: 2)
            .frame(minWidth: minWidth)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.12, lift: false))
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        30
        #else
        20
        #endif
    }
    private var labelSize: CGFloat {
        #if os(tvOS)
        18
        #else
        12
        #endif
    }
    private var minWidth: CGFloat {
        #if os(tvOS)
        110
        #else
        72
        #endif
    }
}

/// Cast and director/creator lines.
struct CastCrewView: View {
    let item: MediaItem
    var onDark: Bool = false

    private var labelColor: Color { onDark ? .white.opacity(0.6) : UltrafinColors.tertiaryText }
    private var valueColor: Color { onDark ? .white.opacity(0.85) : UltrafinColors.secondaryText }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let cast = item.castText { line(label: "Cast", value: cast) }
            if let crew = item.crewLine { line(label: crew.label, value: crew.name) }
        }
    }

    private func line(label: String, value: String) -> some View {
        (Text(label + ": ").foregroundStyle(labelColor)
            + Text(value).foregroundStyle(valueColor))
            .font(.system(size: size))
            .lineLimit(1)
    }

    private var size: CGFloat {
        #if os(tvOS)
        20
        #else
        13
        #endif
    }
}

/// A focusable underlined tab selector (Episodes / More Like This / …).
struct DetailTabBar: View {
    let tabs: [String]
    @Binding var selection: Int

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: Spacing.xl) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
                Button { selection = idx } label: {
                    VStack(spacing: 6) {
                        Text(tab)
                            .font(.system(size: size, weight: .semibold, design: .rounded))
                            .foregroundStyle(idx == selection ? UltrafinColors.primaryText : UltrafinColors.tertiaryText)
                        Capsule()
                            .fill(idx == selection ? settings.theme.accent.color : .clear)
                            .frame(height: 3)
                    }
                    .fixedSize()
                }
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: false))
            }
            Spacer()
        }
    }

    private var size: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
}
