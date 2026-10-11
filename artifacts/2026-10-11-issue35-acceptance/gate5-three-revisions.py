#!/usr/bin/env python3
"""Gate-5 across revisions: count "stranded" pixels of the assembled Kot-Arbuz.

Replicates the algorithm of `Scripts/accept-kot-arbuz-v2.py::connected_gate`
(alpha > 8 mask, flood-fill from the median opaque pixel, 4-connectivity) for
three revisions of the layer set:

  * 3c8ac30  — v1 baseline (`main` when issue #35 was written; expected 13 px)
  * b61e581  — the pre-fix v2 attempt (expected 1197 px; 4 blobs)
  * WORKTREE — the current worktree (expected 0 px; 1 blob)

Run from the repository root:  python3 gate5-three-revisions.py
"""
import io
import subprocess

import numpy as np
from PIL import Image

PACKS = ("kot-arbuz", "kot-arbuz-moonlight", "kot-arbuz-strawberry")
LAYERS = ("head", "body", "tail", "legs-a", "legs-b", "legs-c")


def stranded(rev: str) -> dict[str, int]:
    out: dict[str, int] = {}
    for pack in PACKS:
        stack = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        for layer in LAYERS:
            path = f"Resources/PetSkins/{pack}/{layer}.png"
            if rev == "WORKTREE":
                data = open(path, "rb").read()
            else:
                data = subprocess.run(
                    ["git", "show", f"{rev}:{path}"], capture_output=True
                ).stdout
            if data:
                stack.alpha_composite(Image.open(io.BytesIO(data)).convert("RGBA"))
        opaque = np.asarray(stack)[..., 3] > 8
        total = int(opaque.sum())
        ys, xs = np.nonzero(opaque)
        reach = np.zeros_like(opaque)
        reach[int(np.median(ys)), int(np.median(xs))] = True
        reach &= opaque
        for _ in range(4000):
            prev = reach.copy()
            reach[1:, :] |= prev[:-1, :]
            reach[:-1, :] |= prev[1:, :]
            reach[:, 1:] |= prev[:, :-1]
            reach[:, :-1] |= prev[:, 1:]
            reach &= opaque
            if np.array_equal(reach, prev):
                break
        out[pack] = total - int(reach.sum())
    return out


def main() -> None:
    for rev, label in (
        ("3c8ac30", "v1 main base (3c8ac30)"),
        ("b61e581", "pre-fix v2 attempt (b61e581)"),
        ("WORKTREE", "current worktree (main @ 505193c)"),
    ):
        r = stranded(rev)
        cells = "  ".join(f"{k}={v}px" for k, v in r.items())
        print(f"{label:36s}: {cells}")


if __name__ == "__main__":
    main()
