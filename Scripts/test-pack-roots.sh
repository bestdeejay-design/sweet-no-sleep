#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Headless: only the resolver and the test are compiled, so no window server or
# AppKit state is needed. The assembled app is checked by verify-pack-roots.py.
swiftc \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT_DIR/Sources/SweetNoSleep/PetPackRoots.swift" \
  "$ROOT_DIR/Scripts/test-pack-roots.swift" \
  -framework Foundation \
  -o "$TEMP_DIR/test-pack-roots"

"$TEMP_DIR/test-pack-roots"
