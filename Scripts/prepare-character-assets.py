#!/usr/bin/env python3
"""Derive the layered Kot-Arbuz character assets from the master artwork.

The master `Resources/Characters/kot-arbuz/kot-arbuz.png` is a 3756 x 3756
illustration on a flat white background. The floating panel needs the character
as transparent sprites, split into layers so the renderer can animate them
independently (issue #17, animation parity with the procedural Kiwi):

    Resources/PetSkins/kot-arbuz/body.png     torso, without tail/head/legs
    Resources/PetSkins/kot-arbuz/tail.png     the tail crescent alone
    Resources/PetSkins/kot-arbuz/head.png     hood, ears and face (eyes removed)
    Resources/PetSkins/kot-arbuz/legs-a.png   left outer leg (tripod pair A)
    Resources/PetSkins/kot-arbuz/legs-b.png   middle leg (pair B)
    Resources/PetSkins/kot-arbuz/legs-c.png   right outer leg (tripod pair A)
    Resources/PetSkins/kot-arbuz-<variant>/   recolored packs, same rig
    Resources/Art/Rendered/preview-*.png      Settings card previews

All sprite layers share one square canvas and are exported at 1024 x 1024, so
drawing them into the same rect (legs, tail, body, head, then the vector eyes
at the anchors below) restores the artwork exactly at rest, while each layer
rotates around its own pivot:

* the tail rotates around `tailPivotX/Y` (unchanged from format 1);
* the head rotates/bobs around `headPivotX/Y`, the centre of the neck cut;
* each of the three leg layers swings around its own `legPivot*` hip cut, the
  two outer legs phased together against the middle one (tripod gait);
* `eyeLeft*` / `eyeRight*` are the socket anchors of the painted eyes, which
  this script erases from the head layer (inpainting the face pink) so the
  renderer can draw vector eyes that track the cursor, blink and close.

The cuts are straight rows chosen inside regions another layer covers at rest:
the neck cut sits where the hood is as wide as the shoulders, and the hip cut
sits inside the torso, so the body's static overlap bands hide both seams while
layers move. Layer draw order at rest: legs-a, legs-b, tail, body, head, eyes.

Geometry of the artwork, measured on the master at `WORK` resolution:

* the character occupies a 998 x 960 box inside the 3756 px master;
* the tail is a separate crescent that only merges with the body near the
  bottom-left, so a vertical cut plus a horizontal cut at the merge row
  isolates it (see `tail_region`);
* the illustration draws its outlines in pure white, so the background flood
  fill leaks along thin white channels unless they are closed first;
* the two painted eyes are the largest near-black blobs on the face
  (~54 x 78 px at `WORK`); the seeds, mouth, whiskers and claws are smaller or
  thinner and are left alone.

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
import json
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
NECK_ROW = 1010      # head/body cut: hood is shoulder-wide here
LEG_ROW = 1160       # hip cut: inside the torso, hidden behind the body
SEAM_BAND = 18       # static overlap band each layer keeps across a cut
EYE_DARK_FLOOR = 90  # near-black threshold for the painted eyes
EYE_MIN_AREA = 2000  # ignores seeds, mouth, whiskers and claws

PET_FORMAT = 2       # pet.json format: 2 adds the head/leg/eye rig

# Recolored variant packs: hue-band remaps in HSV space (hue 0...1, plus
# saturation/value scales). Bands: green rind, pink flesh, pale highlights.
VARIANTS = {
    "kot-arbuz-moonlight": {
        "green": (0.655, 0.52, 1.06),
        "pink": (0.870, 0.55, 1.05),
        "pale": (0.640, 0.60, 1.02),
    },
    "kot-arbuz-strawberry": {
        "green": (0.955, 0.82, 1.02),
        "pink": (0.075, 0.72, 1.06),
        "pale": (0.950, 0.90, 1.02),
    },
}


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
            if blocks[start_y, start_x] or labels[start_y, start_x]:
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


def label_blobs(mask: np.ndarray, factor: int = 2, min_pixels: int = 0) -> list[np.ndarray]:
    """Connected components of `mask`, largest first (block-scale flood).

    Only components of at least `min_pixels` are materialized as full-size
    masks; thin stroke fragments stay label IDs and cost nothing.
    """
    factor = max(factor, 1)
    height = mask.shape[0] // factor * factor
    width = mask.shape[1] // factor * factor
    blocks = mask[:height, :width].reshape(height // factor, factor, width // factor, factor).any(axis=(1, 3))
    rows, columns = blocks.shape
    labels = np.zeros_like(blocks, dtype=np.int32)
    current = 0
    sizes: dict[int, int] = {}
    for start_y in range(rows):
        for start_x in range(columns):
            if blocks[start_y, start_x] or labels[start_y, start_x]:
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
            sizes[current] = size
    components = []
    for label, size in sorted(sizes.items(), key=lambda item: -item[1]):
        if size * factor * factor < min_pixels:
            continue
        keep = np.repeat(np.repeat(labels == label, factor, axis=0), factor, axis=1)
        expanded = np.zeros_like(mask)
        expanded[: keep.shape[0], : keep.shape[1]] = keep
        components.append(dilate(mask & expanded, factor) & mask)
    return components


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


def eye_sockets(character: np.ndarray, rgb: np.ndarray) -> list[dict[str, float]]:
    """Locate the two painted eyes: the largest near-black blobs on the face."""
    dark = (rgb.max(axis=2) < EYE_DARK_FLOOR) & character
    sockets = []
    for blob in label_blobs(dark, factor=2, min_pixels=EYE_MIN_AREA):
        area = int(blob.sum())
        if area < EYE_MIN_AREA:
            continue
        ys, xs = np.nonzero(blob)
        width = xs.max() - xs.min() + 1
        height = ys.max() - ys.min() + 1
        if not 0.45 <= width / height <= 0.95:
            continue
        sockets.append(
            {
                "x": float((xs.min() + xs.max() + 1) / 2),
                "y": float((ys.min() + ys.max() + 1) / 2),
                "radiusX": float(width / 2),
                "radiusY": float(height / 2),
            }
        )
    if len(sockets) != 2:
        raise SystemExit(f"Expected exactly two painted eyes, found {len(sockets)}.")
    return sorted(sockets, key=lambda socket: socket["x"])


def inpaint(rgb: np.ndarray, sockets: list[dict[str, float]]) -> np.ndarray:
    """Erase the painted eyes, filling them from the face pink around them."""
    fixed = rgb.copy()
    dark = rgb.max(axis=2) < EYE_DARK_FLOOR
    for socket in sockets:
        center = (int(round(socket["y"])), int(round(socket["x"])))
        radius = (int(round(socket["radiusY"])) + 3, int(round(socket["radiusX"])) + 3)
        slice_y = slice(center[0] - radius[0], center[0] + radius[0] + 1)
        slice_x = slice(center[1] - radius[1], center[1] + radius[1] + 1)
        # Include the anti-aliased fringe of the painted eye, otherwise a grey
        # ring survives the fill; the face pink itself stays well above 205.
        patch_max = fixed[slice_y, slice_x].max(axis=2)
        hole = patch_max < 205
        # Sample the face pink a few pixels away from the eye: the anti-aliased
        # eye edge is dark and would grey out the fill.
        clean = patch_max >= 215
        ring = dilate(hole, 8) & ~dilate(hole, 2) & clean
        samples = np.argwhere(ring)[::2].astype(np.float32)
        if samples.size == 0:
            continue
        targets = np.argwhere(hole).astype(np.float32)
        colors = fixed[slice_y, slice_x][ring.astype(bool)][::2].astype(np.float32)
        # Inverse-distance weighted fill: the face pink ramps diagonally, so a
        # local blend follows the gradient instead of flattening it.
        delta = targets[:, None, :] - samples[None, :, :]
        weight = 1.0 / (np.einsum("ijk,ijk->ij", delta, delta) + 4.0) ** 2
        weight /= weight.sum(axis=1, keepdims=True)
        filled = np.einsum("ij,jk->ik", weight, colors)
        patch = fixed[slice_y, slice_x].copy()
        patch[hole.astype(bool)] = filled.round().astype(np.uint8)
        # Soften the seam the fill leaves against the anti-aliased eye edge.
        blurred = np.array(Image.fromarray(patch).filter(ImageFilter.GaussianBlur(1.1)))
        seam = dilate(hole, 2)
        patch[seam] = blurred[seam]
        fixed[slice_y, slice_x] = patch
    return fixed


def leg_layers(character: np.ndarray) -> tuple[list[np.ndarray], list[tuple[int, int]]]:
    """Split the three legs into one layer each and report the hip pivots.

    Every leg rotates around its own hip, so the walk cycle can phase-offset
    them: the two outer legs (`legs-a`, `legs-c`) move together as a tripod
    pair against the middle leg (`legs-b`).
    """
    feet = character.copy()
    feet[: LEG_ROW + 36, :] = False
    blobs = label_blobs(feet, factor=2, min_pixels=400)[:3]
    if len(blobs) != 3:
        raise SystemExit(f"Expected three legs below the hip cut, found {len(blobs)}.")
    bands = []
    for blob in blobs:
        _, xs = np.nonzero(blob)
        bands.append((int(xs.min()) + int(xs.max())) / 2)
    order = sorted(range(3), key=lambda index: bands[index])
    centers = np.array([bands[index] for index in order])

    region = character.copy()
    region[:LEG_ROW, :] = False
    ys, xs = np.nonzero(region)
    distance = np.abs(xs.astype(np.float64)[:, None] - centers[None, :])
    owner = distance.argmin(axis=1)
    layers = []
    pivots = []
    for position in range(3):
        mask = np.zeros_like(region)
        mask[ys[owner == position], xs[owner == position]] = True
        layers.append(mask)
        layer_ys, layer_xs = np.nonzero(mask)
        hip_row = LEG_ROW + 8
        if mask[hip_row].any():
            pivot_x = int(round(float(layer_xs[layer_ys == hip_row].mean())))
        else:
            pivot_x = int(round(float(layer_xs.mean())))
        pivots.append((pivot_x, LEG_ROW))
    return layers, pivots


def layer_image(rgb: np.ndarray, alpha: np.ndarray, box: tuple[int, int, int, int]) -> Image.Image:
    """Cut one layer and resample it to the shared canvas.

    The resize runs on premultiplied color: straight-alpha LANCZOS would blend
    the transparent backdrop's white into every layer edge and leave a light
    halo along the straight cuts where two layers meet.
    """
    image = Image.fromarray(rgb, mode="RGB").convert("RGBA")
    image.putalpha(Image.fromarray(alpha, mode="L"))
    cut = image.crop(box)
    array = np.array(cut).astype(np.float32)
    premultiplied = array[:, :, :3] * array[:, :, 3:4] / 255.0
    stacked = np.dstack([premultiplied, array[:, :, 3:]])
    channels = [
        np.array(Image.fromarray(stacked[:, :, index].round().astype(np.uint8), mode="L").resize((CANVAS, CANVAS), Image.LANCZOS)).astype(np.float32)
        for index in range(4)
    ]
    resized = np.dstack(channels)
    out_alpha = resized[:, :, 3:]
    safe = np.where(out_alpha > 1, out_alpha, 1.0)
    color = np.clip(resized[:, :, :3] * 255.0 / safe, 0, 255)
    result = np.dstack([color, out_alpha]).round().astype(np.uint8)
    return Image.fromarray(result, mode="RGBA")


def compose_masks(
    character: np.ndarray,
    tail: np.ndarray,
    pivot: tuple[int, int],
    cut_x: int,
    sockets: list[dict[str, float]],
) -> tuple[dict[str, np.ndarray], tuple[int, int, int, int], dict[str, float]]:
    """Cut every sprite layer mask and report the anchors the renderer needs."""
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

    rows = np.arange(character.shape[0])[:, None]
    cols = np.arange(character.shape[1])[None, :]
    # The stroke that merges the tail crescent into the body sits below the tail
    # mask: it belongs to the static body, never to the bobbing head.
    tail_bottom = int(np.nonzero(tail)[0].max())
    tail_root = character & (rows >= tail_bottom - 6) & (cols <= cut_x + 60)
    head = character & (rows <= NECK_ROW) & ~tail & ~tail_root
    body = ((body & (rows >= NECK_ROW - SEAM_BAND) & (rows <= LEG_ROW + SEAM_BAND)) | tail_root) & ~erode(tail, BODY_MARGIN)
    leg_masks, leg_pivots = leg_layers(character)
    masks = {
        "body": body,
        "tail": tail,
        "head": head,
        "legs-a": leg_masks[0],
        "legs-b": leg_masks[1],
        "legs-c": leg_masks[2],
    }
    union = masks["body"] | masks["tail"] | masks["head"] | masks["legs-a"] | masks["legs-b"] | masks["legs-c"]
    if (union != character).any():
        missing = int((character & ~union).sum())
        extra = int((union & ~character).sum())
        raise SystemExit(f"Layer masks do not tile the character: {missing} missing, {extra} extra pixels.")

    def norm(point_x: float, point_y: float) -> tuple[float, float]:
        return round((point_x - box[0]) / side, 4), round((point_y - box[1]) / side, 4)

    metrics = {
        "tailPivotX": round((pivot[0] - box[0]) / side, 4),
        "tailPivotY": round((pivot[1] - box[1]) / side, 4),
        "characterWidth": round((max_x - min_x) / side, 4),
        "characterHeight": round((max_y - min_y) / side, 4),
        "cutX": round((cut_x - box[0]) / side, 4),
        "headPivotX": norm(center_x, NECK_ROW)[0],
        "headPivotY": norm(center_x, NECK_ROW)[1],
        "legPivotAX": norm(leg_pivots[0][0], leg_pivots[0][1])[0],
        "legPivotAY": norm(leg_pivots[0][0], leg_pivots[0][1])[1],
        "legPivotBX": norm(leg_pivots[1][0], leg_pivots[1][1])[0],
        "legPivotBY": norm(leg_pivots[1][0], leg_pivots[1][1])[1],
        "legPivotCX": norm(leg_pivots[2][0], leg_pivots[2][1])[0],
        "legPivotCY": norm(leg_pivots[2][0], leg_pivots[2][1])[1],
        "eyeLeftX": norm(sockets[0]["x"], sockets[0]["y"])[0],
        "eyeLeftY": norm(sockets[0]["x"], sockets[0]["y"])[1],
        "eyeRightX": norm(sockets[1]["x"], sockets[1]["y"])[0],
        "eyeRightY": norm(sockets[1]["x"], sockets[1]["y"])[1],
        "eyeRadiusX": round(sockets[0]["radiusX"] / side, 4),
        "eyeRadiusY": round(sockets[0]["radiusY"] / side, 4),
    }
    return masks, box, metrics


def cut_layers(
    rgb: np.ndarray,
    alpha: np.ndarray,
    masks: dict[str, np.ndarray],
    box: tuple[int, int, int, int],
) -> dict[str, Image.Image]:
    """Render every layer mask against `rgb` into a shared square canvas."""
    return {
        name: layer_image(rgb, np.where(mask, alpha, 0).astype(np.uint8), box)
        for name, mask in masks.items()
    }


def recolor(rgb: np.ndarray, bands: dict[str, tuple[float, float, float]]) -> np.ndarray:
    """Remap the artwork's hue bands for a palette variant, keeping shading."""
    values = rgb.astype(np.float32) / 255.0
    maximum = values.max(axis=2)
    minimum = values.min(axis=2)
    delta = maximum - minimum
    hue = np.zeros_like(maximum)
    red, green, blue = values[:, :, 0], values[:, :, 1], values[:, :, 2]
    mask = delta > 1e-6
    hue = np.where(mask & (maximum == red), ((green - blue) / np.where(mask, delta, 1)) % 6, hue)
    hue = np.where(mask & (maximum == green) & ~(maximum == red), (blue - red) / np.where(mask, delta, 1) + 2, hue)
    hue = np.where(mask & ~(maximum == red) & ~(maximum == green), (red - green) / np.where(mask, delta, 1) + 4, hue)
    hue = hue / 6.0
    saturation = np.where(maximum > 1e-6, delta / np.where(maximum > 1e-6, maximum, 1), 0.0)

    green_band = mask & (hue > 0.16) & (hue < 0.50)
    pink_band = mask & ((hue > 0.83) | (hue < 0.08)) & ~green_band
    pale_band = mask & ~green_band & ~pink_band
    dark = maximum < 0.22

    def shift(band: np.ndarray, target: tuple[float, float, float]) -> None:
        nonlocal hue, saturation, maximum
        target_hue, sat_scale, val_scale = target
        hue = np.where(band, target_hue, hue)
        saturation = np.where(band, np.clip(saturation * sat_scale, 0, 1), saturation)
        maximum = np.where(band, np.clip(maximum * val_scale, 0, 1), maximum)

    shift(green_band & ~dark, bands["green"])
    shift(pink_band & ~dark, bands["pink"])
    shift(pale_band & ~dark, bands["pale"])

    hue6 = hue * 6.0
    sector = np.floor(hue6).astype(np.int32) % 6
    fraction = hue6 - np.floor(hue6)
    p = maximum * (1 - saturation)
    q = maximum * (1 - saturation * fraction)
    t = maximum * (1 - saturation * (1 - fraction))
    table = np.stack(
        [
            np.stack([maximum, t, p], axis=-1),
            np.stack([q, maximum, p], axis=-1),
            np.stack([p, maximum, t], axis=-1),
            np.stack([p, q, maximum], axis=-1),
            np.stack([t, p, maximum], axis=-1),
            np.stack([maximum, p, q], axis=-1),
        ]
    )
    picked = np.take_along_axis(table, sector[None, ..., None], axis=0)[0]
    return (picked * 255).round().astype(np.uint8)


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


