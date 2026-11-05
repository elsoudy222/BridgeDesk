#!/usr/bin/env python3
"""Generate BridgeDesk app icons from scratch (no binary assets in git).

The macOS AppIcon set (7 PNGs) and the Windows .ico are binary files,
so they are NOT committed to the repository — the GitHub snapshot push
used here only carries UTF-8 text. Run this once after cloning, and
the release workflow runs it before every build:

    cd app
    pip install pillow        # once, if Pillow is missing
    python3 tool/generate_icons.py

Output:
  macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_<size>.png
  windows/runner/resources/app_icon.ico

Design: solid BridgeDesk blue (#2563EB) with a white "B". Replace with
real brand art later by dropping your own files at those same paths.
"""
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Pillow is required: pip install pillow", file=sys.stderr)
    sys.exit(1)

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLUE = (37, 99, 235, 255)
WHITE = (255, 255, 255, 255)

MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ICO_SIZES = [256, 128, 64, 48, 32, 16]


def make_icon(size: int) -> "Image.Image":
    img = Image.new("RGBA", (size, size), BLUE)
    draw = ImageDraw.Draw(img)
    # Rounded-square feel: a slightly inset lighter panel.
    pad = max(1, size // 12)
    draw.rounded_rectangle(
        [pad, pad, size - pad, size - pad],
        radius=size // 6,
        fill=(59, 130, 246, 255),
    )
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", size // 2)
    except OSError:
        font = ImageFont.load_default()
    draw.text(
        (size // 2, size // 2),
        "B",
        font=font,
        fill=WHITE,
        anchor="mm",
    )
    return img


def main() -> None:
    mac_dir = os.path.join(
        APP_DIR,
        "macos",
        "Runner",
        "Assets.xcassets",
        "AppIcon.appiconset",
    )
    os.makedirs(mac_dir, exist_ok=True)
    for size in MAC_SIZES:
        path = os.path.join(mac_dir, f"app_icon_{size}.png")
        make_icon(size).save(path, format="PNG")
        print(f"wrote {path}")

    win_dir = os.path.join(APP_DIR, "windows", "runner", "resources")
    os.makedirs(win_dir, exist_ok=True)
    ico_path = os.path.join(win_dir, "app_icon.ico")
    biggest = make_icon(256)
    biggest.save(ico_path, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    print(f"wrote {ico_path}")


if __name__ == "__main__":
    main()
