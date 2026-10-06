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
Scripts/test-agent-hooks.sh

if [[ "$(uname -s)" == "Darwin" ]] && command -v swift >/dev/null 2>&1; then
  swift build --package-path "$ROOT_DIR" --configuration debug
else
  printf 'SKIP Swift build: it requires macOS with Swift 5.9+ and the macOS 14 SDK.\n'
fi