def draw_preview_eyes(draw: ImageDraw.ImageDraw, metrics: dict[str, float], width: int, height: int, side: int, offset: tuple[int, int], color: str) -> None:
    """Open vector eyes at the rig anchors, so the card matches the live pet."""
    for key in ("eyeLeft", "eyeRight"):
        center = (
            offset[0] + int(metrics[key + "X"] * side),
            offset[1] + int(metrics[key + "Y"] * side),
        )
        radius_x = max(int(metrics["eyeRadiusX"] * side), 2)
        radius_y = max(int(metrics["eyeRadiusY"] * side), 3)
        draw.ellipse(
            [center[0] - radius_x, center[1] - radius_y, center[0] + radius_x, center[1] + radius_y],
            fill=color,
        )
        shine = max(radius_x // 3, 1)
        draw.ellipse(
            [
                center[0] - radius_x // 2 - shine,
                center[1] - radius_y // 2 - shine,
                center[0] - radius_x // 2 + shine,
                center[1] - radius_y // 2 + shine,
            ],
            fill=(255, 255, 255, 235),
        )


def preview_images(layers: dict[str, Image.Image], metrics: dict[str, float], dots: tuple[str, str, str], outline: str) -> tuple[Image.Image, Image.Image]:
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
    for name in ("legs-a", "legs-b", "legs-c", "tail", "body", "head"):
        sprite.alpha_composite(layers[name])
    side = int(0.94 * height)
    sprite = sprite.resize((side, side), Image.LANCZOS)
    offset = (int(width * 0.42) - side // 2, int(height * 0.52) - side // 2)
    sprite_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    sprite_layer.paste(sprite, offset, sprite)
    canvas.alpha_composite(sprite_layer)
    draw_preview_eyes(ImageDraw.Draw(canvas), metrics, width, height, side, offset, outline)

    dots_draw = ImageDraw.Draw(canvas)
    for index, color in enumerate(dots):
        center = (190 * scale, (52 + index * 30) * scale)
        radius = 11 * scale
        dots_draw.ellipse(
            [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
            fill=color,
            outline=(255, 255, 255, 255),
            width=3 * scale,
        )

    plain = canvas.convert("RGB")
    return plain.resize((240, 160), Image.LANCZOS), plain


def pack_manifest(metrics: dict[str, float]) -> dict:
    """The `pet.json` character manifest (format 2: layered rig)."""
    return {
        "format": PET_FORMAT,
        "kind": "sprite",
        "canvas": CANVAS,
        "heightRatio": metrics["characterHeight"],
        "tailPivotX": metrics["tailPivotX"],
        "tailPivotY": metrics["tailPivotY"],
        "tailSwingDegrees": 4.5,
        "headPivotX": metrics["headPivotX"],
        "headPivotY": metrics["headPivotY"],
        "legPivotAX": metrics["legPivotAX"],
        "legPivotAY": metrics["legPivotAY"],
        "legPivotBX": metrics["legPivotBX"],
        "legPivotBY": metrics["legPivotBY"],
        "legPivotCX": metrics["legPivotCX"],
        "legPivotCY": metrics["legPivotCY"],
        "eyeLeftX": metrics["eyeLeftX"],
        "eyeLeftY": metrics["eyeLeftY"],
        "eyeRightX": metrics["eyeRightX"],
        "eyeRightY": metrics["eyeRightY"],
        "eyeRadiusX": metrics["eyeRadiusX"],
        "eyeRadiusY": metrics["eyeRadiusY"],
    }


def variant_skin(base_skin: dict, variant_id: str) -> dict:
    """The skin.json of a recolored variant pack (palette + effect only)."""
    skin = json.loads(json.dumps(base_skin))
    skin["id"] = variant_id
    if variant_id.endswith("moonlight"):
        skin["name"] = "Kot-Arbuz Moonlight"
        skin["subtitle"] = "Midnight rind and moon dust"
        skin["colors"] = {
            "fur": "#B9B9E9", "furLight": "#E8E8FF", "outline": "#414268",
            "innerEar": "#D99FCB", "iris": "#6C73B5", "accent": "#A5A3FF", "cheek": "#D99FCB",
        }
        skin["animation"] = {
            "breathingFrequency": 1.8, "breathingAmplitude": 0.012,
            "tailFrequency": 1.6, "tailAmplitude": 0.06, "celebrationEffect": "moonDust",
        }
    else:
        skin["name"] = "Kot-Arbuz Strawberry"
        skin["subtitle"] = "Berry rind and berry hearts"
        skin["colors"] = {
            "fur": "#F0A6A6", "furLight": "#FFE1DA", "outline": "#693E4B",
            "innerEar": "#BB6986", "iris": "#659276", "accent": "#83C66C", "cheek": "#E77F86",
        }
        skin["animation"] = {
            "breathingFrequency": 2.7, "breathingAmplitude": 0.022,
            "tailFrequency": 4.0, "tailAmplitude": 0.17, "celebrationEffect": "berryHearts",
        }
    return skin


def derive() -> tuple[dict[str, dict[str, Image.Image]], dict[str, float], dict[str, dict]]:
    """Derive every pack's layers, previews and manifests from the master."""
    with Image.open(MASTER) as handle:
        master = handle.resize((WORK, WORK), Image.LANCZOS)
    source = np.array(master.convert("RGB"))
    alpha, character = character_mask(source)
    sockets = eye_sockets(character, source)
    rgb = inpaint(source, sockets)
    tail_mask, pivot, cut_x = tail_region(character)
    masks, box, metrics = compose_masks(character, tail_mask, pivot, cut_x, sockets)
    layers = cut_layers(rgb, alpha, masks, box)

    base_skin = json.loads((PACK / "skin.json").read_text(encoding="utf-8"))
    packs: dict[str, dict[str, Image.Image]] = {"kot-arbuz": layers}
    skins: dict[str, dict] = {"kot-arbuz": base_skin}
    for variant_id, bands in VARIANTS.items():
        tinted = recolor(rgb, bands)
        packs[variant_id] = cut_layers(tinted, alpha, masks, box)
        skins[variant_id] = variant_skin(base_skin, variant_id)
    return packs, metrics, skins


def preview_for(pack_layers: dict[str, Image.Image], metrics: dict[str, float], skin: dict) -> tuple[Image.Image, Image.Image]:
    colors = skin["colors"]
    return preview_images(
        pack_layers,
        metrics,
        (colors["accent"], colors["furLight"], colors["cheek"]),
        colors["outline"],
    )


def committed_files(packs: dict[str, dict[str, Image.Image]], metrics: dict[str, float], skins: dict[str, dict]) -> list[tuple[Path, Image.Image]]:
    files: list[tuple[Path, Image.Image]] = []
    for pack_id, layers in packs.items():
        folder = ROOT / "Resources" / "PetSkins" / pack_id
        for name, image in layers.items():
            files.append((folder / f"{name}.png", image))
        small, large = preview_for(layers, metrics, skins[pack_id])
        files.append((RENDERED / f"preview-{pack_id}.png", small))
        files.append((RENDERED / f"preview-{pack_id}@2x.png", large))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the committed assets instead of writing them")
    parser.add_argument("--preview", help="write a flattened composite of the layers to this path")
    arguments = parser.parse_args()

    packs, metrics, skins = derive()

    print("Layers derived from the master artwork:")
    for key, value in metrics.items():
        print(f"  {key}: {value}")

    if arguments.preview:
        flattened = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 255))
        for name in ("legs-a", "legs-b", "legs-c", "tail", "body", "head"):
            flattened.alpha_composite(packs["kot-arbuz"][name])
        flattened.convert("RGB").save(arguments.preview)

    committed = committed_files(packs, metrics, skins)

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
        manifest = pack_manifest(metrics)
        for pack_id in packs:
            path = ROOT / "Resources" / "PetSkins" / pack_id / "pet.json"
            if not path.is_file():
                print(f"{path.relative_to(ROOT)} is missing", file=sys.stderr)
                failures += 1
                continue
            stored = json.loads(path.read_text(encoding="utf-8"))
            if stored != manifest:
                print(f"{path.relative_to(ROOT)} differs from the derived manifest", file=sys.stderr)
                failures += 1
        print("Character asset check passed." if failures == 0 else "Character asset check failed.", file=sys.stderr)
        return 1 if failures else 0

    for pack_id, layers in packs.items():
        folder = ROOT / "Resources" / "PetSkins" / pack_id
        folder.mkdir(parents=True, exist_ok=True)
        for name, image in layers.items():
            image.save(folder / f"{name}.png")
        manifest = pack_manifest(metrics)
        (folder / "pet.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        if pack_id != "kot-arbuz":
            skin = skins[pack_id]
            (folder / "skin.json").write_text(json.dumps(skin, indent=2) + "\n", encoding="utf-8")
        small, large = preview_for(layers, metrics, skins[pack_id])
        RENDERED.mkdir(parents=True, exist_ok=True)
        small.save(RENDERED / f"preview-{pack_id}.png")
        large.save(RENDERED / f"preview-{pack_id}@2x.png")
        print(f"Wrote {folder.relative_to(ROOT)} layers, pet.json and both preview renders.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
