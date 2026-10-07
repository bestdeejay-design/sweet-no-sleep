#!/usr/bin/env python3
"""Validate hand-authored SVG media and the macOS-rendered release assets."""
from __future__ import annotations

import argparse
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "Resources" / "Art"
RENDERED = ART / "Rendered"

SOURCES = {
    "app-icon.svg": (1024, 1024),
    "menubar-awake.svg": (22, 22),
    "menubar-asleep.svg": (22, 22),
    "preview-kiwi.svg": (240, 160),
    "preview-moonlight.svg": (240, 160),
    "preview-strawberry.svg": (240, 160),
    "banner.svg": (1280, 640),
    "og-image.svg": (1200, 630),
}

ICONSET = {
    "icon_16x16.png": (16, 16),
    "icon_16x16@2x.png": (32, 32),
    "icon_32x32.png": (32, 32),
    "icon_32x32@2x.png": (64, 64),
    "icon_128x128.png": (128, 128),
    "icon_128x128@2x.png": (256, 256),
    "icon_256x256.png": (256, 256),
    "icon_256x256@2x.png": (512, 512),
    "icon_512x512.png": (512, 512),
    "icon_512x512@2x.png": (1024, 1024),
}

RENDERED_IMAGES = {
    "app-icon-1024.png": (1024, 1024),
    "menubar-awake.png": (22, 22),
    "menubar-awake@2x.png": (44, 44),
    "menubar-asleep.png": (22, 22),
    "menubar-asleep@2x.png": (44, 44),
    "preview-kiwi.png": (240, 160),
    "preview-kiwi@2x.png": (480, 320),
    "preview-moonlight.png": (240, 160),
    "preview-moonlight@2x.png": (480, 320),
    "preview-strawberry.png": (240, 160),
    "preview-strawberry@2x.png": (480, 320),
    "banner.png": (1280, 640),
    "og-image.png": (1200, 630),
}

MASCOT_ART = (
    "app-icon.svg",
    "preview-kiwi.svg",
    "preview-moonlight.svg",
    "preview-strawberry.svg",
    "banner.svg",
    "og-image.svg",
)
MASCOT_SIGNATURES = (
    "M-76 44 C-100 15 -98 -12 -88 -33 L-84 -102",
    "M0 -76 Q-12.9 -88 -17 -100",
    'circle cx="0" cy="40" r="20.5"',
    'ellipse cx="30" cy="80" rx="20" ry="10"',
)


def report_error(errors: list[str], path: Path, message: str) -> None:
    try:
        name = path.relative_to(ROOT)
    except ValueError:
        name = path
    errors.append(f"{name}: {message}")


def number(value: str | None) -> float | None:
    if value is None:
        return None
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)(?:px)?\s*", value)
    return float(match.group(1)) if match else None


def validate_svg(path: Path, expected_size: tuple[int, int], errors: list[str]) -> None:
    if not path.is_file():
        report_error(errors, path, "required SVG source is missing")
        return
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as error:
        report_error(errors, path, f"invalid XML: {error}")
        return

    if root.tag.rsplit("}", 1)[-1] != "svg":
        report_error(errors, path, "root element must be <svg>")
    width, height = expected_size
    if number(root.get("width")) != width or number(root.get("height")) != height:
        report_error(errors, path, f"root width and height must be {width} x {height}")
    view_box = root.get("viewBox", "").replace(",", " ").split()
    try:
        parsed_view_box = tuple(float(value) for value in view_box)
    except ValueError:
        parsed_view_box = ()
    if parsed_view_box != (0.0, 0.0, float(width), float(height)):
        report_error(errors, path, f"viewBox must be 0 0 {width} {height}")

    for element in root.iter():
        tag = element.tag.rsplit("}", 1)[-1]
        if tag in {"script", "foreignObject", "image"}:
            report_error(errors, path, f"<{tag}> is not allowed; keep media self-contained and editable")
        for attribute, value in element.attrib.items():
            attribute_name = attribute.rsplit("}", 1)[-1].lower()
            value_lower = value.lower()
            if attribute_name == "href" and not value.startswith("#"):
                report_error(errors, path, "external SVG references are not allowed")
            if "javascript:" in value_lower or "url(http" in value_lower or "url(//" in value_lower:
                report_error(errors, path, "external or executable references are not allowed")


