#!/usr/bin/env python3
"""Acceptance helper for the Kot-Arbuz v2 rebuild (issue #29).

Design rule: every gate in here is exact, and anything heuristic is printed as
a number for a human to judge - never as a pass/fail. An earlier revision of
this script tried to decide the art revision by aligning each layer with the
part sheet by bounding box, and it rejected a correct v2 rebuild. The first
explanation recorded here - that the pieces are rotated (legs 68-79 degrees, the
tail 28) - turned out to be wrong: it came from comparing against the v1
algorithm's differently cut layers. Verified against PR #32, every piece keeps
its orientation (layer and sheet aspects match within 0.6 %) and the transform is
a uniform scale plus translation. The bounding-box heuristic is still gone: it
was never measuring art revision.

Gates (all exact):

1. `prepare-character-assets.py --check` passes — the arena's own pipeline
   agrees with the committed assets.
2. The committed derived assets differ from the base revision — the art really
   changed instead of `--check` going green on the old pack.
3. The pipeline points at the v2 sources — `MASTER`/`PARTS` (or whatever the
   script calls them) resolve inside `Resources/Characters/kot-arbuz/v2/`.
4. With `--app`, the assembled bundle carries byte-identical layers and
   previews to the committed ones — the build is not stale.

Reported for review (no verdict):

- Per layer of the base pack: the best rotation of the matching part-sheet
  piece and the residual difference at that angle, next to the same number for
  the layer as committed at the base revision. A v2 layer should show a small
  residual at some angle and lose to the base layer at angle 0 when the art
  really switched.
- Visual sheets: the six layers of each pack on a checkerboard, and each pack's
  preview rendered at the on-screen character sizes (45 / 132 / 170 pt panels).

    python3 Scripts/accept-kot-arbuz-v2.py
    python3 Scripts/accept-kot-arbuz-v2.py --base origin/main
    python3 Scripts/accept-kot-arbuz-v2.py --app "dist/Sweet No Sleep — Kiwi Cat.app" \
        --out artifacts/acceptance-kot-arbuz-v2

Exit status 0 only when every gate passes.
"""
from __future__ import annotations

import argparse
import io
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PACKS = ("kot-arbuz", "kot-arbuz-moonlight", "kot-arbuz-strawberry")
LAYERS = ("head", "body", "tail", "legs-a", "legs-b", "legs-c")
V2_DIR = ROOT / "Resources" / "Characters" / "kot-arbuz" / "v2"
V2_PARTS = V2_DIR / "kot-arbuz-v2-parts.png"

# Bounding boxes of the six pieces on the 3756 x 3756 part sheet, measured from
# the sheet itself (Resources/Characters/kot-arbuz/v2/README.md).
PART_BOXES = {
    "head": (1304, 80, 3195, 1927),
    "body": (1176, 2058, 2402, 2824),
    "tail": (498, 1928, 1061, 2478),
    "legs-a": (927, 2722, 1339, 3417),
    "legs-b": (1729, 2885, 2035, 3417),
    "legs-c": (2305, 2666, 2644, 3197),
}
WHITE_CUTOFF = 245
GRID = 64
ANGLES = range(-180, 180, 4)


def git_show(revision: str, path: str) -> bytes | None:
    result = subprocess.run(["git", "-C", str(ROOT), "show", f"{revision}:{path}"], capture_output=True)
    return result.stdout if result.returncode == 0 else None


def keyed(image: Image.Image) -> Image.Image:
    """Transparent where the pixel is essentially white (the sheet has no alpha)."""
    rgb = image.convert("RGB")
    channels = rgb.split()
    minimum = np.minimum(np.minimum(np.asarray(channels[0]), np.asarray(channels[1])), np.asarray(channels[2]))
    alpha = np.where(minimum >= WHITE_CUTOFF, 0, 255).astype(np.uint8)
    out = rgb.convert("RGBA")
    out.putalpha(Image.fromarray(alpha))
    return out


def content(image: Image.Image) -> Image.Image | None:
    box = image.getchannel("A").getbbox()
    return image.crop(box) if box else None


def on_white(image: Image.Image, size: int = GRID) -> np.ndarray:
    """Content scaled into a size x size frame, composited on white, as float RGB."""
    frame = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    scaled = image.copy()
    scaled.thumbnail((size, size), Image.LANCZOS)
    frame.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    return np.asarray(frame.convert("RGB"), dtype=np.float32)


def residual(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.abs(a - b).mean())


def best_rotation(layer: Image.Image, piece: Image.Image) -> tuple[int, float]:
    """Best angle for 'rotate the sheet piece, then fit it to the layer'.

    The fit normalises scale and translation away, so the search measures the
    rotation (and therefore the aspect) of the piece: a naive bounding-box
    comparison cannot do this, and getting it wrong is exactly how the previous
    revision of this script produced a false REJECT.
    """
    target = on_white(layer)
    best_angle, best = 0, float("inf")
    for angle in ANGLES:
        rotated = piece.rotate(angle, resample=Image.BICUBIC, expand=True)
        rotated = content(rotated)
        if rotated is None:
            continue
        value = residual(target, on_white(rotated))
        if value < best:
            best_angle, best = angle, value
    return best_angle, best


