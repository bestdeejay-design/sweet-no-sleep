#!/usr/bin/env python3
"""Validate the bundled, data-only pet skin manifests without third-party deps."""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SKIN_ROOT = ROOT / "Resources" / "PetSkins"
HEX_COLOR = re.compile(r"^#?[0-9a-fA-F]{6}$")
SAFE_ID = re.compile(r"^[A-Za-z0-9_-]{1,48}$")
EFFECTS = {"leaves", "moonDust", "berryHearts", "starburst"}
COLOR_KEYS = {"fur", "furLight", "outline", "innerEar", "iris", "accent", "cheek"}
ANIMATION_RANGES = {
    "breathingFrequency": (0.2, 8.0),
    "breathingAmplitude": (0.0, 0.08),
    "tailFrequency": (0.2, 10.0),
    "tailAmplitude": (0.0, 0.35),
}


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def fail(path: Path, message: str) -> None:
    print(f"{display_path(path)}: {message}", file=sys.stderr)


def validate(path: Path) -> tuple[str | None, list[str]]:
    problems: list[str] = []
    try:
        with path.open(encoding="utf-8") as file:
            skin: Any = json.load(file)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return None, [f"invalid JSON: {error}"]

    if not isinstance(skin, dict):
        return None, ["manifest root must be a JSON object"]

    for key in ("id", "name", "subtitle", "colors", "animation"):
        if key not in skin:
            problems.append(f"missing required field: {key}")

    skin_id = skin.get("id")
    if not isinstance(skin_id, str) or not SAFE_ID.fullmatch(skin_id):
        problems.append("id must contain 1–48 ASCII letters, digits, hyphens or underscores")
        skin_id = None

    if not isinstance(skin.get("name"), str) or not skin["name"].strip():
        problems.append("name must be a non-empty string")
    if not isinstance(skin.get("subtitle"), str):
        problems.append("subtitle must be a string")

    colors = skin.get("colors")
    if not isinstance(colors, dict):
        problems.append("colors must be an object")
    else:
        for key in sorted(COLOR_KEYS):
            value = colors.get(key)
            if not isinstance(value, str) or not HEX_COLOR.fullmatch(value):
                problems.append(f"colors.{key} must be a six-digit hex color")

    animation = skin.get("animation")
    if not isinstance(animation, dict):
        problems.append("animation must be an object")
    else:
        for key, (minimum, maximum) in ANIMATION_RANGES.items():
            value = animation.get(key)
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                problems.append(f"animation.{key} must be a number")
                continue
            if not math.isfinite(value) or not minimum <= value <= maximum:
                problems.append(f"animation.{key} must be in the range {minimum}…{maximum}")
        effect = animation.get("celebrationEffect")
        if not isinstance(effect, str) or effect not in EFFECTS:
            problems.append("animation.celebrationEffect must be one of: " + ", ".join(sorted(EFFECTS)))

    return skin_id, problems


def main() -> int:
    if len(sys.argv) > 1:
        manifests: list[Path] = []
        for raw_path in sys.argv[1:]:
            path = Path(raw_path).expanduser().resolve()
            if path.is_file() and path.name == "skin.json":
                manifests.append(path)
            elif path.is_dir():
                direct_manifest = path / "skin.json"
                manifests.extend([direct_manifest] if direct_manifest.is_file() else path.glob("*/skin.json"))
            else:
                print(f"Not a skin.json file or pack directory: {path}", file=sys.stderr)
                return 1
        manifests = sorted(set(manifests))
    else:
        manifests = sorted(SKIN_ROOT.glob("*/skin.json"))

    if not manifests:
        print("No skin manifests found.", file=sys.stderr)
        return 1

    seen_ids: dict[str, Path] = {}
    failures = 0
    for manifest in manifests:
        skin_id, problems = validate(manifest)
        if skin_id is not None:
            previous = seen_ids.get(skin_id)
            if previous is not None:
                problems.append(f"duplicate id {skin_id!r}; already used by {display_path(previous)}")
            else:
                seen_ids[skin_id] = manifest
        for problem in problems:
            fail(manifest, problem)
            failures += 1

    if failures:
        print(f"Skin validation failed: {failures} issue(s) across {len(manifests)} manifest(s).", file=sys.stderr)
        return 1

    print(f"Skin validation passed: {len(manifests)} manifest(s), {len(seen_ids)} unique IDs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
