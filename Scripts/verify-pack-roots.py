#!/usr/bin/env python3
"""Checks which pack roots an assembled app resolves (issue #33).

    Scripts/verify-pack-roots.py "dist/Sweet No Sleep — Kiwi Cat.app" [--require]

The app's own `--pack-roots` report is run from this checkout, which is the
condition that used to let a stale `Resources/PetSkins` win. The script then
requires that:

* the app's bundle is the base root and is present;
* a bundled launch consults no repository root and no override root;
* every pack the app loads renders from inside the bundle, or from the user
  folder (the one override allowed by design); and
* every file of a bundled pack is byte-identical to the file in this checkout's
  `Resources/PetSkins` that was baked into the bundle.

It prints the resolved roots and the head.png hash each pack renders, so the
result is visible in the CI log. Without `--require` it skips (exit 0) when
there is no app or the host is not macOS; with `--require` those are failures.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import platform
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO_PACKS = ROOT / "Resources" / "PetSkins"
USER_PACKS = pathlib.Path.home() / "Library/Application Support/SweetNoSleep/PetSkins"
OVERRIDE_VARIABLE = "SWEET_NO_SLEEP_PACK_ROOT"
REPOSITORY_KINDS = {"repository", "override"}


def same_path(a: pathlib.Path | str, b: pathlib.Path | str) -> bool:
    return os.path.realpath(a) == os.path.realpath(b)


def inside(path: pathlib.Path | str, folder: pathlib.Path) -> bool:
    real = os.path.realpath(path)
    base = os.path.realpath(folder)
    return real == base or real.startswith(base + os.sep)


def sha12(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12] if path.is_file() else "-"


def skip_or_fail(message: str, required: bool) -> int:
    if required:
        print(f"FAIL pack roots: {message}")
        return 1
    print(f"SKIP pack roots: {message}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("app", help="path to the assembled .app bundle")
    parser.add_argument("--require", action="store_true", help="fail instead of skipping")
    args = parser.parse_args()

    app = pathlib.Path(args.app)
    binary = app / "Contents" / "MacOS" / "SweetNoSleep"
    if platform.system() != "Darwin":
        return skip_or_fail("the app only runs on macOS", args.require)
    if not binary.is_file():
        return skip_or_fail(f"no app bundle at {app}", args.require)

    bundle_packs = app / "Contents" / "Resources" / "PetSkins"
    # Run from this checkout, with no opt-in in the environment: this is the
    # condition under which an ancestor's stale packs used to win.
    env = {k: v for k, v in os.environ.items() if k != OVERRIDE_VARIABLE}
    completed = subprocess.run(
        [str(binary), "--pack-roots"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )

    failures: list[str] = []
    if completed.returncode != 0:
        failures.append(f"`SweetNoSleep --pack-roots` exited {completed.returncode}: {completed.stderr.strip()}")

    roots: list[tuple[str, pathlib.Path, str]] = []
    packs: list[tuple[str, pathlib.Path]] = []
    for line in completed.stdout.splitlines():
        fields = line.split("\t")
        if fields[0] == "root" and len(fields) == 4:
            roots.append((fields[1], pathlib.Path(fields[2]), fields[3]))
        elif fields[0] == "pack" and len(fields) == 3:
            packs.append((fields[1], pathlib.Path(fields[2])))

    print("pack roots resolved by the app (SweetNoSleep --pack-roots, run from this checkout):")
    for kind, path, state in roots:
        print(f"  {kind:<10} {state:<8} {path}")

    bundle_roots = [r for r in roots if r[0] == "bundle"]
    if len(bundle_roots) != 1 or not same_path(bundle_roots[0][1], bundle_packs):
        failures.append(f"the bundle root is not the app's own PetSkins ({bundle_packs})")
    elif bundle_roots[0][2] != "present":
        failures.append("the app's own PetSkins folder is absent")
    for kind, path, _ in roots:
        if kind in REPOSITORY_KINDS:
            failures.append(f"a bundled launch consulted a {kind} root: {path}")

    expected = sorted(
        folder.name for folder in REPO_PACKS.iterdir() if (folder / "skin.json").is_file()
    ) if REPO_PACKS.is_dir() else []
    if not expected:
        failures.append(f"no packs found in {REPO_PACKS}")

    print("packs and the head.png each one renders:")
    loaded = {pack_id: folder for pack_id, folder in packs}
    for name in expected:
        folder = loaded.get(name)
        if folder is None:
            failures.append(f"pack {name} did not load")
            print(f"  {name:<24} -            (not loaded)")
            continue
        print(f"  {name:<24} {sha12(folder / 'head.png'):<12} {folder}")

        if inside(folder, bundle_packs):
            for source in sorted((REPO_PACKS / name).iterdir()):
                if not source.is_file():
                    continue
                baked = folder / source.name
                if not baked.is_file() or baked.read_bytes() != source.read_bytes():
                    failures.append(f"{name}/{source.name} in the bundle differs from Resources/PetSkins")
        elif inside(folder, USER_PACKS):
            print(f"    note: {name} is replaced by a user pack; bundled bytes are not compared")
        else:
            failures.append(f"pack {name} renders from outside the bundle: {folder}")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        print("VERDICT: REJECT - the app would not render the packs baked into it")
        return 1
    print(f"PASS: the app renders {len(expected)} bundled pack(s) from its own bundle, byte-identical to Resources/PetSkins")
    return 0


if __name__ == "__main__":
    sys.exit(main())
