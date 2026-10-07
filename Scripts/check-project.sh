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

# Sources must stay ASCII English: no Cyrillic text anywhere in Sources/.
if grep -rlP '[\x{0400}-\x{04FF}]' Sources >/dev/null 2>&1; then
  printf 'Cyrillic text found in Sources/:\n' >&2
  grep -rlP '[\x{0400}-\x{04FF}]' Sources >&2
  exit 1
fi
printf 'Sources contain no Cyrillic text.\n'

if [[ "${SWEET_NO_SLEEP_SKIP_SWIFT_BUILD:-0}" == "1" ]]; then
  printf 'SKIP Swift build: explicitly skipped for split CI diagnostics.\n'
elif [[ "$(uname -s)" == "Darwin" ]] && command -v swift >/dev/null 2>&1; then
  swift build --package-path "$ROOT_DIR" --configuration debug
  Scripts/test-panel-wander.sh
else
  printf 'SKIP Swift build: it requires macOS with Swift 5.9+ and the macOS 14 SDK.\n'
fi
