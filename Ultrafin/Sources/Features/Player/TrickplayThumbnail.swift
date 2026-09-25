import SwiftUI
import UIKit

/// A single scrubber-preview frame for a playback time, cropped out of the
/// Jellyfin trickplay sprite sheet. The sprite tile is loaded (and cached) once;
/// moving within the same tile just re-crops, so scrubbing stays smooth.
struct TrickplayThumbnail: View {
    let source: TrickplaySource
    let time: Double
    var width: CGFloat = 220

    @State private var tile: UIImage?

    private var height: CGFloat { (width / source.aspect).rounded() }

    var body: some View {
        ZStack {
            if let image = cropped {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.black
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(.white.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        .task(id: source.tileURL(for: time)) { await loadTile() }
    }

    /// The current tile cropped down to just the thumbnail for `time`.
    private var cropped: UIImage? {
        guard let tile, let cg = tile.cgImage else { return nil }
        let rect = source.cropRect(for: time)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1,
              let cropped = cg.cropping(to: rect) else { return tile }
        return UIImage(cgImage: cropped)
    }

    private func loadTile() async {
        guard let url = source.tileURL(for: time) else { return }
        tile = await ImageLoader.shared.image(for: url)
    }
}
