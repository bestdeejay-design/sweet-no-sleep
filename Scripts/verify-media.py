#!/usr/bin/env python3
"""Verify the art sources and the rendered media catalog.

Runs on Linux and macOS without external tools: PNG headers are read directly and
the .icns container is parsed by hand. Used by Scripts/check-project.sh, so a
missing source, a wrong raster size, or an incomplete icon set fails the build.
"""
from __future__ import annotations

import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
ART = ROOT / "Resources" / "Art"
MEDIA = ROOT / "Resources" / "Media"

# SVG sources this pack owns. Everything in Resources/Media is rebuilt from them.
SOURCES = [
    "app-icon.svg",
    "menubar-awake.svg",
    "menubar-asleep.svg",
    "preview-kiwi.svg",
    "preview-moonlight.svg",
    "preview-strawberry.svg",
    "banner.svg",
    "og-image.svg",
]

# Rendered PNGs and their exact pixel sizes.
RENDERS = {
    "menubar-awake.png": (22, 22),
    "menubar-awake@2x.png": (44, 44),
    "menubar-asleep.png": (22, 22),
    "menubar-asleep@2x.png": (44, 44),
    "preview-kiwi.png": (104, 52),
    "preview-kiwi@2x.png": (208, 104),
    "preview-moonlight.png": (104, 52),
    "preview-moonlight@2x.png": (208, 104),
    "preview-strawberry.png": (104, 52),
    "preview-strawberry@2x.png": (208, 104),
    "banner.png": (1280, 640),
    "og-image.png": (1200, 630),
}

# .icns element type -> pixel size it carries. PNG based types are the modern
# set that iconutil and icns-pack.py write; the raw types are the legacy
# uncompressed elements iconutil still emits for the smallest icons.
ICNS_PNG_ELEMENTS = {
    b"icp4": 16,
    b"ic11": 32,
    b"icp5": 32,
    b"ic12": 64,
    b"ic07": 128,
    b"ic13": 256,
    b"ic08": 256,
    b"ic14": 512,
    b"ic09": 512,
    b"ic10": 1024,
}
ICNS_RAW_ELEMENTS = {
    b"is32": 16,
    b"il32": 32,
    b"ih32": 48,
    b"it32": 128,
    b"ic04": 16,
    b"ic05": 32,
}
# Companion mask elements; they carry no size requirement of their own.
ICNS_MASK_ELEMENTS = {b"s8mk", b"l8mk", b"h8mk", b"t8mk", b"TOC "}
REQUIRED_ICON_SIZES = (16, 32, 64, 128, 256, 512, 1024)


def png_size(path: pathlib.Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("not a PNG file")
    return struct.unpack(">II", header[16:24])


def icns_sizes(path: pathlib.Path) -> tuple[set[int], set[int], list[str]]:
    """Return (PNG verified sizes, raw element sizes, element inventory).

    PNG elements are measured from their IHDR chunk; legacy raw elements are
    accepted at the size their type declares, with the payload length used as a
    sanity check. The inventory is reported so a failure explains itself.
    """
    data = path.read_bytes()
    if data[:4] != b"icns":
        raise ValueError("missing icns magic")
    declared = struct.unpack(">I", data[4:8])[0]
    if declared != len(data):
        raise ValueError(f"declared length {declared} does not match file length {len(data)}")

    png_sizes: set[int] = set()
    raw_sizes: set[int] = set()
    inventory: list[str] = []
    offset = 8
    while offset + 8 <= len(data):
        ostype = data[offset : offset + 4]
        length = struct.unpack(">I", data[offset + 4 : offset + 8])[0]
        if length < 8 or offset + length > len(data):
            raise ValueError(f"element {ostype!r} has an invalid length {length}")
        payload_length = length - 8
        is_png = data[offset + 8 : offset + 16] == b"\x89PNG\r\n\x1a\n"
        if is_png and ostype in ICNS_PNG_ELEMENTS:
            # 8 byte element header, 8 byte PNG signature, then the IHDR chunk:
            # 4 byte length, "IHDR", and the width/height pair.
            width, height = struct.unpack(">II", data[offset + 24 : offset + 32])
            if width != height:
                raise ValueError(f"element {ostype!r} is not square ({width}x{height})")
            png_sizes.add(width)
            inventory.append(f"{ostype.decode('ascii', 'replace')}={width}px/png")
        elif ostype in ICNS_RAW_ELEMENTS:
            size = ICNS_RAW_ELEMENTS[ostype]
            # Raw elements store 3 or 4 bytes per pixel, optionally behind an
            # 8 byte header, so require at least a 3 byte per pixel payload.
            if payload_length < size * size * 3:
                raise ValueError(
                    f"element {ostype!r} carries {payload_length} bytes, too few for {size} px art"
                )
            raw_sizes.add(size)
            inventory.append(f"{ostype.decode('ascii', 'replace')}={size}px/raw")
        elif ostype in ICNS_MASK_ELEMENTS:
            inventory.append(f"{ostype.decode('ascii', 'replace')}/mask")
        else:
            inventory.append(f"{ostype.decode('ascii', 'replace')}/{payload_length}B")
        offset += length
    return png_sizes, raw_sizes, inventory


def main() -> int:
    errors: list[str] = []

    for name in SOURCES:
        path = ART / name
        if not path.is_file():
            errors.append(f"missing art source: Resources/Art/{name}")
            continue
        text = path.read_text(encoding="utf-8")
        if "<svg" not in text or "</svg>" not in text:
            errors.append(f"Resources/Art/{name} is not a complete SVG document")
        if text.lstrip().startswith("<?xml"):
            errors.append(f"Resources/Art/{name} starts with an XML declaration; renderers expect <svg> first")

    if not MEDIA.is_dir():
        errors.append("missing rendered media directory: Resources/Media (run Scripts/render-media.sh)")
    else:
        for name, expected in sorted(RENDERS.items()):
            path = MEDIA / name
            if not path.is_file():
                errors.append(f"missing render: Resources/Media/{name} (run Scripts/render-media.sh)")
                continue
            try:
                actual = png_size(path)
            except (OSError, ValueError) as error:
                errors.append(f"Resources/Media/{name} is unreadable: {error}")
                continue
            if actual != expected:
                errors.append(
                    f"Resources/Media/{name} is {actual[0]}x{actual[1]} px, expected {expected[0]}x{expected[1]}"
                )

        icns_path = MEDIA / "SweetNoSleep.icns"
        if not icns_path.is_file():
            errors.append("missing app icon: Resources/Media/SweetNoSleep.icns (run Scripts/render-media.sh)")
        else:
            try:
                png_sizes, raw_sizes, inventory = icns_sizes(icns_path)
            except (OSError, ValueError) as error:
                errors.append(f"Resources/Media/SweetNoSleep.icns is invalid: {error}")
                png_sizes, raw_sizes, inventory = set(), set(), []
            covered = png_sizes | raw_sizes
            missing = [size for size in REQUIRED_ICON_SIZES if size not in covered]
            if missing:
                detail = ", ".join(f"{size} px" for size in missing)
                errors.append(
                    "SweetNoSleep.icns is missing art for: "
                    f"{detail} (elements: {' '.join(inventory) or 'none'})"
                )

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(
        f"Media check passed: {len(SOURCES)} SVG sources and {len(RENDERS) + 1} renders verified."
    )
    print(f"SweetNoSleep.icns covers {len(png_sizes | raw_sizes)} sizes ({' '.join(inventory)}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
