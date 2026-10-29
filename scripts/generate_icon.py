#!/usr/bin/env python3
"""Draw the Fix-it Lens app icon and logo locally with Pillow (no model, no third-party art).

A camera-lens ring around a hex nut, with a teal SAM-style segmentation contour hugging the nut
and an amber focus tick. Output: AppIcon.png (1024, opaque) and Logo.png (512).
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "samdevna" / "Assets.xcassets"
S = 4096  # supersampled canvas
C = S / 2

NIGHT = (6, 7, 10)
NIGHT_RAISED = (20, 23, 31)
AMBER = (255, 176, 32)
AMBER_DEEP = (214, 128, 0)
TEAL = (52, 209, 176)


def radial_background() -> Image.Image:
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            d = math.hypot(x - 128, y - 110) / 181
            t = max(0.0, min(1.0, d))
            px[x, y] = tuple(int(NIGHT_RAISED[i] * (1 - t) + NIGHT[i] * t) for i in range(3))
    return small.resize((S, S), Image.BICUBIC)


def hexagon(r: float, rot: float = 0.0) -> list[tuple[float, float]]:
    return [(C + r * math.cos(rot + k * math.pi / 3), C + r * math.sin(rot + k * math.pi / 3)) for k in range(6)]


def main() -> None:
    img = radial_background()

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([C - 1500, C - 1500, C + 1500, C + 1500], outline=AMBER + (150,), width=260)
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img.paste(glow, (0, 0), glow)

    d = ImageDraw.Draw(img)
    # Lens ring: outer amber, thin inner bezel.
    d.ellipse([C - 1480, C - 1480, C + 1480, C + 1480], outline=AMBER, width=190)
    d.ellipse([C - 1210, C - 1210, C + 1210, C + 1210], outline=(46, 52, 66), width=40)
    # Aperture tick marks.
    for k in range(24):
        a = k * math.tau / 24
        r1, r2 = 1250, 1330 if k % 2 else 1370
        d.line([(C + r1 * math.cos(a), C + r1 * math.sin(a)), (C + r2 * math.cos(a), C + r2 * math.sin(a))],
               fill=(70, 78, 96), width=30)

    # Hex nut with a round bore.
    rot = math.pi / 6
    d.polygon(hexagon(820, rot), fill=(34, 38, 48))
    d.polygon(hexagon(820, rot), outline=(120, 128, 146), width=46)
    d.polygon(hexagon(640, rot), outline=(58, 64, 80), width=22)
    d.ellipse([C - 360, C - 360, C + 360, C + 360], fill=NIGHT)
    d.ellipse([C - 360, C - 360, C + 360, C + 360], outline=(96, 104, 122), width=36)

    # SAM-style segmentation contour: teal, slightly outside the nut, with a translucent fill.
    mask = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    md = ImageDraw.Draw(mask)
    md.polygon(hexagon(900, rot), fill=TEAL + (46,))
    pts = hexagon(900, rot)
    md.line(pts + [pts[0]], fill=TEAL + (255,), width=64, joint="curve")
    for x, y in pts:
        md.ellipse([x - 70, y - 70, x + 70, y + 70], fill=TEAL + (255,))
    img.paste(mask, (0, 0), mask)

    # Amber focus tick at top-right of the ring.
    a = -math.pi / 4
    fx, fy = C + 1480 * math.cos(a), C + 1480 * math.sin(a)
    d.ellipse([fx - 170, fy - 170, fx + 170, fy + 170], fill=AMBER_DEEP, outline=AMBER, width=50)

    icon = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
    icon.save(ASSETS / "AppIcon.appiconset" / "AppIcon.png", optimize=True)
    icon.resize((512, 512), Image.LANCZOS).save(ASSETS / "Logo.imageset" / "Logo.png", optimize=True)
    print("wrote AppIcon.png (1024) and Logo.png (512)")


if __name__ == "__main__":
    main()
