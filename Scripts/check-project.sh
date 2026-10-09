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
python3 Scripts/compile-localizations.py --self-test
# Real NSLocalizedString lookups through Bundle.module; needs the assembled app,
# so it skips until Scripts/build-app.sh has run (macOS only).
python3 Scripts/verify-localizations.py "dist/Sweet No Sleep — Kiwi Cat.app"
if [[ "$(uname -s)" == "Darwin" ]]; then
  Scripts/render-media.sh
  python3 Scripts/validate-media.py --check-rendered
else
  python3 Scripts/validate-media.py
fi
python3 Scripts/validate-skins.py
if python3 -c 'import PIL, numpy' >/dev/null 2>&1; then
  python3 Scripts/prepare-character-assets.py --check
  # Verifies the committed transparent animation loops; skips if they were
  # never rendered (Scripts/render-character-animations.py).
  python3 Scripts/render-character-animations.py --check
else
  printf 'SKIP character layer check: Pillow and NumPy are not installed.\n'
fi
Scripts/test-agent-hooks.sh
python3 Scripts/test-webhook-auth.py
python3 Scripts/test-mcp-server.py

if [[ "${SWEET_NO_SLEEP_SKIP_SWIFT_BUILD:-0}" == "1" ]]; then
  printf 'SKIP Swift build: explicitly skipped for split CI diagnostics.\n'
elif [[ "$(uname -s)" == "Darwin" ]] && command -v swift >/dev/null 2>&1; then
  swift build --package-path "$ROOT_DIR" --configuration debug
  Scripts/test-panel-wander.sh
else
  printf 'SKIP Swift build: it requires macOS with Swift 5.9+ and the macOS 14 SDK.\n'
fi
