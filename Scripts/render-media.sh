#!/usr/bin/env bash
# Render every SVG source in Resources/Art into the media bundle that the app
# ships with, the README links to, and the release icon is cut from.
#
# macOS is the release path: stock qlmanage/sips rasterize an SVG, iconutil packs
# the .icns. Linux workstations get the same outputs from rsvg-convert, resvg, or
# Scripts/svg-render.py (cairosvg / resvg-py) and Scripts/icns-pack.py.
#
# The script is idempotent: it always rewrites the same outputs from the same
# sources, and it skips gracefully with a message when no rasterizer is available.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART_DIR="$ROOT_DIR/Resources/Art"
MEDIA_DIR="$ROOT_DIR/Resources/Media"
SVG_HELPER="$ROOT_DIR/Scripts/svg-render.py"
ICNS_HELPER="$ROOT_DIR/Scripts/icns-pack.py"
ICNS_NAME="SweetNoSleep"
ICON_SIZES=(16 32 64 128 256 512 1024)

python_backend_available() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c 'import cairosvg' >/dev/null 2>&1 && return 0
  python3 -c 'import resvg_py' >/dev/null 2>&1 && return 0
  return 1
}

detect_renderer() {
  if command -v rsvg-convert >/dev/null 2>&1; then printf 'rsvg-convert\n'; return 0; fi
  if command -v resvg >/dev/null 2>&1; then printf 'resvg\n'; return 0; fi
  if python_backend_available; then printf 'python\n'; return 0; fi
  if command -v qlmanage >/dev/null 2>&1; then printf 'qlmanage\n'; return 0; fi
  if command -v sips >/dev/null 2>&1; then printf 'sips\n'; return 0; fi
  printf 'none\n'
}

render_with_qlmanage() {
  local source="$1" output="$2" width="$3" height="$4"
  local scratch longest
  scratch="$(mktemp -d)"
  longest="$width"
  if (( height > width )); then longest="$height"; fi
  qlmanage -t -s "$longest" -o "$scratch" "$source" >/dev/null 2>&1 || true
  if [[ ! -f "$scratch/$(basename "$source").png" ]]; then
    rm -rf "$scratch"
    echo "qlmanage could not rasterize $(basename "$source")" >&2
    return 1
  fi
  cp "$scratch/$(basename "$source").png" "$output"
  rm -rf "$scratch"
  sips -z "$height" "$width" "$output" >/dev/null
}

render_with_sips() {
  local source="$1" output="$2" width="$3" height="$4"
  if ! sips -s format png "$source" --out "$output" >/dev/null 2>&1; then
    echo "sips could not rasterize $(basename "$source")" >&2
    return 1
  fi
  sips -z "$height" "$width" "$output" >/dev/null
}

render_png() {
  local source="$1" output="$2" width="$3" height="$4"
  [[ -f "$source" ]] || { echo "Missing SVG source: $source" >&2; exit 1; }
  mkdir -p "$(dirname "$output")"
  case "$RENDERER" in
    rsvg-convert) rsvg-convert --width "$width" --height "$height" --output "$output" "$source" ;;
    resvg) resvg --width "$width" --height "$height" "$source" "$output" ;;
    python) python3 "$SVG_HELPER" "$source" "$output" "$width" "$height" ;;
    qlmanage) render_with_qlmanage "$source" "$output" "$width" "$height" ;;
    sips) render_with_sips "$source" "$output" "$width" "$height" ;;
    *) echo "No SVG rasterizer selected." >&2; exit 1 ;;
  esac
}

render_icon() {
  local work_dir iconset
  work_dir="$(mktemp -d)"
  iconset="$work_dir/$ICNS_NAME.iconset"
  mkdir -p "$iconset"

  # iconutil expects the standard iconset names; the @2x files carry the larger
  # pixel sizes, so ten files cover the seven sizes plus their retina variants.
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_16x16.png" 16 16
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_16x16@2x.png" 32 32
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_32x32.png" 32 32
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_32x32@2x.png" 64 64
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_128x128.png" 128 128
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_128x128@2x.png" 256 256
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_256x256.png" 256 256
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_256x256@2x.png" 512 512
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_512x512.png" 512 512
  render_png "$ART_DIR/app-icon.svg" "$iconset/icon_512x512@2x.png" 1024 1024

  if command -v iconutil >/dev/null 2>&1; then
    iconutil --convert icns "$iconset" --output "$MEDIA_DIR/$ICNS_NAME.icns"
  else
    # Linux has no iconutil; the fallback writes the same PNG based icns payload.
    python3 "$ICNS_HELPER" "$iconset" "$MEDIA_DIR/$ICNS_NAME.icns"
  fi
  rm -rf "$work_dir"
}

RENDERER="$(detect_renderer)"
if [[ "$RENDERER" == "none" ]]; then
  cat <<'MESSAGE'
SKIP media render: no SVG rasterizer found.
Install one of: librsvg (rsvg-convert), resvg, `pip3 install --user cairosvg`,
or run this script on macOS, which uses the stock qlmanage/sips tools.
Checked-in renders in Resources/Media stay untouched; nothing was rewritten.
MESSAGE
  exit 0
fi

echo "Rendering media with: $RENDERER"
mkdir -p "$MEDIA_DIR"

# Menu bar template icons: 22 pt, plus a 2x render for retina menu bars.
render_png "$ART_DIR/menubar-awake.svg" "$MEDIA_DIR/menubar-awake.png" 22 22
render_png "$ART_DIR/menubar-awake.svg" "$MEDIA_DIR/menubar-awake@2x.png" 44 44
render_png "$ART_DIR/menubar-asleep.svg" "$MEDIA_DIR/menubar-asleep.png" 22 22
render_png "$ART_DIR/menubar-asleep.svg" "$MEDIA_DIR/menubar-asleep@2x.png" 44 44

# Skin previews shown on the Settings > Pet cards: 104x52 pt, plus 2x.
for skin in kiwi moonlight strawberry; do
  render_png "$ART_DIR/preview-$skin.svg" "$MEDIA_DIR/preview-$skin.png" 104 52
  render_png "$ART_DIR/preview-$skin.svg" "$MEDIA_DIR/preview-$skin@2x.png" 208 104
done

# Marketing renders: the README banner and the social preview card.
render_png "$ART_DIR/banner.svg" "$MEDIA_DIR/banner.png" 1280 640
render_png "$ART_DIR/og-image.svg" "$MEDIA_DIR/og-image.png" 1200 630

render_icon

echo "Media written to Resources/Media:"
for size in "${ICON_SIZES[@]}"; do
  printf '  %s.icns covers %s px\n' "$ICNS_NAME" "$size"
done
ls -1 "$MEDIA_DIR"
