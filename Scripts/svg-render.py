#!/usr/bin/env python3
"""Rasterize one SVG file to PNG.

Used by Scripts/render-media.sh when no command-line rasterizer is installed
(Linux workstations and CI without librsvg). macOS release builds use the stock
tools instead, so this helper is optional: it exits with code 3 and a readable
message when no Python renderer is available.

Supported backends: cairosvg, resvg_py (install with
`pip3 install --user cairosvg` or `pip3 install --user resvg-py`).
"""
from __future__ import annotations

import argparse
import pathlib
import sys


def load_backend():
    try:
        import cairosvg  # type: ignore

        def render(source: str, width: int, height: int) -> bytes:
            return cairosvg.svg2png(bytestring=source.encode("utf-8"), output_width=width, output_height=height)

        return "cairosvg", render
    except Exception:
        pass

    try:
        import resvg_py  # type: ignore

        def render(source: str, width: int, height: int) -> bytes:
            return bytes(resvg_py.svg_to_bytes(svg_string=source, width=width, height=height))

        return "resvg", render
    except Exception:
        pass

    return None, None


def main() -> int:
    parser = argparse.ArgumentParser(description="Rasterize an SVG file to PNG at an exact pixel size.")
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("width", type=int)
    parser.add_argument("height", type=int)
    arguments = parser.parse_args()

    if not arguments.source.is_file():
        print(f"Missing SVG source: {arguments.source}", file=sys.stderr)
        return 2

    name, render = load_backend()
    if render is None:
        print(
            "No Python SVG renderer found. Install cairosvg or resvg-py, or install "
            "librsvg for the rsvg-convert command-line tool.",
            file=sys.stderr,
        )
        return 3

    png = render(arguments.source.read_text(encoding="utf-8"), arguments.width, arguments.height)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(png)
    print(f"{arguments.output.name}: {arguments.width}x{arguments.height} px via {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
