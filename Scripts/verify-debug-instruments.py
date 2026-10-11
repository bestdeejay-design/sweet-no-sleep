#!/usr/bin/env python3
"""Checks the hidden debug instruments' mood list against the app's own enum.

    Scripts/verify-debug-instruments.py [path/to/.app | path/to/binary]

`sweetnosleep://debug/mood?list=1` is the enumerable form of `KiwiMood` the
debug instruments publish (`Sources/SweetNoSleep/DebugInstruments.swift`), and
`SweetNoSleep --debug-moods` is its headless twin - the same report runs before
any window exists, so it is safe on CI. This script runs that report and
requires that:

* the app exits 0 and prints one id per line, nothing else;
* the printed ids are exactly the cases of `enum KiwiMood` in
  `Sources/SweetNoSleep/SweetNoSleepModel.swift`, in declaration order, so a
  mood added later cannot silently go missing from the list; and
* every id round-trips through the `mood(for:)` parser's spelling rules
  (lowercased, no separators), and the doc table in `docs/CODE_AUDIT.md`
  mentions each of them.

Without a binary (not built, or not macOS) it skips with exit 0, like
`Scripts/verify-pack-roots.py`.
"""

from __future__ import annotations

import argparse
import pathlib
import platform
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODEL = ROOT / "Sources" / "SweetNoSleep" / "SweetNoSleepModel.swift"
INSTRUMENTS = ROOT / "Sources" / "SweetNoSleep" / "DebugInstruments.swift"
AUDIT = ROOT / "docs" / "CODE_AUDIT.md"
CANDIDATES = (
    pathlib.Path("dist/Sweet No Sleep — Kiwi Cat.app/Contents/MacOS/SweetNoSleep"),
    pathlib.Path(".build/debug/SweetNoSleep"),
    pathlib.Path(".build/release/SweetNoSleep"),
)

ENUM_BLOCK = re.compile(r"enum KiwiMood[^{]*\{(?P<body>.*?)\n\}", re.DOTALL)
ENUM_CASE = re.compile(r"^\s*case\s+([A-Za-z][A-Za-z0-9]*)", re.MULTILINE)


def kiwi_moods() -> list[str]:
    """The `KiwiMood` cases, in declaration order."""
    body = ENUM_BLOCK.search(MODEL.read_text(encoding="utf-8"))
    if body is None:
        raise SystemExit(f"FAIL debug instruments: no `enum KiwiMood` in {MODEL}")
    cases = ENUM_CASE.findall(body.group("body"))
    if not cases:
        raise SystemExit(f"FAIL debug instruments: `enum KiwiMood` in {MODEL} declares no cases")
    return cases


def binary_path(argument: str | None) -> pathlib.Path | None:
    """The binary to run: the given `.app`/binary if it exists, else the build tree."""
    if argument:
        candidate = pathlib.Path(argument)
        if candidate.is_dir() and candidate.suffix == ".app":
            candidate = candidate / "Contents" / "MacOS" / "SweetNoSleep"
        if candidate.is_file():
            return candidate
    for fallback in CANDIDATES:
        path = ROOT / fallback
        if path.is_file():
            return path
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("app", nargs="?", help="assembled .app bundle or built binary")
    parser.add_argument("--require", action="store_true", help="fail instead of skipping")
    args = parser.parse_args()

    # The static side needs no binary: the source list, the parser and the docs
    # must agree on every platform.
    expected = kiwi_moods()
    failures: list[str] = []
    instruments = INSTRUMENTS.read_text(encoding="utf-8")
    for mood in expected:
        if f'case "{mood.lower()}":' not in instruments:
            failures.append(f"`DebugInstruments.mood(for:)` has no case for `{mood}`")
    audit = AUDIT.read_text(encoding="utf-8")
    missing_in_docs = [mood for mood in expected if f"`{mood}`" not in audit]
    if missing_in_docs:
        failures.append(f"docs/CODE_AUDIT.md does not list {missing_in_docs}")

    binary = None if platform.system() != "Darwin" else binary_path(args.app)
    printed: list[str] = []
    if binary is not None:
        completed = subprocess.run(
            [str(binary), "--debug-moods"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
        printed = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
        if completed.returncode != 0:
            failures.append(f"`SweetNoSleep --debug-moods` exited {completed.returncode}: {completed.stderr.strip()}")
        if printed != expected:
            failures.append(
                "the printed ids do not match `KiwiMood` in declaration order: "
                f"printed {printed}, expected {expected}"
            )
        print(f"debug instruments report from {binary.relative_to(ROOT)}:")
        for mood in printed:
            print(f"  {mood}")
    elif not failures and not args.require:
        print(f"Debug instruments sources list {len(expected)} mood ids; run the app for the report.")

    if failures:
        for failure in failures:
            print(f"FAIL debug instruments: {failure}", file=sys.stderr)
        return 1
    if binary is None:
        if args.require:
            return skip_or_fail(
                "no built SweetNoSleep binary (run `swift build` or `Scripts/build-app.sh`)", True
            )
        print("SKIP debug instruments report: no built SweetNoSleep binary on this host.")
        return 0
    print(f"Debug instruments check passed: {len(printed)} mood ids match `KiwiMood`, parser and docs.")
    return 0


def skip_or_fail(message: str, required: bool) -> int:
    if required:
        print(f"FAIL debug instruments: {message}", file=sys.stderr)
        return 1
    print(f"SKIP debug instruments: {message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
