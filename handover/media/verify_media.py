#!/usr/bin/env python3
"""Programmatic acceptance checks for the Kot-Arbuz handover media pack.

Run after `build_media.py` (or on a fresh clone) to prove the pack meets the
delivery contract of issue #18 before it is copied into `ksu`:

* exact pixel dimensions per deliverable;
* JPEG weight caps (200 KB cover, 100 KB og, 300 KB detail strip);
* the og card carries no large white rectangle: all four corners are the dark
  `#0b0b0b` page background and near-white pixels are a rounding-error share;
* every file decodes as a baseline-or-progressive JPEG at quality-friendly
  settings and reports its real on-disk size.

Usage:
    python3 handover/media/verify_media.py
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError as error:  # pragma: no cover - development helper only
    print(f"verify_media.py needs Pillow and NumPy: {error}", file=sys.stderr)
    raise SystemExit(2)

OUT = Path(__file__).resolve().parent

SPEC = {
    "kot-arbuz.jpg": {"size": (2000, 2000), "max_kb": 200},
    "skin-card.jpg": {"size": (1200, 800), "max_kb": 300},
    "og-16.jpg": {"size": (1200, 630), "max_kb": 100},
    "app-states.jpg": {"size": (2200, 443), "max_kb": 300},
}

OG_CORNER_PATCH = 12        # corner square sampled on the og card
OG_CORNER_MAX = 40          # darkest-page-background tolerance per channel
OG_WHITE_FLOOR = 236        # "near white" threshold for the rectangle scan
OG_WHITE_MAX_SHARE = 0.004  # a white card would own tens of percent


def corner_stats(pixels: np.ndarray, patch: int) -> list[tuple[tuple[int, ...], int]]:
    height, width = pixels.shape[:2]
    corners = {
        "top-left": pixels[:patch, :patch],
        "top-right": pixels[:patch, width - patch :],
        "bottom-left": pixels[height - patch :, :patch],
        "bottom-right": pixels[height - patch :, width - patch :],
    }
    report = []
    for name, block in corners.items():
        mean = block.reshape(-1, 3).mean(axis=0)
        report.append((name, tuple(int(round(value)) for value in mean), int(block.max())))
    return report


def main() -> int:
    failures = 0

    def fail(message: str) -> None:
        nonlocal failures
        failures += 1
        print(f"  FAIL {message}", file=sys.stderr)

    for name, spec in SPEC.items():
        path = OUT / name
        print(f"{name}:")
        if not path.is_file():
            fail(f"{name} is missing")
            continue
        weight_kb = path.stat().st_size / 1024
        with Image.open(path) as handle:
            if handle.format != "JPEG":
                fail(f"{name} is {handle.format}, expected JPEG")
            size = handle.size
            pixels = np.array(handle.convert("RGB"))
        print(f"  dimensions {size[0]}x{size[1]}  weight {weight_kb:.0f} KB")
        if size != spec["size"]:
            fail(f"{name} is {size[0]}x{size[1]}, expected {spec['size'][0]}x{spec['size'][1]}")
        if weight_kb > spec["max_kb"]:
            fail(f"{name} weighs {weight_kb:.0f} KB, cap is {spec['max_kb']} KB")

        if name == "og-16.jpg":
            for corner, mean, peak in corner_stats(pixels, OG_CORNER_PATCH):
                status = "ok" if peak <= OG_CORNER_MAX else "FAIL"
                print(f"  corner {corner}: mean rgb{mean} max {peak} [{status}]")
                if peak > OG_CORNER_MAX:
                    fail(f"og corner {corner} is rgb{mean} (max {peak}): a light rectangle reaches the edge")
            near_white = np.all(pixels >= OG_WHITE_FLOOR, axis=2)
            share = float(near_white.mean())
            print(f"  near-white pixel share {share * 100:.3f}% (cap {OG_WHITE_MAX_SHARE * 100:.1f}%)")
            if share > OG_WHITE_MAX_SHARE:
                fail(f"og carries {share * 100:.2f}% near-white pixels: the master's white backdrop leaked in")
            # The character must sit inside the frame, centred. The glow peaks
            # near rgb(78, 57, 42), so a 90-per-channel floor isolates the cat.
            lit = pixels.max(axis=2) > 90
            ys, xs = np.nonzero(lit)
            if ys.size == 0:
                fail("og card is empty: no character pixels found")
            else:
                box = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
                center = ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)
                height = box[3] - box[1] + 1
                print(f"  character bbox {box}  height {height}  centre ({center[0]:.0f}, {center[1]:.0f})")
                if not 500 <= height <= 540:
                    fail(f"og character is {height} px tall, expected ~520 px")
                if abs(center[0] - 600) > 8 or abs(center[1] - 315) > 8:
                    fail(f"og character centre ({center[0]:.0f}, {center[1]:.0f}) is off the 600/315 mark")

    print("Handover media verification passed." if failures == 0 else f"{failures} verification failure(s).", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
