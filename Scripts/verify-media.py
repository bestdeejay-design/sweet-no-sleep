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

# .icns element type -> required pixel size. Every type must be packed.
ICNS_ELEMENTS = {
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


def png_size(path: pathlib.Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("not a PNG file")
    return struct.unpack(">II", header[16:24])


def icns_elements(path: pathlib.Path) -> dict[bytes, int]:
    data = path.read_bytes()
    if data[:4] != b"icns":
        raise ValueError("missing icns magic")
    declared = struct.unpack(">I", data[4:8])[0]
    if declared != len(data):
        raise ValueError(f"declared length {declared} does not match file length {len(data)}")
    elements: dict[bytes, int] = {}
    offset = 8
    while offset + 8 <= len(data):
        ostype = data[offset : offset + 4]
        length = struct.unpack(">I", data[offset + 4 : offset + 8])[0]
        if length < 8 or offset + length > len(data):
            raise ValueError(f"element {ostype!r} has an invalid length {length}")
        if ostype in ICNS_ELEMENTS and data[offset + 8 : offset + 16] == b"\x89PNG\r\n\x1a\n":
            # 8 byte element header, 8 byte PNG signature, then the IHDR chunk:
            # 4 byte length, "IHDR", and the width/height pair.
            width, height = struct.unpack(">II", data[offset + 24 : offset + 32])
            if width != height:
                raise ValueError(f"element {ostype!r} is not square ({width}x{height})")
            elements[ostype] = width
        offset += length
    return elements


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
                packed = icns_elements(icns_path)
            except (OSError, ValueError) as error:
                errors.append(f"Resources/Media/SweetNoSleep.icns is invalid: {error}")
                packed = {}
            for ostype, size in sorted(ICNS_ELEMENTS.items(), key=lambda item: item[1]):
                if ostype not in packed:
                    errors.append(f"SweetNoSleep.icns is missing the {size} px element")
                elif packed[ostype] != size:
                    errors.append(
                        f"SweetNoSleep.icns element for {size} px contains {packed[ostype]} px art"
                    )

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(
        f"Media check passed: {len(SOURCES)} SVG sources and {len(RENDERS) + 1} renders verified."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
