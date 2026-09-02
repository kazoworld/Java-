import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A color sampled from artwork, stored as plain components so it's `Sendable`
/// and safe to hand back from a background task. `isDark` says whether white
/// text reads well when this is used as a fill.
struct ArtworkColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let isDark: Bool

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    #if canImport(UIKit)
    /// A tuned shade of this color for building gradients — scale brightness and
    /// saturation, and optionally rotate the hue. Used to spin one sampled color
    /// into the multi-tone wash behind the player, Apple Music-style.
    func shade(brightness bMul: Double = 1, saturation sMul: Double = 1, hue hShift: Double = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: red, green: green, blue: blue, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = h + CGFloat(hShift)
        hue -= floor(hue) // wrap into 0...1
        let ui = UIColor(hue: hue,
                         saturation: min(1, max(0, s * CGFloat(sMul))),
                         brightness: min(1, max(0, b * CGFloat(bMul))),
                         alpha: 1)
        return Color(ui)
    }
    #else
    func shade(brightness bMul: Double = 1, saturation sMul: Double = 1, hue hShift: Double = 0) -> Color { color }
    #endif
}

/// Extracts a vivid representative color from a remote image so UI (like the
/// media bar) can be tinted by the *content* rather than the app's theme.
///
/// Uses CoreGraphics to average the image down to a single pixel — no CoreImage
/// dependency — then boosts it into a pleasant, vivid accent.
enum ImageColor {
    static func vibrant(from url: URL?) async -> ArtworkColor? {
        #if canImport(UIKit)
        guard let url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let cg = image.cgImage
        else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = CGFloat(pixel[0]) / 255
        let g = CGFloat(pixel[1]) / 255
        let b = CGFloat(pixel[2]) / 255

        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: &al)
        let vivid = UIColor(hue: h,
                            saturation: min(1, max(s, 0.55)),
                            brightness: min(0.9, max(br, 0.6)),
                            alpha: 1)

        var vr: CGFloat = 0, vg: CGFloat = 0, vb: CGFloat = 0, va: CGFloat = 0
        vivid.getRed(&vr, green: &vg, blue: &vb, alpha: &va)
        let luminance = 0.2126 * vr + 0.7152 * vg + 0.0722 * vb

        return ArtworkColor(red: Double(vr), green: Double(vg), blue: Double(vb), isDark: luminance < 0.6)
        #else
        return nil
        #endif
    }
}
