#!/usr/bin/env python3
"""Generates the DiceKeys app icon from the original mark.

Source: scripts/app-icon-source/original-mark-1024.png, the blue-on-white DiceKeys box
that has always been the app icon. Nothing is redrawn; the mark is split into two layers
by color so Icon Composer can light them as Liquid Glass:

  frame.png   the box (body, hinge tabs, latch)      -> DiceKeys blue, glass
  dice.png    the 25 dice inside the box             -> white, glass, in front

Colors are applied in icon.json (layer fills), so the layer PNGs are white silhouettes.
Light appearance: system light background, blue box, white dice (the original look).
Dark appearance: system dark background, lighter blue box, white dice.

Outputs
  DiceKeys/Resources/AppIcon.icon/                                Icon Composer package
  DiceKeys/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png        flat fallback

Run:  python3 scripts/generate-app-icon.py   (needs `pip install -r scripts/requirements.txt`)
"""

import json
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scripts" / "app-icon-source" / "original-mark-1024.png"
RESOURCES = ROOT / "DiceKeys" / "Resources"
SIZE = 1024
BLUE = (52, 65, 141)  # the mark's blue
BLUE_DARK_MODE = (99, 116, 204)  # lighter so the box reads on a dark background
WHITE = (255, 255, 255)
# The mark fills 144..893 x 64..959 of its 1024 canvas; scale it to sit inside the
# icon's safe area with even margins.
CONTENT_SCALE = 0.80


def load_mark():
    return Image.open(SOURCE).convert("RGB")


def split_layers(mark):
    """Returns (frame_alpha, dice_alpha) 'L' images from the blue-on-white mark.

    Blue coverage becomes the frame's alpha (antialiased edges preserved). White pixels
    that are not reachable from the canvas edge are the dice; everything else is background.
    """
    w, h = mark.size
    px = mark.load()
    frame = Image.new("L", (w, h), 0)
    fpx = frame.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            # 0 on pure white, 255 on the blue; linear in between for the antialiased edge
            whiteness = (r + g + b) / 3
            fpx[x, y] = max(0, min(255, round((255 - whiteness) * 255 / (255 - (BLUE[0] + BLUE[1] + BLUE[2]) / 3))))

    # Flood fill the exterior background from the corners through "mostly white" pixels.
    exterior = bytearray(w * h)
    q = deque([(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)])
    while q:
        x, y = q.popleft()
        if exterior[y * w + x]:
            continue
        if fpx[x, y] > 64:
            continue
        exterior[y * w + x] = 1
        if x > 0:
            q.append((x - 1, y))
        if x < w - 1:
            q.append((x + 1, y))
        if y > 0:
            q.append((x, y - 1))
        if y < h - 1:
            q.append((x, y + 1))

    dice = Image.new("L", (w, h), 0)
    dpx = dice.load()
    for y in range(h):
        for x in range(w):
            if not exterior[y * w + x]:
                dpx[x, y] = 255 - fpx[x, y]
    return frame, dice


def fit_to_canvas(alpha):
    """Scales the 1024 mark down and centers it on a 1024 canvas."""
    size = round(SIZE * CONTENT_SCALE)
    scaled = alpha.resize((size, size), Image.LANCZOS)
    out = Image.new("L", (SIZE, SIZE), 0)
    out.paste(scaled, ((SIZE - size) // 2, (SIZE - size) // 2))
    return out


def silhouette(alpha, color=WHITE):
    img = Image.new("RGBA", alpha.size, color + (0,))
    img.putalpha(alpha)
    return img


def color_string(rgb):
    return "extended-srgb:{:.5f},{:.5f},{:.5f},1.00000".format(*tuple(c / 255 for c in rgb))


def write_icon_package(frame_alpha, dice_alpha):
    pkg = RESOURCES / "AppIcon.icon"
    assets = pkg / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    silhouette(frame_alpha).save(assets / "frame.png")
    silhouette(dice_alpha).save(assets / "dice.png")
    document = {
        "fill-specializations": [
            {"value": "system-light"},
            {"appearance": "dark", "value": "system-dark"},
        ],
        "groups": [
            {
                "name": "dice",
                "layers": [
                    {
                        "name": "dice",
                        "image-name": "dice.png",
                        "glass": True,
                        "fill": {"solid": color_string(WHITE)},
                    }
                ],
                "lighting": "individual",
                "specular": True,
                "shadow": {"kind": "neutral", "opacity": 0.35},
                "translucency": {"enabled": False, "value": 0.5},
            },
            {
                "name": "frame",
                "layers": [
                    {
                        "name": "frame",
                        "image-name": "frame.png",
                        "glass": True,
                        "fill-specializations": [
                            {"value": {"solid": color_string(BLUE)}},
                            {"appearance": "dark", "value": {"solid": color_string(BLUE_DARK_MODE)}},
                        ],
                    }
                ],
                "lighting": "combined",
                "specular": True,
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": False, "value": 0.5},
            },
        ],
        "supported-platforms": {"squares": "shared"},
    }
    (pkg / "icon.json").write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")


def flat_icon(frame_alpha, dice_alpha):
    """The original look, for tooling that cannot render the layered document."""
    out = Image.new("RGBA", (SIZE, SIZE), WHITE + (255,))
    out = Image.alpha_composite(out, silhouette(frame_alpha, BLUE))
    return Image.alpha_composite(out, silhouette(dice_alpha, WHITE))


def write_appiconset(name, image):
    folder = RESOURCES / "Assets.xcassets" / name
    for old in folder.glob("*.png"):
        old.unlink()
    image.save(folder / "AppIcon-1024.png")
    entry = {"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
    (folder / "Contents.json").write_text(
        json.dumps({"images": [entry], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )


def main():
    frame_alpha, dice_alpha = split_layers(load_mark())
    frame_alpha, dice_alpha = fit_to_canvas(frame_alpha), fit_to_canvas(dice_alpha)
    write_icon_package(frame_alpha, dice_alpha)
    write_appiconset("AppIcon.appiconset", flat_icon(frame_alpha, dice_alpha))
    print("wrote AppIcon.icon and AppIcon.appiconset")


if __name__ == "__main__":
    main()