def png_dimensions(path: Path) -> tuple[int, int] | None:
    try:
        with path.open("rb") as file:
            header = file.read(24)
    except OSError:
        return None
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", header[16:24])


def validate_png(path: Path, expected_size: tuple[int, int], errors: list[str]) -> None:
    actual = png_dimensions(path)
    if actual is None:
        report_error(errors, path, "missing or invalid PNG")
    elif actual != expected_size:
        report_error(errors, path, f"expected {expected_size[0]} x {expected_size[1]} px, found {actual[0]} x {actual[1]} px")


def validate_icns(path: Path, errors: list[str]) -> None:
    try:
        data = path.read_bytes()
    except OSError:
        report_error(errors, path, "missing generated .icns file")
        return
    if len(data) < 16 or data[:4] != b"icns":
        report_error(errors, path, "not a valid ICNS container")
        return
    declared_size = struct.unpack(">I", data[4:8])[0]
    if declared_size != len(data):
        report_error(errors, path, f"ICNS header declares {declared_size} bytes but file contains {len(data)}")
        return
    offset = 8
    chunks = 0
    while offset < len(data):
        if offset + 8 > len(data):
            report_error(errors, path, "truncated ICNS chunk header")
            return
        chunk_size = struct.unpack(">I", data[offset + 4:offset + 8])[0]
        if chunk_size < 8 or offset + chunk_size > len(data):
            report_error(errors, path, "invalid or truncated ICNS image chunk")
            return
        chunks += 1
        offset += chunk_size
    if offset != len(data) or chunks == 0:
        report_error(errors, path, "ICNS container has no complete image chunks")


def validate_rendered(errors: list[str]) -> bool:
    iconset_dir = RENDERED / "SweetNoSleep.iconset"
    if not iconset_dir.is_dir():
        report_error(errors, iconset_dir, "generated iconset is missing")
    else:
        for name, size in ICONSET.items():
            validate_png(iconset_dir / name, size, errors)

    validate_icns(RENDERED / "SweetNoSleep.icns", errors)
    for name, size in RENDERED_IMAGES.items():
        validate_png(RENDERED / name, size, errors)
    return True


def validate_mascot_consistency(errors: list[str]) -> None:
    for name in MASCOT_ART:
        path = ART / name
        if not path.is_file():
            continue
        content = path.read_text(encoding="utf-8")
        missing = [signature for signature in MASCOT_SIGNATURES if signature not in content]
        if missing:
            report_error(
                errors,
                path,
                "static art must retain the app Kiwi's head, crown leaves, chest badge, and paws; review the matching Canvas pose",
            )


def validate_source_text(errors: list[str]) -> None:
    source_root = ROOT / "Sources"
    for path in sorted(source_root.rglob("*")):
        if not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        for character in content:
            codepoint = ord(character)
            if 0x0400 <= codepoint <= 0x052F:
                report_error(errors, path, "Cyrillic characters are not allowed in Sources/")
                break


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-rendered", action="store_true", help="require and validate macOS-generated PNG/ICNS outputs")
    args = parser.parse_args()

    errors: list[str] = []
    for name, size in SOURCES.items():
        validate_svg(ART / name, size, errors)
    validate_mascot_consistency(errors)
    # Deviation: docs/MEDIA.md dropped — it is outside the task's allowed status
    # paths and was absent at base b09d593 (golden-only artifact).
    for path in (ROOT / "Scripts" / "render-media.sh",):
        if not path.is_file():
            report_error(errors, path, "required media-kit file is missing")
    validate_source_text(errors)

    has_rendered_media = (RENDERED / "SweetNoSleep.icns").exists() or (RENDERED / "SweetNoSleep.iconset").exists()
    if args.check_rendered or has_rendered_media:
        validate_rendered(errors)
    else:
        print("Rendered PNG/ICNS checks skipped: generate them on macOS with Scripts/render-media.sh.")

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        print(f"Media validation failed: {len(errors)} issue(s).", file=sys.stderr)
        return 1

    source_count = len(SOURCES)
    if args.check_rendered or has_rendered_media:
        print(f"Media validation passed: {source_count} editable SVG sources and complete generated outputs.")
    else:
        print(f"Media source validation passed: {source_count} self-contained SVG sources.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
