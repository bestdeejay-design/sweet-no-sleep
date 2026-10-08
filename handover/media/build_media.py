#!/usr/bin/env python3
"""Build the Kot-Arbuz media pack for the dajet.ru portfolio page (issue #18).

Every image in this handover pack is derived from sources that already live in
this repository, so the pack can always be rebuilt byte-for-byte from the repo:

| Output            | Source                                                              |
| ----------------- | ------------------------------------------------------------------- |
| `kot-arbuz.jpg`   | `Resources/Characters/kot-arbuz/kot-arbuz.png` (3756 x 3756 master) |
| `skin-card.jpg`   | `Resources/PetSkins/kot-arbuz/{body,tail}.png` sprite layers        |
| `og-16.jpg`       | the same transparent sprite layers (never the master PNG)          |
| `app-states.jpg`  | `artifacts/2026-10-08-pr16-acceptance-evidence.png`                 |

Rules followed (ksu DESIGN_RULES + this repo's `docs/MEDIA.md`):

* JPEG, quality 85, progressive, optimized; weight caps per deliverable.
* Downscale-only rendering: nothing is ever upscaled. The sprite layers are
  1024 x 1024, so the skin card renders them at 752 px inside a 1200 x 800
  canvas, and the og card crops them to the silhouette at 520 px tall.
* `skin-card.jpg` reuses the composition language of
  `Scripts/prepare-character-assets.py::preview_images` (mint-to-blush wash,
  white halo, character left of centre, palette dots on the right) at scale 5
  instead of scale 2, which is exactly 1200 x 800.
* `og-16.jpg` must be cut from the transparent layers: the master PNG has an
  opaque white backdrop, and flattening it onto the dark card would paint a
  white rectangle over the page's Open Graph preview.

Requires Pillow and NumPy (development helper only; the committed JPEGs are the
deliverable and the app never runs this script).

Usage:
    python3 handover/media/build_media.py            # rebuild all four images
    python3 handover/media/build_media.py --check    # report what would change
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw
except ImportError as error:  # pragma: no cover - development helper only
    print(f"build_media.py needs Pillow and NumPy: {error}", file=sys.stderr)
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
MASTER = ROOT / "Resources" / "Characters" / "kot-arbuz" / "kot-arbuz.png"
BODY = ROOT / "Resources" / "PetSkins" / "kot-arbuz" / "body.png"
TAIL = ROOT / "Resources" / "PetSkins" / "kot-arbuz" / "tail.png"
EVIDENCE = ROOT / "artifacts" / "2026-10-08-pr16-acceptance-evidence.png"

SPRITE = 1024          # sprite layer canvas, shared by body.png and tail.png
JPEG_QUALITY = 85

# --- skin card (1200 x 800): the preview_images() design grid at scale 5 -----
CARD_SCALE = 5
CARD_W, CARD_H = 240 * CARD_SCALE, 160 * CARD_SCALE
CARD_WASH_START = (0xED, 0xF8, 0xE3)   # soft mint
CARD_WASH_END = (0xFC, 0xE9, 0xEC)     # soft blush
CARD_HALO_RGB = (255, 255, 255, 107)
CARD_DOTS = ("#93BE6E", "#F3FFDE", "#FD9D9A")

# --- og card (1200 x 630) ----------------------------------------------------
OG_W, OG_H = 1200, 630
OG_BACKGROUND = (0x0B, 0x0B, 0x0B)
OG_CHARACTER_HEIGHT = 520
OG_GLOW_RIND = (0x7F, 0xAF, 0x5E)     # #7FAF5E watermelon rind
OG_GLOW_FLESH = (0xFD, 0x5D, 0x5D)    # #FD5D5D watermelon flesh


def diagonal_gradient(size: tuple[int, int], start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    """The mint-to-blush wash, identical math to prepare-character-assets.py."""
    width, height = size
    mix = (
        np.add.outer(np.linspace(0, 1, height, dtype=np.float32), np.linspace(0, 1, width, dtype=np.float32))
        / 2.0
    )
    channels = [
        (start[index] + (end[index] - start[index]) * mix).round().astype(np.uint8)
        for index in range(3)
    ]
    return Image.fromarray(np.dstack(channels), mode="RGB").convert("RGBA")


def save_jpeg(image: Image.Image, path: Path) -> None:
    image.convert("RGB").save(
        path,
        format="JPEG",
        quality=JPEG_QUALITY,
        optimize=True,
        progressive=True,
    )


def build_master() -> Image.Image:
    """kot-arbuz.jpg: master art flattened to white, 2000 x 2000."""
    with Image.open(MASTER) as handle:
        master = handle.convert("RGBA")
    flat = Image.new("RGBA", master.size, (255, 255, 255, 255))
    flat.alpha_composite(master)
    return flat.convert("RGB").resize((2000, 2000), Image.LANCZOS)


def sprite_composite() -> Image.Image:
    """The live character: tail under body on the shared 1024 x 1024 canvas."""
    sprite = Image.new("RGBA", (SPRITE, SPRITE), (0, 0, 0, 0))
    with Image.open(TAIL) as handle:
        sprite.alpha_composite(handle.convert("RGBA"))
    with Image.open(BODY) as handle:
        sprite.alpha_composite(handle.convert("RGBA"))
    return sprite


def build_skin_card() -> Image.Image:
    """skin-card.jpg: the Settings-card composition at 1200 x 800 (scale 5)."""
    scale = CARD_SCALE
    width, height = CARD_W, CARD_H
    canvas = diagonal_gradient((width, height), CARD_WASH_START, CARD_WASH_END)

    corner = Image.new("L", (width, height), 0)
    ImageDraw.Draw(corner).rounded_rectangle([0, 0, width - 1, height - 1], radius=22 * scale, fill=255)
    canvas.putalpha(corner)

    halo = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    halo_radius = 69 * scale
    halo_center = (100 * scale, 82 * scale)
    ImageDraw.Draw(halo).ellipse(
        [
            halo_center[0] - halo_radius,
            halo_center[1] - halo_radius,
            halo_center[0] + halo_radius,
            halo_center[1] + halo_radius,
        ],
        fill=CARD_HALO_RGB,
    )
    canvas.alpha_composite(halo)

    # Downscale-only: the 1024 px sprite is drawn at 752 px inside the card.
    side = int(0.94 * height)
    sprite = sprite_composite().resize((side, side), Image.LANCZOS)
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    layer.paste(sprite, (int(width * 0.42) - side // 2, int(height * 0.52) - side // 2), sprite)
    canvas.alpha_composite(layer)

    dots = ImageDraw.Draw(canvas)
    for index, color in enumerate(CARD_DOTS):
        center = (190 * scale, (52 + index * 30) * scale)
        radius = 11 * scale
        dots.ellipse(
            [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
            fill=color,
            outline=(255, 255, 255, 255),
            width=3 * scale,
        )
    return canvas.convert("RGB")


def gaussian_blob(size: tuple[int, int], center: tuple[float, float], radius: float, peak: float) -> np.ndarray:
    """Smooth radial falloff (0..peak) used for the og glow."""
    width, height = size
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    distance = np.sqrt((xs - center[0]) ** 2 + (ys - center[1]) ** 2) / radius
    return peak * np.exp(-2.2 * distance**2)


def build_og() -> Image.Image:
    """og-16.jpg: dark card, silhouette-cropped character, palette glow."""
    sprite = sprite_composite()
    alpha = np.array(sprite)[:, :, 3]
    ys, xs = np.nonzero(alpha > 8)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    cropped = sprite.crop(box)

    target_h = OG_CHARACTER_HEIGHT
    target_w = int(round(cropped.width * target_h / cropped.height))
    character = cropped.resize((target_w, target_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (OG_W, OG_H), OG_BACKGROUND + (255,))
    center = (OG_W / 2.0, OG_H / 2.0)

    # Two tinted lobes of one smooth falloff: rind green up-left, flesh red
    # down-right, so the glow reads as his palette rather than a grey haze.
    green = gaussian_blob((OG_W, OG_H), (center[0] - 60, center[1] - 40), 290.0, 58.0)
    red = gaussian_blob((OG_W, OG_H), (center[0] + 70, center[1] + 50), 250.0, 50.0)
    glow = np.zeros((OG_H, OG_W, 4), dtype=np.float32)
    total = green + red + 1e-6
    for channel in range(3):
        glow[:, :, channel] = (green * OG_GLOW_RIND[channel] + red * OG_GLOW_FLESH[channel]) / total
    glow[:, :, 3] = np.minimum(green + red, 96.0)
    canvas.alpha_composite(Image.fromarray(glow.round().astype(np.uint8), mode="RGBA"))

    paste = (int(round(center[0] - target_w / 2.0)), int(round(center[1] - target_h / 2.0)))
    layer = Image.new("RGBA", (OG_W, OG_H), (0, 0, 0, 0))
    layer.paste(character, paste, character)
    canvas.alpha_composite(layer)
    return canvas.convert("RGB")


def build_app_states() -> Image.Image:
    """app-states.jpg: the PR #16 evidence strip at 2200 px wide."""
    with Image.open(EVIDENCE) as handle:
        strip = handle.convert("RGB")
    if strip.width > 2200:
        height = int(round(strip.height * 2200 / strip.width))
        strip = strip.resize((2200, height), Image.LANCZOS)
    return strip


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare against the committed JPEGs, write nothing")
    arguments = parser.parse_args()

    outputs = [
        ("kot-arbuz.jpg", build_master()),
        ("skin-card.jpg", build_skin_card()),
        ("og-16.jpg", build_og()),
        ("app-states.jpg", build_app_states()),
    ]

    for name, image in outputs:
        path = OUT / name
        if arguments.check:
            if not path.is_file():
                print(f"{name} is missing from the handover pack", file=sys.stderr)
                return 1
            with Image.open(path) as existing:
                if existing.size != image.size or existing.convert("RGB").tobytes() != image.tobytes():
                    print(f"{name} differs from the derived image", file=sys.stderr)
                    return 1
            continue
        save_jpeg(image, path)
        print(f"wrote {path.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}  {path.stat().st_size / 1024:.0f} KB")

    if arguments.check:
        print("Handover media check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
