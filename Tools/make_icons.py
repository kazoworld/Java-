#!/usr/bin/env python3
"""Generate every Ultrafin icon asset from one square source image.

The source is the artwork as designed: a soft four-corner gradient with a
waveform-and-play mark at its centre. Everything else — the iOS icon, the tvOS
layered icon, the top shelf art, the launch mark — is derived from it here so
the family can never drift apart.

Two things need care and are why this is a script rather than a manual export:

*Corners.* Design tools hand back the icon with the rounded mask already baked
in and black outside it. iOS applies its own mask, so a baked one shows as dark
corners on the Home Screen. The gradient is extended into that dead area by
normalized convolution — a blur of the valid pixels divided by a blur of the
mask — which grows the existing colour outward instead of inventing any.

*Separation.* tvOS wants the icon as parallax layers, so the mark has to come
away from its background. It's recovered by comparing the art against a heavily
blurred copy of itself: what stands proud of its own local background is the
mark. The measurements that fall out of that (below) then let it be redrawn
crisply at any size rather than upscaled.

Usage:  python3 Tools/make_icons.py <source.png>
"""

import sys
import pathlib

from PIL import Image, ImageDraw, ImageFilter

try:
    import numpy as np
except ImportError:
    sys.exit("needs numpy and pillow:  pip install numpy pillow")

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Ultrafin/Resources/Assets.xcassets"
BRAND = ASSETS / "App Icon & Top Shelf Image.brandassets"

# The mark, measured off the source as fractions of its side. Bars are rounded
# capsules on a shared centre line; the play triangle points right with its
# corners rounded.
BARS = [  # (centre x, height)
    (0.2364, 0.1084),
    (0.2955, 0.2233),
    (0.3557, 0.3413),
    (0.4163, 0.1882),
]
BAR_WIDTH = 0.0325
BAR_CENTRE_Y = 0.4940
TRI_X0, TRI_X1 = 0.4681, 0.7409
TRI_Y0, TRI_Y1 = 0.3222, 0.6834
TRI_RADIUS = 0.030


