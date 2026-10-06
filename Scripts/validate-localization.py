#!/usr/bin/env python3
"""Check English source strings against the SwiftPM string catalog."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "Sources" / "SweetNoSleep"
CATALOG_PATH = SOURCE_DIR / "Localizable.xcstrings"
LOCALIZED_CALL = re.compile(r'L10n\.(?:text|format)\(\s*"((?:[^"\\]|\\.)*)"')


def contains_cyrillic(text: str) -> bool:
    return any(0x0400 <= ord(character) <= 0x04FF for character in text)


def main() -> int:
    try:
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Could not read localization catalog: {error}", file=sys.stderr)
        return 1

    if catalog.get("sourceLanguage") != "en":
        print("Localization catalog sourceLanguage must be 'en'.", file=sys.stderr)
        return 1

    expected: set[str] = set()
    source_errors: list[str] = []
    for path in sorted(SOURCE_DIR.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        if contains_cyrillic(text):
            source_errors.append(f"{path.relative_to(ROOT)} contains Cyrillic characters")
        for match in LOCALIZED_CALL.finditer(text):
            raw_key = match.group(1)
            key = raw_key.replace(r"\n", "\n").replace(r'\"', '"').replace(r"\\", "\\")
            expected.add(key)

    strings = catalog.get("strings", {})
    missing = sorted(expected - strings.keys())
    extra = sorted(strings.keys() - expected)
    invalid_values: list[str] = []
    for key in sorted(expected & strings.keys()):
        entry = strings[key]
        english = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
        if english != key:
            invalid_values.append(key)

    errors = source_errors
    if missing:
        errors.append("Missing catalog keys: " + ", ".join(repr(key) for key in missing))
    if extra:
        errors.append("Unused catalog keys: " + ", ".join(repr(key) for key in extra))
    if invalid_values:
        errors.append("English source values differ from their keys: " + ", ".join(repr(key) for key in invalid_values))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"Localization check passed: {len(expected)} English source keys match the catalog.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
