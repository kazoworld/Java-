import SwiftUI

/// Type scale built on the system font with rounded design for a soft, modern
/// feel. Using semantic names keeps screens from hard-coding sizes.
enum Typography {
    static var displayTitle: Font { .system(size: 34, weight: .bold, design: .rounded) }
    static var sectionTitle: Font { .system(size: 22, weight: .semibold, design: .rounded) }
    static var cardTitle: Font { .system(size: 15, weight: .semibold, design: .rounded) }
    static var body: Font { .system(size: 16, weight: .regular) }
    static var caption: Font { .system(size: 13, weight: .medium) }
    static var monoTimecode: Font { .system(size: 13, weight: .medium, design: .monospaced) }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// Standard corner radius for cards and sheets.
    static let cornerRadius: CGFloat = 16
    static let posterCornerRadius: CGFloat = 12
}
