#!/usr/bin/env python3
"""Verify that every shipped locale really loads at runtime in the assembled app.

Table presence is not enough: the CFBundle strings loader silently rejects a
`Localizable.strings` it cannot parse and `NSLocalizedString` then returns the
English key. So this script asks the app itself - it runs the menu-bar binary
with `--localization-report`, which resolves every catalog key through
`L10n.text` (that is, `NSLocalizedString(key, tableName: nil, bundle: .module,
value: key)`) - and compares the result against `Localizable.xcstrings`.

One process per locale with `-AppleLanguages "(<locale>)"`, which is how macOS
selects a language at launch; a fresh process avoids Foundation's bundle cache
handing the first locale to every later lookup.

Requires the assembled app bundle, so it only runs on macOS (or wherever the
bundle was built). It skips with a message when the bundle is absent, so
`Scripts/check-project.sh` can call it on any platform.

Usage:
    verify-localizations.py <app-bundle> [--catalog PATH] [--binary NAME]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "Sources" / "SweetNoSleep" / "Localizable.xcstrings"
REPORT_FLAG = "--localization-report"
TIMEOUT_SECONDS = 60


def fail(message: str) -> None:
    print(f"::error title=Localization runtime::{message}")
    raise SystemExit(1)


def catalog_tables(catalog_path: Path) -> dict[str, dict[str, str]]:
    if not catalog_path.is_file():
        fail(f"missing source catalog: {catalog_path}")
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    tables: dict[str, dict[str, str]] = {}
    for key, entry in catalog.get("strings", {}).items():
        for locale, localization in entry.get("localizations", {}).items():
            tables.setdefault(locale, {})[key] = localization["stringUnit"]["value"]
    if not tables:
        fail(f"{catalog_path} declares no localized strings")
    return tables


def resource_bundles(app: Path) -> list[Path]:
    resources = app / "Contents" / "Resources"
    bundles = sorted(path for path in resources.glob("*.bundle") if path.is_dir())
    if not bundles:
        listing = " | ".join(str(path.relative_to(resources)) for path in sorted(resources.rglob("*")))[:2000]
        fail(f"no SwiftPM resource bundle in {resources}. Contents: {listing}")
    return bundles


def check_tables(bundles: list[Path], locales: list[str]) -> None:
    """Cheap structural gate: every locale ships a table inside the bundle."""
    for locale in locales:
        tables = [bundle for bundle in bundles if (bundle / f"{locale}.lproj" / "Localizable.strings").is_file()]
        if not tables:
            fail(f"missing compiled {locale}.lproj/Localizable.strings in the app bundle")


def run_report(binary: Path, locale: str) -> dict:
    try:
        completed = subprocess.run(
            [str(binary), REPORT_FLAG, "-AppleLanguages", f"({locale})"],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        fail(f"{locale}: {binary.name} {REPORT_FLAG} timed out after {TIMEOUT_SECONDS}s")
    if completed.returncode != 0:
        fail(f"{locale}: {binary.name} {REPORT_FLAG} exited {completed.returncode}: {completed.stderr.strip()}")
    try:
        report = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        fail(f"{locale}: could not parse the report ({error}): {completed.stdout[:400]!r}")
    if not isinstance(report, dict) or not isinstance(report.get("values"), dict):
        fail(f"{locale}: unexpected report shape: {completed.stdout[:400]!r}")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="assembled .app bundle")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--binary", default="SweetNoSleep", help="executable name inside Contents/MacOS")
    arguments = parser.parse_args()

    app: Path = arguments.app
    binary = app / "Contents" / "MacOS" / arguments.binary
    if not app.is_dir() or not binary.is_executable():
        print(f"SKIP localization runtime check: {binary} is not built yet.")
        return 0

    tables = catalog_tables(arguments.catalog)
    locales = sorted(tables)
    bundles = resource_bundles(app)
    check_tables(bundles, locales)

    for locale in locales:
        expected = tables[locale]
        report = run_report(binary, locale)
        values: dict[str, str] = report["values"]

        missing = sorted(set(expected) - set(values))
        if missing:
            fail(f"{locale}: the app resolved no value for {len(missing)} key(s), e.g. {missing[:3]}")
        wrong = sorted(key for key in expected if values.get(key) != expected[key])
        if wrong:
            sample = wrong[0]
            fail(
                f"{locale}: {len(wrong)}/{len(expected)} keys fell back to English, "
                f"e.g. {sample!r} resolved to {values.get(sample)!r}, expected {expected[sample]!r}"
            )
        preferred = report.get("preferred") or ["?"]
        print(
            f"{locale}: {len(expected)} keys resolved at runtime through Bundle.module "
            f"(preferred: {', '.join(preferred)})"
        )

    print(
        f"Localization runtime check passed: {len(locales)} locales "
        f"({', '.join(locales)}) resolve all {len(next(iter(tables.values())))} keys at runtime."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
