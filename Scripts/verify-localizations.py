#!/usr/bin/env python3
"""Verify that every shipped locale really loads at runtime in the assembled app.

Table presence is not enough: the CFBundle strings loader silently rejects a
`Localizable.strings` it cannot parse and `NSLocalizedString` then returns the
English key. So this script asks the app itself to resolve the strings, by
running the menu-bar binary with `--localization-report`, and compares the
results against `Localizable.xcstrings`.

Each locale gets its own scratch bundle: a copy of the shipped
`<locale>.lproj/Localizable.strings` in a bundle that carries only that locale
and declares it as its development region. CFBundle has no choice there, so the
lookup is deterministic - the CI answer does not depend on the machine's
language list, which CFBundle may read from a preferences domain a test process
cannot influence. The same run also reports the facts about `Bundle.module`
itself (is the locale discovered, does its table resolve, does it parse), so a
placement problem is still caught.

Requires the assembled app bundle, so it only runs on macOS (or wherever the
bundle was built). It skips with a message when the bundle is absent, so
`Scripts/check-project.sh` can call it on any platform.

Usage:
    verify-localizations.py <app-bundle> [--catalog PATH] [--binary NAME]
"""
from __future__ import annotations

import argparse
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "Sources" / "SweetNoSleep" / "Localizable.xcstrings"
REPORT_FLAG = "--localization-report"
TIMEOUT_SECONDS = 60

# A minimal macOS-style bundle. `CFBundleDevelopmentRegion` is the lever: with
# only one localization present, it is what CFBundle falls back to, so the
# lookup happens in the locale under test no matter what the machine prefers.
SCRATCH_INFO_PLIST = {
    "CFBundleIdentifier": "com.sweetnosleep.localizationcheck",
    "CFBundleName": "LocalizationCheck",
    "CFBundlePackageType": "BNDL",
    "CFBundleInfoDictionaryVersion": "6.0",
}


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


def shipped_table(bundles: list[Path], locale: str) -> Path:
    """The compiled table for `locale` inside the app's own resource bundle."""
    for bundle in bundles:
        candidate = bundle / f"{locale}.lproj" / "Localizable.strings"
        if candidate.is_file():
            return candidate
    fail(f"missing compiled {locale}.lproj/Localizable.strings in the app bundle")


def build_scratch_bundle(root: Path, locale: str, table: Path) -> Path:
    """A bundle whose only localization is `locale`, holding a copy of `table`."""
    bundle = root / f"{locale}.bundle"
    contents = bundle / "Contents"
    target = contents / "Resources" / f"{locale}.lproj"
    target.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(table, target / "Localizable.strings")
    info = dict(SCRATCH_INFO_PLIST)
    info["CFBundleDevelopmentRegion"] = locale
    with (contents / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle, fmt=plistlib.FMT_XML)
    return bundle


def run_report(binary: Path, locale: str, scratch: Path) -> dict:
    try:
        completed = subprocess.run(
            [str(binary), REPORT_FLAG, "--locale", locale, "--bundle", str(scratch), "-AppleLanguages", f"({locale})"],
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


def describe(report: dict, keys: tuple[str, ...]) -> str:
    return ", ".join(f"{key}={report[key]!r}" for key in keys if key in report)


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify that every shipped locale loads at runtime.")
    parser.add_argument("app", type=Path, help="assembled .app bundle")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--binary", default="SweetNoSleep", help="executable name inside Contents/MacOS")
    arguments = parser.parse_args()

    app: Path = arguments.app
    binary = app / "Contents" / "MacOS" / arguments.binary
    if not app.is_dir() or not binary.is_file():
        print(f"SKIP localization runtime check: {binary} is not built yet.")
        return 0

    tables = catalog_tables(arguments.catalog)
    locales = sorted(tables)
    bundles = resource_bundles(app)
    entries = len(next(iter(tables.values())))

    with tempfile.TemporaryDirectory(prefix="sns-localizations-") as temporary:
        root = Path(temporary)
        for locale in locales:
            expected = tables[locale]
            scratch = build_scratch_bundle(root, locale, shipped_table(bundles, locale))
            report = run_report(binary, locale, scratch)

            # 1. The deterministic gate: the strings loader has to agree with
            #    the catalog for the bytes that ship.
            preferred = str(report.get("preferred", "")).split(",")
            if preferred[:1] != [locale]:
                fail(
                    f"{locale}: the scratch bundle resolved to {preferred!r} instead of [{locale!r}]. "
                    f"Scratch bundle: {describe(report, ('bundle', 'available', 'development', 'table', 'dictionary'))}"
                )
            values: dict[str, str] = report["values"]
            missing = sorted(set(expected) - set(values))
            if missing:
                fail(f"{locale}: the app resolved no value for {len(missing)} key(s), e.g. {missing[:3]}")
            wrong = sorted(key for key in expected if values.get(key) != expected[key])
            if wrong:
                sample = " | ".join(
                    f"{key} -> {values.get(key)!r} (expected {expected[key]!r})" for key in wrong[:3]
                )
                fail(
                    f"{locale}: {len(wrong)}/{len(expected)} keys fell back to English. First: {sample}. "
                    f"Scratch bundle: {describe(report, ('bundle', 'table', 'dictionary'))}"
                )

            # 2. The placement gate: the app's own resource bundle has to
            #    discover the locale and resolve a table that parses.
            available = str(report.get("moduleAvailable", "")).split(",")
            if locale not in available:
                fail(f"{locale}: Bundle.module does not offer it. {describe(report, ('modulePath', 'moduleAvailable'))}")
            if not report.get("moduleTable"):
                fail(f"{locale}: Bundle.module resolves no table. {describe(report, ('modulePath', 'moduleAvailable'))}")
            if int(report.get("moduleDictionary", "0")) != entries:
                fail(
                    f"{locale}: Bundle.module table has {report.get('moduleDictionary')} entries, "
                    f"expected {entries}. {describe(report, ('modulePath', 'moduleTable'))}"
                )

            print(
                f"{locale}: {len(expected)} keys resolved at runtime through the CFBundle strings loader; "
                f"Bundle.module offers {len(available)} locales and its table parses to "
                f"{report.get('moduleDictionary')} entries"
            )

    print(
        f"Localization runtime check passed: {len(locales)} locales "
        f"({', '.join(locales)}) resolve all {entries} keys at runtime."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
