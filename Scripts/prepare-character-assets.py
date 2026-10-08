#!/usr/bin/env python3
"""Derive the layered Kot-Arbuz character assets from the master artwork.

The master `Resources/Characters/kot-arbuz/kot-arbuz.png` is a 3756 x 3756
illustration on a flat white background. The floating panel needs the character
as transparent sprites, split into two layers so the renderer can animate
breathing (body) and the signature tail wag (tail) independently:

    Resources/PetSkins/kot-arbuz/body.png
    Resources/PetSkins/kot-arbuz/tail.png
    Resources/Art/Rendered/preview-kot-arbuz.png       (Settings card preview)
    Resources/Art/Rendered/preview-kot-arbuz@2x.png

Both sprite layers share one square canvas and are exported at 1024 x 1024, so
drawing them into the same rect restores the artwork exactly, while the tail
rotates around the pivot printed by this script (kept in `pet.json`).

Geometry of the artwork, measured on the master:

* the character occupies a 998 x 960 box inside the 3756 px master;
* the tail is a separate crescent that only merges with the body near the
  bottom-left, so a vertical cut plus a horizontal cut at the merge row
  isolates it (see `tail_region`);
* the illustration draws its outlines in pure white, so the background flood
  fill leaks along thin white channels unless they are closed first.

This is a development helper, not part of the app or of `check-project.sh`:
it needs Pillow and NumPy, and the derived PNGs are committed, so building the
app never runs it. Re-run it only when the master artwork changes, then run
`--check` to confirm the committed files match.

Usage:
    python3 Scripts/prepare-character-assets.py
    python3 Scripts/prepare-character-assets.py --check
    python3 Scripts/prepare-character-assets.py --preview /tmp/layers.png
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
except ImportError as error:  # pragma: no cover - development helper only
    print(f"prepare-character-assets.py needs Pillow and NumPy: {error}", file=sys.stderr)
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "Resources" / "Characters" / "kot-arbuz" / "kot-arbuz.png"
PACK = ROOT / "Resources" / "PetSkins" / "kot-arbuz"
RENDERED = ROOT / "Resources" / "Art" / "Rendered"

WORK = 1600          # resolution the masks are derived at
CANVAS = 1024        # exported sprite size
BACKGROUND_FLOOR = 236
CHANNEL_RADIUS = 4   # closes white outline channels up to 8 px wide
PADDING_RATIO = 0.05
BODY_MARGIN = 12     # static body pixels kept along the tail cut (hidden overlap)


def window_any(mask: np.ndarray, radius: int, axis: int) -> np.ndarray:
    """True where any True lies within `radius` along `axis` (running window)."""
    if radius <= 0:
        return mask
    moved = np.moveaxis(mask, axis, 0)
    counts = np.cumsum(moved.astype(np.int32), axis=0)
    counts = np.concatenate([np.zeros((1,) + counts.shape[1:], dtype=np.int32), counts], axis=0)
    length = moved.shape[0]
    indices = np.arange(length)
    high = np.minimum(indices + radius + 1, length)
    low = np.maximum(indices - radius, 0)
    return np.moveaxis(counts[high] - counts[low] > 0, 0, axis)


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    """Square-kernel dilation; the square corners never matter for these masks."""
    return window_any(window_any(mask, radius, 0), radius, 1)


def erode(mask: np.ndarray, radius: int) -> np.ndarray:
    return ~dilate(~mask, radius)


def flood_from_border(near_white: np.ndarray) -> np.ndarray:
    """Flood fill the backdrop: sweep rows and columns to a fixed point."""
    reached = np.zeros_like(near_white)
    reached[0, :] |= near_white[0, :]
    reached[-1, :] |= near_white[-1, :]
    reached[:, 0] |= near_white[:, 0]
    reached[:, -1] |= near_white[:, -1]
    while True:
        grown = reached.copy()
        for _ in range(2):  # one row sweep and one column sweep, both directions
            grown = np.maximum.accumulate(grown, axis=1) & near_white
            grown = np.flip(np.maximum.accumulate(np.flip(grown, axis=1), axis=1), axis=1) & near_white
            grown = np.maximum.accumulate(grown, axis=0) & near_white
            grown = np.flip(np.maximum.accumulate(np.flip(grown, axis=0), axis=0), axis=0) & near_white
        if np.array_equal(grown, reached):
            return reached
        reached = grown


def largest_blob(mask: np.ndarray, factor: int = 4) -> np.ndarray:
    """Keep the largest connected component of `mask` (explored at block scale)."""
    factor = max(factor, 1)
    height = mask.shape[0] // factor * factor
    width = mask.shape[1] // factor * factor
    blocks = mask[:height, :width].reshape(height // factor, factor, width // factor, factor).any(axis=(1, 3))
    rows, columns = blocks.shape
    labels = np.zeros_like(blocks, dtype=np.int32)
    best_label = 0
    best_size = 0
    current = 0
    for start_y in range(rows):
        for start_x in range(columns):
            if not blocks[start_y, start_x] or labels[start_y, start_x]:
                continue
            current += 1
            size = 0
            stack = [(start_y, start_x)]
            labels[start_y, start_x] = current
            while stack:
                y, x = stack.pop()
                size += 1
                for next_y, next_x in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= next_y < rows and 0 <= next_x < columns and blocks[next_y, next_x] and not labels[next_y, next_x]:
                        labels[next_y, next_x] = current
                        stack.append((next_y, next_x))
            if size > best_size:
                best_size = size
                best_label = current
    if best_label == 0:
        return mask
    keep = labels == best_label
    keep = np.repeat(np.repeat(keep, factor, axis=0), factor, axis=1)
    expanded = np.zeros_like(mask)
    expanded[: keep.shape[0], : keep.shape[1]] = keep
    return dilate(mask & expanded, factor) & mask


def character_mask(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Return (soft alpha 0-255, hard character mask) for the master pixels."""
    near_white = np.all(rgb >= BACKGROUND_FLOOR, axis=2)
    backdrop = flood_from_border(near_white)

    # Anti-aliased outline pixels ramp from transparent to opaque; everything
    # the flood fill could not reach is character, including white highlights.
    lightness = rgb.min(axis=2).astype(np.float32) / 255.0
    ramp = np.clip((1.0 - lightness) / 0.10, 0.0, 1.0)
    alpha = np.where(backdrop, ramp * 255.0, 255.0)

    character = alpha > 12
    # The artwork draws outlines in white; the flood fill leaks along those thin
    # channels and would punch holes in the tail. Closing them keeps the mask
    # solid and lets the interior white lines stay opaque, as in the master.
    closed = erode(dilate(character, CHANNEL_RADIUS), CHANNEL_RADIUS)
    alpha = np.array(
        Image.fromarray(np.where(closed, alpha, 0.0).round().astype(np.uint8), mode="L").filter(ImageFilter.GaussianBlur(0.7))
    )
    return alpha, closed


