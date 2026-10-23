#!/usr/bin/env python3
"""Generate CareTV AI launcher icons, the Fire TV banner and store artwork.

The geometry mirrors lib/widgets/tv_app_logo.dart so the PNG assets match the
in-app logo. Requires Pillow (pip install pillow). numpy is optional.

Usage (from the project root):
    python3 tools/generate_assets.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
SS = 4  # supersampling factor for smooth edges

SLATE = (15, 23, 42)
CROSS = (244, 63, 94)
SPARKLE = (251, 191, 36)
WHITE = (255, 255, 255)
MUTED = (148, 163, 184)


def gradient(width, height, c1, c2):
    """Diagonal (top-left -> bottom-right) gradient image."""
    try:
        import numpy as np

        xs = np.linspace(0, 1, width)[None, :]
        ys = np.linspace(0, 1, height)[:, None]
        t = (xs + ys) / 2.0
        arr = np.zeros((height, width, 3), dtype=np.float32)
        for i in range(3):
            arr[:, :, i] = c1[i] + (c2[i] - c1[i]) * t
        return Image.fromarray(arr.astype("uint8"), "RGB")
    except ImportError:
        img = Image.new("RGB", (width, height))
        draw = ImageDraw.Draw(img)
        for y in range(height):
            t = y / max(1, height - 1)
            color = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
            draw.line([(0, y), (width, y)], fill=color)
        return img


def sparkle_points(cx, cy, radius):
    pts = []
    for i in range(8):
        r = radius if i % 2 == 0 else radius * 0.28
        a = -math.pi / 2 + i * math.pi / 4
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_logo(size, background=True):
    """Return an RGBA image of the logo, `size` x `size` pixels."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    if background:
        bg = gradient(s, s, (14, 165, 233), (20, 184, 166)).convert("RGBA")
        mask = Image.new("L", (s, s), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=255
        )
        img.paste(bg, (0, 0), mask)

    d = ImageDraw.Draw(img)
    sw = max(2, round(s * 0.035))
    half = sw / 2

    # TV body (stroke is centred on the path, like Flutter).
    d.rounded_rectangle(
        [s * 0.13 - half, s * 0.20 - half, s * 0.87 + half, s * 0.67 + half],
        radius=int(s * 0.07 + half),
        fill=WHITE,
    )
    d.rounded_rectangle(
        [s * 0.13 + half, s * 0.20 + half, s * 0.87 - half, s * 0.67 - half],
        radius=max(1, int(s * 0.07 - half)),
        fill=SLATE,
    )

    # Stand with round caps.
    def line(p1, p2):
        d.line([p1, p2], fill=WHITE, width=sw)
        for x, y in (p1, p2):
            d.ellipse([x - half, y - half, x + half, y + half], fill=WHITE)

    line((s * 0.5, s * 0.67), (s * 0.5, s * 0.77))
    line((s * 0.34, s * 0.79), (s * 0.66, s * 0.79))

    # Medical cross.
    cx, cy = s * 0.42, s * 0.435
    arm, thick = s * 0.13, s * 0.075
    rad = int(thick * 0.35)
    d.rounded_rectangle(
        [cx - arm, cy - thick / 2, cx + arm, cy + thick / 2], radius=rad, fill=CROSS
    )
    d.rounded_rectangle(
        [cx - thick / 2, cy - arm, cx + thick / 2, cy + arm], radius=rad, fill=CROSS
    )

    # AI sparkles.
    d.polygon(sparkle_points(s * 0.69, s * 0.35, s * 0.12), fill=SPARKLE)
    d.polygon(sparkle_points(s * 0.72, s * 0.55, s * 0.05), fill=WHITE)

    return img.resize((size, size), Image.LANCZOS)


def load_font(px, bold=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "C:\\Windows\\Fonts\\arialbd.ttf" if bold else "C:\\Windows\\Fonts\\arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
        if bold
        else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, int(px))
    return ImageFont.load_default()


def make_banner(width, height):
    """16:9 banner: logo + wordmark (mirrors TVBannerLogo)."""
    img = gradient(width, height, SLATE, (19, 78, 74)).convert("RGBA")
    pad = height * 0.12
    logo_size = int(height * 0.62)
    logo = draw_logo(logo_size, background=False)
    img.alpha_composite(logo, (int(pad), int((height - logo_size) / 2)))

    d = ImageDraw.Draw(img)
    x = int(pad + logo_size + height * 0.08)
    title_font = load_font(height * 0.145, bold=True)
    sub_font = load_font(height * 0.07)
    title_h = d.textbbox((0, 0), "CareTV AI", font=title_font)[3]
    sub_h = d.textbbox((0, 0), "Smart care on your TV", font=sub_font)[3]
    top = int((height - (title_h + sub_h + height * 0.03)) / 2)
    d.text((x, top), "CareTV AI", font=title_font, fill=WHITE)
    d.text((x, top + title_h + height * 0.03), "Smart care on your TV", font=sub_font, fill=MUTED)
    return img.convert("RGB")


def save(img, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT), img.size)


def main():
    # Launcher icons (legacy mipmaps; `flutter create` skips files that exist).
    for density, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(draw_logo(px), RES, f"mipmap-{density}", "ic_launcher.png")

    # Android TV / Fire TV launcher banner: 320 x 180 px in drawable-xhdpi.
    save(make_banner(320, 180), RES, "drawable-xhdpi", "tv_banner.png")

    # Store artwork (check Amazon's current asset specs before submitting).
    save(draw_logo(512), ROOT, "store_assets", "icon_512x512.png")
    save(make_banner(1280, 720), ROOT, "store_assets", "banner_1280x720.png")


if __name__ == "__main__":
    main()
