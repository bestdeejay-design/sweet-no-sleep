#!/usr/bin/env python3
"""Validate hand-authored SVG media and the macOS-rendered release assets.

The checks encode the final media pack decision from issue #5:
  1. app-icon.svg is the golden build's Kiwi cat icon, kept byte-identical;
  2. the menu bar keeps the SF Symbol (see validate_menu_bar_symbol);
  3. skin previews are the adopted pack-leaf live-pet sources;
  4. banner.svg is the pack-cat base with the golden cat at the agreed transform;
  5. og-image.svg is the pack-leaf base with the mini app icon at the agreed transform.
"""
from __future__ import annotations

import argparse
import hashlib
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

# The approved golden build's app icon, byte-for-byte.
GOLDEN_APP_ICON_SHA256 = "14092e2f9e0da5c7848fb8fac0794fc6b3cdd91b7874ebb675a84f1d4be07449"

# The golden build's bundled reserve menu-bar PNGs, byte-for-byte ("leave them
# untouched": sips re-renders of the pinned menubar sources are deterministic).
GOLDEN_MENUBAR_SHA256 = {
    "menubar-awake.png": "ec3b5ef42f338d5179501edebf8be993b254414c34f0115d03dd41de5eb7fda1",
    "menubar-awake@2x.png": "ba3277a898f7f21af53d64f24ab629ce314a39f65a8ad4a307ac502506cf917f",
    "menubar-asleep.png": "c71747eff8810eb2af882445aaf78cabb63266186e7b93a997579d28e0b284d0",
    "menubar-asleep@2x.png": "9f80defb74765a4fac2e1731e7576e025151c3f2453cbef44cf9008a6d614d0f",
}

# Live-pet pose signatures shared by the Canvas drawing and the adopted art.
MASCOT_ART = (
    "preview-kiwi.svg",
    "preview-moonlight.svg",
    "preview-strawberry.svg",
    "og-image.svg",
)
MASCOT_SIGNATURES = (
    "M-76 44 C-100 15 -98 -12 -88 -33 L-84 -102",
    "M0 -76 Q-12.9 -88 -17 -100",
    'circle cx="0" cy="40" r="20.5"',
    'ellipse cx="30" cy="80" rx="20" ry="10"',
)

# Composition anchors from the final decision.
BANNER_CAT_TRANSFORM = "translate(707.1 88.7) scale(0.49)"
OG_MINI_ICON_TRANSFORM = "translate(67 65) scale(0.04296875)"
GOLDEN_CAT_HEAD = "M-76 44 C-100 15 -98 -12 -88 -33 L-84 -102"


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


def validate_rendered(errors: list[str]) -> None:
    iconset_dir = RENDERED / "SweetNoSleep.iconset"
    if not iconset_dir.is_dir():
        report_error(errors, iconset_dir, "generated iconset is missing")
    else:
        for name, size in ICONSET.items():
            validate_png(iconset_dir / name, size, errors)

    validate_icns(RENDERED / "SweetNoSleep.icns", errors)
    for name, size in RENDERED_IMAGES.items():
        validate_png(RENDERED / name, size, errors)


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
                "live-pet illustrations must retain the Kiwi's head, crown leaves, chest badge, and paws; review the matching Canvas pose",
            )


def validate_golden_app_icon(errors: list[str]) -> None:
    """Decision 1: the app icon is the golden build's Kiwi cat, byte-identical."""
    path = ART / "app-icon.svg"
    if not path.is_file():
        return  # Already reported as a missing source.
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != GOLDEN_APP_ICON_SHA256:
        report_error(
            errors,
            path,
            "app icon must stay byte-identical to the approved golden build's icon "
            f"(expected sha256 {GOLDEN_APP_ICON_SHA256[:12]}..., found {digest[:12]}...)",
        )


def validate_menu_bar_symbol(errors: list[str]) -> None:
    """Decision 2: the menu bar keeps the SF Symbol; bundled menubar PNGs are reserve."""
    app_source = ROOT / "Sources" / "SweetNoSleep" / "SweetNoSleepApp.swift"
    if app_source.is_file():
        content = app_source.read_text(encoding="utf-8")
        if 'systemImage: "leaf.fill"' not in content:
            report_error(errors, app_source, 'the menu bar must keep MenuBarExtra(systemImage: "leaf.fill")')
    sources_root = ROOT / "Sources"
    if sources_root.is_dir():
        for path in sorted(sources_root.rglob("*.swift")):
            try:
                content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            if "menuBarIcon" in content:
                report_error(errors, path, "menu-bar PNGs are reserve assets; Sources/ must not load them")