def row_runs(character: np.ndarray, row: int) -> list[tuple[int, int]]:
    """Continuous [start, end] segments of character pixels in one row."""
    columns = np.nonzero(character[row])[0]
    if columns.size == 0:
        return []
    starts = np.concatenate([[columns[0]], columns[1:][np.diff(columns) > 1]])
    ends = np.concatenate([columns[:-1][np.diff(columns) > 1], [columns[-1]]])
    return list(zip((int(value) for value in starts), (int(value) for value in ends)))


def tail_region(character: np.ndarray) -> tuple[np.ndarray, tuple[int, int], int]:
    """Isolate the tail crescent and its rotation pivot at work resolution."""
    ys, xs = np.nonzero(character)
    minimum_x = int(xs.min())
    tail_rows = np.nonzero(character[:, minimum_x : minimum_x + 8].any(axis=1))[0]
    first_row, last_row = int(tail_rows.min()), int(tail_rows.max())

    # The cut sits inside the background gap the artwork leaves between the tail
    # crescent and the body: right of the crescent, left of the body edge.
    body_edges = []
    for row in range(first_row, last_row + 1):
        runs = row_runs(character, row)
        if not runs:
            continue
        body_start = max(runs, key=lambda run: run[1] - run[0])[0]
        if body_start > minimum_x + 40:
            body_edges.append(body_start)
    if not body_edges:
        raise SystemExit("Could not locate the body edge next to the tail.")
    cut_x = min(body_edges) - 40

    # Merge row: the first row where the tail stroke reaches the body and the
    # run becomes long. The tail layer stops just above it, where the stroke is
    # still free-standing, so the cut only crosses the tail itself.
    merge_row = last_row
    for row in range(first_row, last_row + 1):
        for start, end in row_runs(character, row):
            if start <= cut_x - 20 and end - start > 200:
                merge_row = row
                break
        else:
            continue
        break

    region = character.copy()
    region[:, cut_x:] = False
    region[merge_row:, :] = False
    region = largest_blob(region)
    if not region.any():
        raise SystemExit("Tail separation produced an empty layer.")
    tail_y, tail_x = np.nonzero(region)
    base_row = int(tail_y.max())
    pivot = (int(round(float(tail_x[tail_y == base_row].mean()))), base_row + 1)
    return region, pivot, cut_x


def layer_image(rgb: np.ndarray, alpha: np.ndarray, box: tuple[int, int, int, int]) -> Image.Image:
    image = Image.fromarray(rgb, mode="RGB").convert("RGBA")
    image.putalpha(Image.fromarray(alpha, mode="L"))
    return image.crop(box).resize((CANVAS, CANVAS), Image.LANCZOS)


