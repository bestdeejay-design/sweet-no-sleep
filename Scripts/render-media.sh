#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART_DIR="$ROOT_DIR/Resources/Art"
OUTPUT_DIR="$ART_DIR/Rendered"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'Skipping raster media rendering: Resources/Art contains hand-authored SVG sources; render on macOS with sips and iconutil.\n'
  exit 0
fi

for tool in sips iconutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Cannot render release media: required macOS tool is missing: %s\n' "$tool" >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIR"
ICONSET_DIR="$OUTPUT_DIR/SweetNoSleep.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

render_png() {
  local source="$1"
  local width="$2"
  local height="$3"
  local destination="$4"

  if [[ ! -f "$source" ]]; then
    printf 'Missing SVG source: %s\n' "$source" >&2
    exit 1
  fi
  rm -f "$destination"
  sips -s format png --resampleHeightWidth "$height" "$width" "$source" --out "$destination" >/dev/null
}

render_native_png() {
  local source="$1"
  local destination="$2"

  if [[ ! -f "$source" ]]; then
    printf 'Missing SVG source: %s\n' "$source" >&2
    exit 1
  fi
  rm -f "$destination"
  sips -s format png "$source" --out "$destination" >/dev/null
}

# macOS iconset names map point sizes to 1x and 2x pixel representations.
render_png "$ART_DIR/app-icon.svg" 16 16 "$ICONSET_DIR/icon_16x16.png"
render_png "$ART_DIR/app-icon.svg" 32 32 "$ICONSET_DIR/icon_16x16@2x.png"
render_png "$ART_DIR/app-icon.svg" 32 32 "$ICONSET_DIR/icon_32x32.png"
render_png "$ART_DIR/app-icon.svg" 64 64 "$ICONSET_DIR/icon_32x32@2x.png"
render_png "$ART_DIR/app-icon.svg" 128 128 "$ICONSET_DIR/icon_128x128.png"
render_png "$ART_DIR/app-icon.svg" 256 256 "$ICONSET_DIR/icon_128x128@2x.png"
render_png "$ART_DIR/app-icon.svg" 256 256 "$ICONSET_DIR/icon_256x256.png"
render_png "$ART_DIR/app-icon.svg" 512 512 "$ICONSET_DIR/icon_256x256@2x.png"
render_png "$ART_DIR/app-icon.svg" 512 512 "$ICONSET_DIR/icon_512x512.png"
render_png "$ART_DIR/app-icon.svg" 1024 1024 "$ICONSET_DIR/icon_512x512@2x.png"
rm -f "$OUTPUT_DIR/SweetNoSleep.icns"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_DIR/SweetNoSleep.icns"
render_png "$ART_DIR/app-icon.svg" 1024 1024 "$OUTPUT_DIR/app-icon-1024.png"

# Menu-bar art is authored at 22 pt; include 2x pixels for Retina displays.
for state in awake asleep; do
  render_png "$ART_DIR/menubar-$state.svg" 22 22 "$OUTPUT_DIR/menubar-$state.png"
  render_png "$ART_DIR/menubar-$state.svg" 44 44 "$OUTPUT_DIR/menubar-$state@2x.png"
done

# Skin cards display a 3:2 preview and keep a Retina rendition beside it.
for skin in kiwi moonlight strawberry; do
  render_png "$ART_DIR/preview-$skin.svg" 240 160 "$OUTPUT_DIR/preview-$skin.png"
  render_png "$ART_DIR/preview-$skin.svg" 480 320 "$OUTPUT_DIR/preview-$skin@2x.png"
done

# Keep the release banner and future Open Graph variant at their authored sizes.
render_native_png "$ART_DIR/banner.svg" "$OUTPUT_DIR/banner.png"
render_native_png "$ART_DIR/og-image.svg" "$OUTPUT_DIR/og-image.png"

printf 'Rendered app icon, menu-bar icons, skin previews, and social images into %s\n' "$OUTPUT_DIR"
