#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

swiftc \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT_DIR/Sources/SweetNoSleep/PetPanelLayout.swift" \
  "$ROOT_DIR/Scripts/test-panel-layout.swift" \
  -framework Foundation \
  -o "$TEMP_DIR/test-panel-layout"

"$TEMP_DIR/test-panel-layout"