def compose_layers(
    rgb: np.ndarray,
    alpha: np.ndarray,
    character: np.ndarray,
    tail: np.ndarray,
    pivot: tuple[int, int],
    cut_x: int,
) -> tuple[Image.Image, Image.Image, dict[str, float]]:
    """Cut the two sprite layers and report the anchors the renderer needs."""
    # The body keeps a static band of tail pixels along the cut: at rest it is
    # identical to the master (draw order tail, then body), while under rotation
    # it hides the seam behind an opaque margin.
    body = character & ~erode(tail, BODY_MARGIN)

    ys, xs = np.nonzero(character)
    min_x, max_x = int(xs.min()), int(xs.max())
    min_y, max_y = int(ys.min()), int(ys.max())
    side = max(max_x - min_x, max_y - min_y)
    side += int(side * PADDING_RATIO) * 2
    center_x = (min_x + max_x) / 2
    center_y = (min_y + max_y) / 2
    left = int(round(center_x - side / 2))
    top = int(round(center_y - side / 2))
    box = (left, top, left + side, top + side)

    body_alpha = np.where(body, alpha, 0).astype(np.uint8)
    tail_alpha = np.where(tail, alpha, 0).astype(np.uint8)

    metrics = {
        "tailPivotX": round((pivot[0] - box[0]) / side, 4),
        "tailPivotY": round((pivot[1] - box[1]) / side, 4),
        "characterWidth": round((max_x - min_x) / side, 4),
        "characterHeight": round((max_y - min_y) / side, 4),
        "cutX": round((cut_x - box[0]) / side, 4),
    }
    return layer_image(rgb, body_alpha, box), layer_image(rgb, tail_alpha, box), metrics


def gradient(size: tuple[int, int], start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
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


def preview_images(body: Image.Image, tail: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Compose the Settings card preview: wash card, character, palette dots."""
    scale = 2
    width, height = 240 * scale, 160 * scale
    canvas = gradient((width, height), (0xED, 0xF8, 0xE3), (0xFC, 0xE9, 0xEC))

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
        fill=(255, 255, 255, 107),
    )
    canvas.alpha_composite(halo)

    sprite = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sprite.alpha_composite(tail)
    sprite.alpha_composite(body)
    side = int(0.94 * height)
    sprite = sprite.resize((side, side), Image.LANCZOS)
    sprite_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    sprite_layer.paste(sprite, (int(width * 0.42) - side // 2, int(height * 0.52) - side // 2), sprite)
    canvas.alpha_composite(sprite_layer)

    dots = ImageDraw.Draw(canvas)
    for index, color in enumerate(("#93BE6E", "#F3FFDE", "#FD9D9A")):
        center = (190 * scale, (52 + index * 30) * scale)
        radius = 11 * scale
        dots.ellipse(
            [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
            fill=color,
            outline=(255, 255, 255, 255),
            width=3 * scale,
        )

    plain = canvas.convert("RGB")
    return plain.resize((240, 160), Image.LANCZOS), plain


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the committed assets instead of writing them")
    parser.add_argument("--preview", help="write a flattened composite of the layers to this path")
    arguments = parser.parse_args()

    with Image.open(MASTER) as handle:
        master = handle.resize((WORK, WORK), Image.LANCZOS)
    rgb = np.array(master.convert("RGB"))
    alpha, character = character_mask(rgb)
    tail_mask, pivot, cut_x = tail_region(character)
    body, tail, metrics = compose_layers(rgb, alpha, character, tail_mask, pivot, cut_x)
    small_preview, large_preview = preview_images(body, tail)

    print("Layers derived from the master artwork:")
    for key, value in metrics.items():
        print(f"  {key}: {value}")

    if arguments.preview:
        flattened = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 255))
        flattened.alpha_composite(tail)
        flattened.alpha_composite(body)
        flattened.convert("RGB").save(arguments.preview)

    committed = (
        (PACK / "body.png", body),
        (PACK / "tail.png", tail),
        (RENDERED / "preview-kot-arbuz.png", small_preview),
        (RENDERED / "preview-kot-arbuz@2x.png", large_preview),
    )

    if arguments.check:
        failures = 0
        for path, produced in committed:
            if not path.is_file():
                print(f"{path.relative_to(ROOT)} is missing", file=sys.stderr)
                failures += 1
                continue
            with Image.open(path) as existing:
                if existing.convert("RGBA").tobytes() != produced.convert("RGBA").tobytes():
                    print(f"{path.relative_to(ROOT)} differs from the derived asset", file=sys.stderr)
                    failures += 1
        print("Character asset check passed." if failures == 0 else "Character asset check failed.", file=sys.stderr)
        return 1 if failures else 0

    PACK.mkdir(parents=True, exist_ok=True)
    RENDERED.mkdir(parents=True, exist_ok=True)
    body.save(PACK / "body.png")
    tail.save(PACK / "tail.png")
    small_preview.save(RENDERED / "preview-kot-arbuz.png")
    large_preview.save(RENDERED / "preview-kot-arbuz@2x.png")
    print(f"Wrote {PACK.relative_to(ROOT)}/body.png, tail.png and both preview renders.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
