#!/usr/bin/env python3
"""App icons (PWA + Android launcher): amber lightning bolt on the night
purple rounded square used by the site favicon. Run once; output is committed."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
NIGHT, VIOLET, AMBER = (26, 15, 51), (59, 31, 122), (255, 177, 59)
BOLT = [(18.6, 4), (8, 18.2), (14.6, 18.2), (12.4, 28), (24, 12.9), (17.1, 12.9)]   # 32x32 favicon path


def icon(size: int, *, maskable: bool = False, rounded: bool = True) -> Image.Image:
    big = size * 4
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if maskable:
        d.rectangle([0, 0, big, big], fill=VIOLET)
        scale, off = big * 0.62 / 32, big * 0.19        # keep inside the safe zone
    else:
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * (0.28 if rounded else 0)), fill=VIOLET)
        scale, off = big / 32, 0
    for i in range(12, 0, -1):                          # soft glow behind the bolt
        r = big * 0.36 * i / 12
        c = big / 2
        d.ellipse([c - r, c - r, c + r, c + r], fill=(139, 92, 246, int(8 * (13 - i) / 12)))
    d.polygon([(x * scale + off, y * scale + off) for x, y in BOLT], fill=AMBER)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    out = ROOT / "app" / "icons"
    out.mkdir(parents=True, exist_ok=True)
    icon(192).save(out / "icon-192.png")
    icon(512).save(out / "icon-512.png")
    icon(512, maskable=True).save(out / "maskable-512.png")
    flat = Image.new("RGB", (180, 180), VIOLET)
    ic = icon(180, rounded=False)
    flat.paste(ic, (0, 0), ic)
    flat.save(out / "apple-touch-icon.png")
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for name, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        folder = res / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        icon(px).save(folder / "ic_launcher.png")
        icon(px, rounded=True).save(folder / "ic_launcher_round.png")
    print("icons written")


if __name__ == "__main__":
    main()
