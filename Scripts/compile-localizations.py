#!/usr/bin/env python3
"""Compile Localizable.xcstrings into <locale>.lproj/Localizable.strings inside a resource bundle.

`swift build` (the native SwiftPM backend) copies `.process` resources unchanged, so the
string catalog is not compiled into the per-locale tables that NSLocalizedString reads.
build-app.sh runs this on the copied SwiftPM resource bundle.

Usage: compile-localizations.py <Localizable.xcstrings> <bundle-dir>
"""
from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    catalog_path, bundle_dir = Path(sys.argv[1]), Path(sys.argv[2])
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))

    tables: dict[str, dict[str, str]] = {}
    for key, entry in catalog.get("strings", {}).items():
        for locale, localization in entry.get("localizations", {}).items():
            tables.setdefault(locale, {})[key] = localization["stringUnit"]["value"]

    for locale, table in sorted(tables.items()):
        directory = bundle_dir / f"{locale}.lproj"
        directory.mkdir(parents=True, exist_ok=True)
        with (directory / "Localizable.strings").open("wb") as handle:
            plistlib.dump(table, handle, fmt=plistlib.FMT_BINARY)

    print(f"Compiled {len(tables)} localization tables into {bundle_dir}: {', '.join(sorted(tables))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
