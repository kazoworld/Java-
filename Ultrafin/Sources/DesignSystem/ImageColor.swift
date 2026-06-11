import SwiftUI
#if canImport(UIKit)
import UIKit
import CoreImage
#endif

/// A color sampled from artwork, plus whether it's dark enough to need white
/// text on top.
struct ArtworkColor: Equatable {
    let color: Color
    let isDark: Bool
}

/// Extracts a vivid representative color from a remote image so UI (like the
/// media bar) can be tinted by the *content* rather than the app's theme.
enum ImageColor {
    static func vibrant(from url: URL?) async -> ArtworkColor? {
        #if canImport(UIKit)
        guard let url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let cg = image.cgImage
        else { return nil }

        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci,
                                                 kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let output = filter.outputImage
        else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)

        let r = CGFloat(bitmap[0]) / 255
        let g = CGFloat(bitmap[1]) / 255
        let b = CGFloat(bitmap[2]) / 255

        // Boost into something vivid and pleasant for accents.
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        let vivid = UIColor(hue: h,
                            saturation: min(1, max(s, 0.55)),
                            brightness: min(0.9, max(br, 0.6)),
                            alpha: 1)

        // Luminance of the vivid color → readable text color when used as a fill.
        var vr: CGFloat = 0, vg: CGFloat = 0, vb: CGFloat = 0, va: CGFloat = 0
        vivid.getRed(&vr, green: &vg, blue: &vb, alpha: &va)
        let luminance = 0.2126 * vr + 0.7152 * vg + 0.0722 * vb

        return ArtworkColor(color: Color(vivid), isDark: luminance < 0.6)
        #else
        return nil
        #endif
    }
}