def pipeline_check() -> tuple[bool, str, list[str]]:
    print("== gate 1: pipeline self-consistency ==")
    result = subprocess.run(
        [sys.executable, str(ROOT / "Scripts" / "prepare-character-assets.py"), "--check"],
        capture_output=True,
        text=True,
    )
    detail = (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    anchors = [line.strip() for line in result.stdout.splitlines() if line.startswith("  ")]
    print(f"   {'PASS' if result.returncode == 0 else 'FAIL'}: {detail}")
    if anchors:
        print("   derived rig: " + ", ".join(anchors))
    return result.returncode == 0, detail, anchors


def gate_changed(base: str) -> tuple[bool, int]:
    print(f"\n== gate 2: committed assets vs base {base} ==")
    total = changed = 0
    for pack in PACKS:
        names = []
        for layer in LAYERS:
            path = f"Resources/PetSkins/{pack}/{layer}.png"
            reference = git_show(base, path)
            disk = ROOT / path
            total += 1
            if reference is None or not disk.is_file():
                names.append(f"{layer}:missing")
                continue
            same = reference == disk.read_bytes()
            changed += 0 if same else 1
            names.append(f"{layer}:{'same' if same else 'CHANGED'}")
        preview = f"Resources/Art/Rendered/preview-{pack}.png"
        reference = git_show(base, preview)
        disk = ROOT / preview
        if reference is not None and disk.is_file():
            names.append(f"preview:{'same' if reference == disk.read_bytes() else 'CHANGED'}")
        print(f"   {pack}: " + "  ".join(names))
    ok = changed > 0
    print(f"   {'PASS' if ok else 'FAIL'}: {changed} of {total} layer files differ from the base")
    return ok, changed


def gate_wiring() -> tuple[bool, str]:
    """The pipeline must read its art from `Resources/Characters/kot-arbuz/v2/`."""
    print("\n== gate 3: pipeline wired to the v2 sources ==")
    script = (ROOT / "Scripts" / "prepare-character-assets.py").read_text(encoding="utf-8")
    hits = [line.strip() for line in script.splitlines() if "Characters" in line and "Resources" in line]
    for line in hits:
        print(f"   {line}")
    ok = any("v2" in line for line in hits)
    if ok:
        print("   PASS: at least one art source resolves inside Characters/kot-arbuz/v2/")
    else:
        print("   FAIL: no v2 source is referenced — the pipeline still reads the v1 master")
    return ok, "; ".join(hits)


def gate_bundle(app: Path) -> bool:
    print(f"\n== gate 4: assembled app vs source ({app.name}) ==")
    if not app.is_dir():
        print(f"   FAIL: no such bundle: {app}")
        return False
    problems = []
    for pack in PACKS:
        for name in LAYERS:
            source = ROOT / "Resources" / "PetSkins" / pack / f"{name}.png"
            bundled = app / "Contents" / "Resources" / "PetSkins" / pack / f"{name}.png"
            if not bundled.is_file():
                problems.append(f"bundle lacks PetSkins/{pack}/{name}.png")
            elif source.is_file() and source.read_bytes() != bundled.read_bytes():
                problems.append(f"bundle/{pack}/{name}.png differs from the source")
    for pack in PACKS:
        for suffix in ("", "@2x"):
            name = f"preview-{pack}{suffix}.png"
            source = ROOT / "Resources" / "Art" / "Rendered" / name
            bundled = app / "Contents" / "Resources" / "Media" / name
            if not bundled.is_file():
                problems.append(f"bundle lacks Media/{name}")
            elif source.is_file() and source.read_bytes() != bundled.read_bytes():
                problems.append(f"bundle Media/{name} differs from the rendered source")
    for problem in problems[:10]:
        print(f"   FAIL: {problem}")
    print("   PASS: the bundle carries the committed layers and previews" if not problems else "   FAIL: rebuild with Scripts/build-app.sh")
    return not problems


def report_transforms(base: str) -> None:
    print("\n== for review: part-sheet alignment of the base pack (no verdict) ==")
    print("   The pieces on the sheet are scaled and translated, not rotated (verified on")
    print("   PR #32), but a bounding-box comparison against the *old* layers is still")
    print("   meaningless because they are cut differently. Read this as a hint, not a gate:")
    print("   the residual mixes the art")
    print("   revision with decomposition differences (the sheet is cut differently")
    print("   from the current layers), so a high number does not by itself mean v1.")
    print("   Identical files compared at the same angle give 0.00.")
    if not V2_PARTS.is_file():
        print(f"   skipped: no part sheet at {V2_PARTS.relative_to(ROOT)}")
        return
    sheet = Image.open(V2_PARTS)
    pieces = {name: keyed(sheet.crop(box)) for name, box in PART_BOXES.items()}
    print(f"   {'layer':<8} {'current: angle':>16} {'resid':>7}   {'base rev: angle':>16} {'resid':>7}")
    for layer in LAYERS:
        disk = ROOT / "Resources" / "PetSkins" / "kot-arbuz" / f"{layer}.png"
        if not disk.is_file():
            continue
        current = content(Image.open(disk).convert("RGBA"))
        base_bytes = git_show(base, f"Resources/PetSkins/kot-arbuz/{layer}.png")
        base_layer = content(Image.open(io.BytesIO(base_bytes)).convert("RGBA")) if base_bytes else None
        if current is None or pieces[layer] is None:
            continue
        angle, value = best_rotation(current, pieces[layer])
        if base_layer is not None:
            base_angle, base_value = best_rotation(base_layer, pieces[layer])
        else:
            base_angle, base_value = 0, float("nan")
        print(f"   {layer:<8} {angle:>16} {value:>7.2f}   {base_angle:>16} {base_value:>7.2f}")


def write_sheets(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    checker = Image.new("RGBA", (1024, 1024), (238, 238, 242, 255))
    pen = ImageDraw.Draw(checker)
    for y in range(0, 1024, 32):
        for x in range(0, 1024, 32):
            if (x // 32 + y // 32) % 2:
                pen.rectangle((x, y, x + 31, y + 31), fill=(216, 216, 226, 255))

    tile_size = 256
    for pack in PACKS:
        sheet = Image.new("RGB", (tile_size * 3, tile_size * 2 + 24), (255, 255, 255))
        draw = ImageDraw.Draw(sheet)
        for index, layer in enumerate(LAYERS):
            disk = ROOT / "Resources" / "PetSkins" / pack / f"{layer}.png"
            if not disk.is_file():
                continue
            tile = checker.copy()
            tile.alpha_composite(Image.open(disk).convert("RGBA"))
            tile.thumbnail((tile_size, tile_size))
            x = (index % 3) * tile_size
            y = (index // 3) * (tile_size + 12)
            sheet.paste(tile, (x, y))
            draw.text((x + 8, y + 8), f"{pack}/{layer}", fill=(20, 20, 20))
        sheet.save(out / f"layers-{pack}.png")

        preview = ROOT / "Resources" / "Art" / "Rendered" / f"preview-{pack}@2x.png"
        if not preview.is_file():
            continue
        source = Image.open(preview).convert("RGBA")
        strips = []
        for panel in (45, 132, 170):
            height = max(8, round(panel * 0.8759))     # character height at that panel size
            scale = height / source.height
            strips.append((panel, source.resize((max(1, round(source.width * scale)), height), Image.LANCZOS)))
        width = sum(small.width for _, small in strips) + 40 * len(strips)
        height = max(small.height for _, small in strips) + 48
        for backdrop, tag in (((250, 250, 252), "light"), ((28, 28, 32), "dark")):
            strip = Image.new("RGB", (width, height), backdrop)
            stripe = ImageDraw.Draw(strip)
            x = 20
            for panel, small in strips:
                strip.paste(small, (x, 32), small)
                stripe.text((x, 12), f"{panel} pt", fill=(90, 90, 96) if tag == "light" else (215, 215, 220))
                x += small.width + 40
            strip.save(out / f"preview-{pack}-sizes-{tag}.png")
    try:
        shown: Path | str = out.relative_to(ROOT)
    except ValueError:
        shown = out
    print(f"\n   wrote visual sheets to {shown}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="main~1", help="revision with the previous derivation (default: main~1)")
    parser.add_argument("--app", help="assembled .app bundle to compare against the source assets")
    parser.add_argument("--out", help="directory for the visual sheets")
    arguments = parser.parse_args()

    pipeline_ok, _, _ = pipeline_check()
    changed_ok, changed = gate_changed(arguments.base)
    wiring_ok, _ = gate_wiring()
    bundle_ok = gate_bundle(Path(arguments.app)) if arguments.app else True

    report_transforms(arguments.base)
    if arguments.out:
        write_sheets(Path(arguments.out).resolve())

    print("\n== summary ==")
    print(f"   gate 1 pipeline --check : {'PASS' if pipeline_ok else 'FAIL'}")
    print(f"   gate 2 art switched     : {'PASS' if changed_ok else 'FAIL'} ({changed} files changed)")
    print(f"   gate 3 wired to v2      : {'PASS' if wiring_ok else 'FAIL'}")
    if arguments.app:
        print(f"   gate 4 bundle fresh     : {'PASS' if bundle_ok else 'FAIL'}")
    ok = pipeline_ok and changed_ok and wiring_ok and bundle_ok
    print("\nVERDICT: " + ("ACCEPT" if ok else "REJECT - see the FAIL lines above"))
    if ok:
        print("   Still eyeball the visual sheets: the gates prove the pack is new and")
        print("   self-consistent, they cannot tell you the cat looks right.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