def full_bleed(src: Image.Image) -> Image.Image:
    """The artwork with its gradient grown out into the masked-off corners."""
    a = np.asarray(src.convert("RGB")).astype(np.float32)
    valid = a.mean(axis=2) > 30
    if valid.all():
        return src.convert("RGB")

    radius = max(src.size) * 0.07
    mask = Image.fromarray((valid * 255).astype(np.uint8))
    # Pull the mask well in before growing anything. Two things live in that
    # outer ring and both leave a ghost of the old corner arc: the mask's own
    # anti-aliased edge, darkened against the black, and the artwork's inner rim
    # highlight, which is brighter than the gradient around it. Erode past both.
    inset = max(1, round(max(src.size) * 0.025 / 4))
    for _ in range(inset):
        mask = mask.filter(ImageFilter.MinFilter(9))  # 4px a pass
    valid = np.asarray(mask).astype(bool)
    kept = Image.fromarray((a * valid[..., None]).astype(np.uint8))
    weight = np.asarray(mask.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255
    colour = np.asarray(kept.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32)
    grown = colour / np.clip(weight, 1e-3, None)[..., None]
    out = np.where(valid[..., None], a, grown)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def corner_colours(art: Image.Image) -> dict:
    """The gradient's four corners, read well inside the mark's reach."""
    rgb = art.convert("RGB")
    w, h = rgb.size

    def patch(fx, fy):
        x, y = int(w * fx), int(h * fy)
        box = rgb.crop((max(0, x - 30), max(0, y - 30), min(w, x + 30), min(h, y + 30)))
        return tuple(int(v) for v in np.asarray(box).reshape(-1, 3).mean(axis=0))

    return {"tl": patch(0.06, 0.06), "tr": patch(0.94, 0.06),
            "bl": patch(0.06, 0.94), "br": patch(0.94, 0.94)}


def gradient(size, colours) -> Image.Image:
    """A bilinear four-corner wash — the icon's background at any aspect."""
    w, h = size
    tl, tr, bl, br = (np.array(colours[k], np.float32) for k in ("tl", "tr", "bl", "br"))
    fx = np.linspace(0, 1, w, dtype=np.float32)[None, :, None]
    fy = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    top = tl * (1 - fx) + tr * fx
    bottom = bl * (1 - fx) + br * fx
    return Image.fromarray(np.clip(top * (1 - fy) + bottom * fy, 0, 255).astype(np.uint8))


def mark(size: int, alpha: int = 235) -> Image.Image:
    """The waveform-and-play mark, drawn white on transparency at `size`²."""
    ss = 4  # supersample; the capsule caps and the triangle's tip need it
    n = size * ss
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    white = (255, 255, 255, alpha)

    half_w = BAR_WIDTH * n / 2
    for cx, height in BARS:
        x, half_h = cx * n, height * n / 2
        cy = BAR_CENTRE_Y * n
        d.rounded_rectangle([x - half_w, cy - half_h, x + half_w, cy + half_h],
                            radius=half_w, fill=white)

    x0, x1 = TRI_X0 * n, TRI_X1 * n
    y0, y1 = TRI_Y0 * n, TRI_Y1 * n
    tip = ((x0, y0), (x1, (y0 + y1) / 2), (x0, y1))
    d.polygon(tip, fill=white)
    # Round the three corners by stroking the outline with a thick round join.
    d.line(tip + (tip[0],), fill=white, width=int(TRI_RADIUS * n * 2), joint="curve")
    for px, py in tip:
        r = TRI_RADIUS * n
        d.ellipse([px - r, py - r, px + r, py + r], fill=white)

    return layer.resize((size, size), Image.LANCZOS)


def marked(size, colours, mark_scale: float) -> Image.Image:
    """Gradient at `size` with the mark centred on it at `mark_scale` of height."""
    w, h = size
    canvas = gradient(size, colours).convert("RGBA")
    side = int(min(w, h) * mark_scale)
    glyph = mark(side)
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow.paste(glyph, ((w - side) // 2, (h - side) // 2), glyph)
    shadow = shadow.filter(ImageFilter.GaussianBlur(side * 0.012))
    canvas.alpha_composite(Image.new("RGBA", (w, h), (0, 0, 0, 0)))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(glyph, ((w - side) // 2, (h - side) // 2))
    return canvas.convert("RGB")


def write(img: Image.Image, path: pathlib.Path, rgb: bool = True):
    path.parent.mkdir(parents=True, exist_ok=True)
    (img.convert("RGB") if rgb else img).save(path)
    print(f"  {path.relative_to(ROOT)}  {img.size[0]}×{img.size[1]}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    art = full_bleed(Image.open(sys.argv[1]))
    colours = corner_colours(art)
    print("corners:", colours)

    print("iOS app icon")
    # No alpha: the App Store rejects an icon with a channel it can't flatten.
    write(art.resize((1024, 1024), Image.LANCZOS), ASSETS / "AppIcon.appiconset/icon-1024.png")

    print("launch mark")
    for scale, px in ((1, 256), (2, 512), (3, 768)):
        suffix = "" if scale == 1 else f"@{scale}x"
        write(art.resize((px, px), Image.LANCZOS),
              ASSETS / f"LaunchMark.imageset/launchmark{suffix}.png")

    print("tvOS layered icon")
    for scale, (w, h) in ((1, (400, 240)), (2, (800, 480))):
        write(gradient((w, h), colours),
              BRAND / f"App Icon.imagestack/Back.imagestacklayer/Content.imageset/back@{scale}x.png")
        # The mark rides on the front layer, which is what gives the icon its
        # parallax when the remote moves over it.
        side = int(h * 0.62)
        front = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        # Opaque here: the front layer floats above the gradient rather than
        # sitting in it, so it wants to read as solid.
        glyph = mark(side, alpha=255)
        front.paste(glyph, ((w - side) // 2, (h - side) // 2), glyph)
        write(front,
              BRAND / f"App Icon.imagestack/Front.imagestacklayer/Content.imageset/front@{scale}x.png",
              rgb=False)

    print("top shelf")
    for scale in (1, 2):
        write(marked((1920 * scale, 720 * scale), colours, 0.42),
              BRAND / f"Top Shelf Image.imageset/topshelf@{scale}x.png")
        write(marked((2320 * scale, 720 * scale), colours, 0.42),
              BRAND / f"Top Shelf Image Wide.imageset/topshelf-wide@{scale}x.png")


if __name__ == "__main__":
    main()
