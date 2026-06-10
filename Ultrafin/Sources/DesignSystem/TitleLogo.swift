import SwiftUI

/// Shows a title's **logo artwork** when the server has it (from TMDb/Fanart),
/// falling back to styled text. Logos are transparent so they sit over hero
/// artwork like Netflix/Apple TV.
struct TitleLogo: View {
    let logoURL: URL?
    let title: String
    var fallbackFont: Font
    var fallbackColor: Color = .white
    var maxWidth: CGFloat = 560
    var maxHeight: CGFloat = 120
    var alignment: Alignment = .bottomLeading

    var body: some View {
        if let logoURL {
            AsyncImage(url: logoURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment)
        } else {
            Text(title)
                .font(fallbackFont)
                .foregroundStyle(fallbackColor)
                .lineLimit(2)
        }
    }
}

extension MediaItem {
    /// True when the server has a logo image for this item.
    var hasLogo: Bool { imageTags?["Logo"] != nil }
}
