#!/usr/bin/env bash
# English is the source language. Translations are generated through the configured
# DeepL/Crowdin workflow; never edit generated locale entries by hand.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$ROOT_DIR/Sources/SweetNoSleep/Localizable.xcstrings"

if [[ ! -f "$CATALOG" ]]; then
  echo "Missing English source catalog: $CATALOG" >&2
  exit 1
fi

if command -v crowdin >/dev/null 2>&1 && [[ -n "${CROWDIN_CONFIG:-}" && -f "$CROWDIN_CONFIG" ]]; then
  crowdin upload sources --config "$CROWDIN_CONFIG"
  crowdin download --config "$CROWDIN_CONFIG"
  exit 0
fi

cat <<'MESSAGE'
English source catalog is ready. No translation provider is configured in this checkout.
Configure DeepL or Crowdin credentials and provider config in the CI secret store, then
run this script there. Generated translations must not be hand-edited.
MESSAGE
