#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

for script in Scripts/*.sh; do
  bash -n "$script"
done
printf 'Shell syntax checks passed.\n'

python3 -m json.tool Sources/SweetNoSleep/Localizable.xcstrings >/dev/null
python3 Scripts/validate-localization.py
python3 Scripts/validate-skins.py
python3 Scripts/verify-media.py
Scripts/test-agent-hooks.sh

# Sources must stay English: no Cyrillic text anywhere in Sources/. Done in
# Python because BSD grep on macOS has no -P and a byte-range pattern would
# depend on the locale.
python3 - <<'PY'
import pathlib
import sys

offenders = []
for path in sorted(pathlib.Path("Sources").rglob("*")):
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        continue
    if any(0x0400 <= ord(character) <= 0x04FF for character in text):
        offenders.append(str(path))

if offenders:
    print("Cyrillic text found in Sources/: " + ", ".join(offenders), file=sys.stderr)
    raise SystemExit(1)
print("Sources contain no Cyrillic text.")
PY

if [[ "${SWEET_NO_SLEEP_SKIP_SWIFT_BUILD:-0}" == "1" ]]; then
  printf 'SKIP Swift build: explicitly skipped for split CI diagnostics.\n'
elif [[ "$(uname -s)" == "Darwin" ]] && command -v swift >/dev/null 2>&1; then
  swift build --package-path "$ROOT_DIR" --configuration debug
  Scripts/test-panel-wander.sh
else
  printf 'SKIP Swift build: it requires macOS with Swift 5.9+ and the macOS 14 SDK.\n'
fi
