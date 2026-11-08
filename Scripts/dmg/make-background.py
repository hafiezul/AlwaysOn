#!/usr/bin/env python3
"""Renders the AlwaysOn installer window background.

A familiar Mac installer: title and one instruction up top, the app and the
Applications folder side by side with a trail of dots leading into a green
chevron (the status dot from the app icon), and a first-launch note below.

The committed background.png and background@2x.png are what the release build
uses, so this only needs to run when the artwork changes:

    python3 Scripts/dmg/make-background.py
    python3 Scripts/dmg/make-background.py --preview /tmp/preview.png

--preview also writes a mock with the icons and both label colours placed
where Finder puts them. Geometry comes from layout.json. Needs Pillow.
"""
import argparse
import json
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FONT = os.path.join(HERE, "fonts", "Inter.ttf")  # closest open face to SF Pro
ICON = os.path.join(REPO, "AlwaysOn/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")

with open(os.path.join(HERE, "layout.json")) as fp:
    L = json.load(fp)
W, H = L["windowWidth"], L["windowHeight"] + L["bleed"]

# Cool slate. Finder draws the icon labels itself, black in Light Mode and
# white in Dark Mode, so the label rows must stay mid-tone: both read at
# about 4.5:1 there (checked with --preview, which prints the numbers).
TOP = (129, 135, 145)
BOTTOM = (103, 109, 118)
WHITE = (255, 255, 255)
GREEN = (0, 191, 99)  # the status dot in the app icon

SS = 4  # supersampling


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([max(14, min(32, size / SS)), weight])
    return f


def text(d, center_x, baseline, s, f, fill, tracking=0.0):
    """Centred text with tracking in em; Pillow has no letter-spacing of its own."""
    em = f.size
    width = f.getlength(s) + tracking * em * (len(s) - 1)
    x = center_x - width / 2
    for i, ch in enumerate(s):
        d.text((x + f.getlength(s[:i]) + tracking * em * i, baseline), ch, font=f, fill=fill, anchor="ls")


def render(scale):
    k = scale * SS
    w, h = W * k, H * k

    # Vertical wash, lit from above: one soft light at the top centre
    column = Image.new("RGB", (1, h))
    px = column.load()
    for y in range(h):
        t = y / (h - 1)
        px[0, y] = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    img = column.resize((w, h)).convert("RGBA")
    light = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    ImageDraw.Draw(light).ellipse([w * 0.18, -h * 0.55, w * 0.82, h * 0.42], fill=(255, 255, 255, 30))
    img = Image.alpha_composite(img, light.filter(ImageFilter.GaussianBlur(70 * k)))

    d = ImageDraw.Draw(img)
    cx = w / 2

    text(d, cx, 72 * k, "Install AlwaysOn", font(28 * k, 680), WHITE + (255,), tracking=-0.012)
    text(d, cx, 101 * k, "Drag the app into your Applications folder", font(14 * k, 450), WHITE + (225,))

    # Trail of evenly spaced dots that brightens into the green chevron
    y = L["iconY"] * k
    start = L["appX"] + L["iconSize"] / 2 + 22
    tip = L["applicationsX"] - L["iconSize"] / 2 - 18
    arm = 11
    step = 19
    n = int((tip - arm - 12 - start) // step) + 1
    first = tip - arm - 12 - (n - 1) * step
    for i in range(n):
        t = i / max(1, n - 1)
        r = (2.4 + 1.3 * t) * k
        x = (first + i * step) * k
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, round(80 + 160 * t)))
    stroke = 4 * k
    pts = [((tip - arm) * k, y - arm * k), (tip * k, y), ((tip - arm) * k, y + arm * k)]
    d.line(pts, fill=GREEN + (255,), width=round(stroke), joint="curve")
    for x, yy in (pts[0], pts[2]):
        d.ellipse([x - stroke / 2, yy - stroke / 2, x + stroke / 2, yy + stroke / 2], fill=GREEN + (255,))

    text(d, cx, (L["windowHeight"] - 30) * k,
         "First launch blocked? Open System Settings › Privacy & Security › Open Anyway",
         font(12 * k, 450), WHITE + (235,))

    out = img.resize((W * scale, H * scale), Image.LANCZOS).convert("RGB")

    # About one level of dither so the 8-bit gradient doesn't band
    noise = Image.effect_noise(out.size, 1.0).convert("L")
    return ImageChops.add(out, Image.merge("RGB", [noise] * 3), scale=1.0, offset=-128)


def folder(size):
    """Rough stand-in for the Applications folder icon, for previews only."""
    k = 4
    s = size * k
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([s * .08, s * .17, s * .45, s * .32], radius=s * .04, fill=(95, 170, 225))
    d.rounded_rectangle([s * .08, s * .24, s * .92, s * .82], radius=s * .06, fill=(118, 192, 240))
    return img.resize((size, size), Image.LANCZOS)


def contrast_report(art):
    def lum(c):
        f = lambda v: (v / 255) / 12.92 if v / 255 <= 0.03928 else (((v / 255) + 0.055) / 1.055) ** 2.4
        r, g, b = map(f, c[:3])
        return .2126 * r + .7152 * g + .0722 * b
    scale = art.width // W
    y0 = (L["iconY"] + L["iconSize"] / 2 + 2) * scale
    worst_white, worst_black = 99, 99
    for cx in (L["appX"], L["applicationsX"]):
        for y in range(int(y0), int(y0 + 18 * scale)):
            for x in range(int((cx - 42) * scale), int((cx + 42) * scale)):
                l = lum(art.getpixel((x, y)))
                worst_white = min(worst_white, 1.05 / (l + .05))
                worst_black = min(worst_black, (l + .05) / .05)
    print(f"Label rows: white labels {worst_white:.2f}:1, black labels {worst_black:.2f}:1 (worst pixel)")


def preview(art, path):
    scale = art.width // W
    size = L["iconSize"] * scale
    icon = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=size * .225, fill=255)
    icon.putalpha(mask)
    apps = folder(size)
    label = ImageFont.truetype(FONT, 13 * scale)
    gap = 12 * scale
    sheet = Image.new("RGB", (art.width, art.height * 2 + gap), (24, 24, 24))
    for row, color in enumerate(((0, 0, 0), WHITE)):
        frame = art.copy()
        fd = ImageDraw.Draw(frame)
        for x, img, name in ((L["appX"], icon, "AlwaysOn"), (L["applicationsX"], apps, "Applications")):
            cx, cy = x * scale, L["iconY"] * scale
            frame.paste(img, (cx - size // 2, cy - size // 2), img)
            fd.text((cx, cy + size // 2 + 10 * scale), name, font=label, fill=color, anchor="mm")
        # Mark where the guaranteed-visible area ends
        fd.line([(0, L["windowHeight"] * scale), (art.width, L["windowHeight"] * scale)], fill=(255, 80, 80), width=1)
        sheet.paste(frame, (0, row * (art.height + gap)))
    sheet.save(path)
    contrast_report(art)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", help="also write a layout mock with both label colours to this path")
    args = ap.parse_args()
    one, two = render(1), render(2)
    one.save(os.path.join(HERE, "background.png"), optimize=True)
    two.save(os.path.join(HERE, "background@2x.png"), optimize=True, dpi=(144, 144))
    if args.preview:
        preview(two, args.preview)
    print("Wrote background.png and background@2x.png")


if __name__ == "__main__":
    main()
