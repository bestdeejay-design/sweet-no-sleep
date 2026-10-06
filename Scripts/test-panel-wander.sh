#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

swiftc \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT_DIR/Sources/SweetNoSleep/PanelOriginAnimator.swift" \
  "$ROOT_DIR/Scripts/test-panel-wander.swift" \
  -framework AppKit \
  -o "$TEMP_DIR/test-panel-wander"

"$TEMP_DIR/test-panel-wander"
