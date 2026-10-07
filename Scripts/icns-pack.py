#!/usr/bin/env python3
"""Pack an .iconset directory into an .icns file.

macOS release builds use the stock `iconutil` command instead; this fallback
exists so Linux workstations and non-macOS CI still produce a real, valid icon
file from the same PNGs. The container format is documented in Apple's
"Container Reference": the file is the `icns` magic, the total byte length, then
one element per size made of an OSType, the element length, and PNG data.
"""
from __future__ import annotations

import argparse
import pathlib
import struct
import sys

# iconset file name -> OSType in the packed file.
ELEMENTS: list[tuple[str, bytes, int]] = [
    ("icon_16x16.png", b"icp4", 16),
    ("icon_16x16@2x.png", b"ic11", 32),
    ("icon_32x32.png", b"icp5", 32),
    ("icon_32x32@2x.png", b"ic12", 64),
    ("icon_128x128.png", b"ic07", 128),
    ("icon_128x128@2x.png", b"ic13", 256),
    ("icon_256x256.png", b"ic08", 256),
    ("icon_256x256@2x.png", b"ic14", 512),
    ("icon_512x512.png", b"ic09", 512),
    ("icon_512x512@2x.png", b"ic10", 1024),
]


def png_size(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG image")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def main() -> int:
    parser = argparse.ArgumentParser(description="Pack an .iconset directory into an .icns file.")
    parser.add_argument("iconset", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    arguments = parser.parse_args()

    if not arguments.iconset.is_dir():
        print(f"Missing iconset directory: {arguments.iconset}", file=sys.stderr)
        return 2

    payloads: list[tuple[bytes, bytes]] = []
    for name, ostype, expected in ELEMENTS:
        path = arguments.iconset / name
        if not path.is_file():
            continue
        data = path.read_bytes()
        width, height = png_size(data)
        if width != expected or height != expected:
            print(f"{name} is {width}x{height} px, expected {expected}x{expected}", file=sys.stderr)
            return 1
        payloads.append((ostype, data))

    if not payloads:
        print(f"No iconset PNGs found in {arguments.iconset}", file=sys.stderr)
        return 1

    body = bytearray()
    for ostype, data in payloads:
        body += ostype + struct.pack(">I", len(data) + 8) + data

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + bytes(body))
    print(f"{arguments.output.name}: {len(payloads)} sizes packed into {len(body) + 8} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