def validate_template_menubar(errors: list[str]) -> None:
    """Bundled reserve menu-bar art keeps the original template rules."""
    for state in ("awake", "asleep"):
        path = ART / f"menubar-{state}.svg"
        if not path.is_file():
            continue
        try:
            root = ET.parse(path).getroot()
        except (ET.ParseError, OSError):
            continue
        colors = {
            value.lower()
            for element in root.iter()
            for attribute, value in element.attrib.items()
            if attribute.rsplit("}", 1)[-1] in {"fill", "stroke"}
        }
        if colors - {"none", "#000000"}:
            report_error(errors, path, "menu-bar template art must use only transparent and pure black paths")
        widths = [
            number(element.get("stroke-width"))
            for element in root.iter()
            if element.get("stroke-width") is not None
        ]
        if any(width is None or width < 0.75 or width > 1.35 for width in widths):
            report_error(errors, path, "menu-bar template strokes must stay close to 1 px")


def validate_golden_menubar_renders(errors: list[str]) -> None:
    """The reserve menu-bar PNGs stay byte-identical to the golden build's."""
    for name, expected in GOLDEN_MENUBAR_SHA256.items():
        path = RENDERED / name
        if not path.is_file():
            continue  # Reported by validate_rendered when outputs are required.
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != expected:
            report_error(
                errors,
                path,
                "reserve menu-bar render must stay byte-identical to the golden build "
                f"(expected sha256 {expected[:12]}..., found {digest[:12]}...)",
            )


def validate_banner_composition(errors: list[str]) -> None:
    """Decision 4: pack-cat base with the golden cat at the agreed transform."""
    path = ART / "banner.svg"
    if not path.is_file():
        return
    content = path.read_text(encoding="utf-8")
    if BANNER_CAT_TRANSFORM not in content:
        report_error(errors, path, f"banner must place the golden cat with transform {BANNER_CAT_TRANSFORM}")
    if GOLDEN_CAT_HEAD not in content:
        report_error(errors, path, "banner must carry the golden build's cat (app-icon.svg pose), not a face-only mark")
    if 'x="836" y="76" width="182"' not in content:
        report_error(errors, path, "banner must keep the pack-cat base layout (ON DUTY pill moved out of place or removed)")


def validate_og_composition(errors: list[str]) -> None:
    """Decision 5: pack-leaf base with the mini app icon (rounded rect + cat)."""
    path = ART / "og-image.svg"
    if not path.is_file():
        return
    content = path.read_text(encoding="utf-8")
    if OG_MINI_ICON_TRANSFORM not in content:
        report_error(errors, path, f"og image must place the mini app icon with transform {OG_MINI_ICON_TRANSFORM}")
    if '<rect width="1024" height="1024" rx="228"' not in content or "url(#golden-bg)" not in content:
        report_error(errors, path, "og image mini icon must contain the rounded card from app-icon.svg")
    if GOLDEN_CAT_HEAD not in content:
        report_error(errors, path, "og image mini icon must contain the golden build's cat")


def validate_source_text(errors: list[str]) -> None:
    source_root = ROOT / "Sources"
    for path in sorted(source_root.rglob("*")):
        if not path.is_file():
            continue
        if path.name == "Localizable.xcstrings":
            # Translations live in the string catalog by design; code must stay Cyrillic-free.
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
    validate_golden_app_icon(errors)
    validate_menu_bar_symbol(errors)
    validate_template_menubar(errors)
    validate_mascot_consistency(errors)
    validate_banner_composition(errors)
    validate_og_composition(errors)
    for path in (ROOT / "docs" / "MEDIA.md", ROOT / "Scripts" / "render-media.sh"):
        if not path.is_file():
            report_error(errors, path, "required media-kit file is missing")
    validate_source_text(errors)

    has_rendered_media = (RENDERED / "SweetNoSleep.icns").exists() or (RENDERED / "SweetNoSleep.iconset").exists()
    if args.check_rendered or has_rendered_media:
        validate_rendered(errors)
    else:
        print("Rendered PNG/ICNS checks skipped: generate them on macOS with Scripts/render-media.sh.")
    validate_golden_menubar_renders(errors)

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
