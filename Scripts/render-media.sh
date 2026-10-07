#!/usr/bin/env bash
# Render every SVG source in Resources/Art into the media bundle that the app
# ships with, the README links to, and the release icon is cut from.
#
# macOS is the release path: stock qlmanage/sips rasterize an SVG, iconutil packs
# the .icns. Linux workstations get the same outputs from rsvg-convert, resvg, or
# Scripts/svg-render.py (cairosvg / resvg-py) and Scripts/icns-pack.py.
#
# The script is idempotent: it always rewrites the same outputs from the same
# sources. When no rasterizer is available it prints a skip message and exits 0,
# so a checkout without rendering tools keeps the checked-in renders. A tool that
# exists but fails is reported and fails the run instead of shipping stale art.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ART_DIR="$ROOT_DIR/Resources/Art"
MEDIA_DIR="$ROOT_DIR/Resources/Media"
SVG_HELPER="$ROOT_DIR/Scripts/svg-render.py"
ICNS_HELPER="$ROOT_DIR/Scripts/icns-pack.py"
ICNS_NAME="SweetNoSleep"
ICON_SIZES=(16 32 64 128 256 512 1024)
RENDERERS=()

# BSD mktemp (macOS) requires a template, GNU mktemp does not; give it one.
scratch_directory() {
  mktemp -d "${TMPDIR:-/tmp}/sns-media.XXXXXX"
}

python_backend_available() {
  command -v python3 >/dev/null 2>&1 || return 1
  [[ -f "$SVG_HELPER" ]] || return 1
  python3 -c 'import cairosvg' >/dev/null 2>&1 && return 0
  python3 -c 'import resvg_py' >/dev/null 2>&1 && return 0
  return 1
}

detect_renderers() {
  command -v rsvg-convert >/dev/null 2>&1 && RENDERERS+=(rsvg-convert)
  command -v resvg >/dev/null 2>&1 && RENDERERS+=(resvg)
  python_backend_available && RENDERERS+=(python)
  command -v qlmanage >/dev/null 2>&1 && RENDERERS+=(qlmanage)
  command -v sips >/dev/null 2>&1 && RENDERERS+=(sips)
  return 0
}

# qlmanage renders a square thumbnail that keeps the aspect ratio and centers the
# art, so a wide source comes back letterboxed. Crop back to the target aspect
# ratio before resizing to the exact pixel size.
render_with_qlmanage() {
  local source="$1" output="$2" width="$3" height="$4"
  local scratch longest thumbnail thumb_width thumb_height crop_width crop_height

  scratch="$(scratch_directory)" || return 1
  longest="$width"
  if ((height > width)); then longest="$height"; fi
  qlmanage -t -s "$longest" -o "$scratch" "$source" >/dev/null 2>&1 || true
  thumbnail="$scratch/$(basename "$source").png"
  if [[ ! -f "$thumbnail" ]]; then
    thumbnail="$(find "$scratch" -maxdepth 1 -name '*.png' -print -quit)"
  fi
  if [[ ! -f "$thumbnail" ]]; then
    echo "qlmanage could not rasterize $(basename "$source")" >&2
    rm -rf "$scratch"
    return 1
  fi

  thumb_width="$(sips -g pixelWidth "$thumbnail" | awk '/pixelWidth/ {print $2}')"
  thumb_height="$(sips -g pixelHeight "$thumbnail" | awk '/pixelHeight/ {print $2}')"
  if [[ -z "$thumb_width" || -z "$thumb_height" || "$thumb_width" -le 0 || "$thumb_height" -le 0 ]]; then
    echo "sips could not read the qlmanage thumbnail for $(basename "$source")" >&2
    rm -rf "$scratch"
    return 1
  fi

  crop_width="$thumb_width"
  crop_height=$((thumb_width * height / width))
  if ((crop_height > thumb_height)); then
    crop_height="$thumb_height"
    crop_width=$((thumb_height * width / height))
  fi
  if ((crop_width < 1)); then crop_width=1; fi
  if ((crop_height < 1)); then crop_height=1; fi

  cp "$thumbnail" "$output"
  rm -rf "$scratch"
  sips --cropToHeightWidth "$crop_height" "$crop_width" "$output" >/dev/null
  sips --resampleHeightWidth "$height" "$width" "$output" >/dev/null
}

# Last resort: some sips builds read SVG directly.
render_with_sips() {
  local source="$1" output="$2" width="$3" height="$4"
  if ! sips -s format png "$source" --out "$output" >/dev/null 2>&1; then
    echo "sips could not rasterize $(basename "$source")" >&2
    return 1
  fi
  sips --resampleHeightWidth "$height" "$width" "$output" >/dev/null 2>&1 || true
}

render_with() {
  local renderer="$1" source="$2" output="$3" width="$4" height="$5"
  case "$renderer" in
    rsvg-convert) rsvg-convert --width "$width" --height "$height" --output "$output" "$source" ;;
    resvg) resvg --width "$width" --height "$height" "$source" "$output" ;;
    python) python3 "$SVG_HELPER" "$source" "$output" "$width" "$height" ;;
    qlmanage) render_with_qlmanage "$source" "$output" "$width" "$height" ;;
    sips) render_with_sips "$source" "$output" "$width" "$height" ;;
    *) echo "Unknown renderer: $renderer" >&2; return 1 ;;
  esac
}

RENDERER_USED=""
render_png() {
  local source="$1" output="$2" width="$3" height="$4" renderer
  if [[ ! -f "$source" ]]; then
    echo "Missing SVG source: $source" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$output")"
  for renderer in "${RENDERERS[@]}"; do
    rm -f "$output"
    if render_with "$renderer" "$source" "$output" "$width" "$height" >/dev/null 2>&1 && [[ -s "$output" ]]; then
      RENDERER_USED="$renderer"
      printf '  %-28s %4d x %-4d via %s\n' "$(basename "$output")" "$width" "$height" "$renderer"
      return 0
    fi
  done
  echo "Every available rasterizer failed for $(basename "$source")." >&2
  return 1
}

render_icon() {
  local work_dir iconset
  work_dir="$(scratch_directory)"
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

  if command -v iconutil >/dev/null 2>&1 \
    && iconutil --convert icns "$iconset" --output "$MEDIA_DIR/$ICNS_NAME.icns" 2>/dev/null; then
    printf '  %-28s packed by iconutil\n' "$ICNS_NAME.icns"
  else
    # No iconutil (or it refused the set): write the same PNG based container.
    printf '  %-28s packed by icns-pack.py\n' "$ICNS_NAME.icns"
    python3 "$ICNS_HELPER" "$iconset" "$MEDIA_DIR/$ICNS_NAME.icns"
  fi
  rm -rf "$work_dir"
}

detect_renderers
if [[ ${#RENDERERS[@]} -eq 0 ]]; then
  cat <<'MESSAGE'
SKIP media render: no SVG rasterizer found.
Install one of: librsvg (rsvg-convert), resvg, `pip3 install --user cairosvg`,
or run this script on macOS, which uses the stock qlmanage/sips tools.
Checked-in renders in Resources/Media stay untouched; nothing was rewritten.
MESSAGE
  exit 0
fi

echo "Rendering media with: ${RENDERERS[*]}"
mkdir -p "$MEDIA_DIR"

# Menu bar icons are 22 pt, with a 2x render for retina menu bars.
render_png "$ART_DIR/menubar-awake.svg" "$MEDIA_DIR/menubar-awake.png" 22 22
render_png "$ART_DIR/menubar-awake.svg" "$MEDIA_DIR/menubar-awake@2x.png" 44 44
render_png "$ART_DIR/menubar-asleep.svg" "$MEDIA_DIR/menubar-asleep.png" 22 22
render_png "$ART_DIR/menubar-asleep.svg" "$MEDIA_DIR/menubar-asleep@2x.png" 44 44

# Skin previews shown on the Settings > Pet cards: 104x52 pt, plus 2x. Add a new
# skin by extending this list and Scripts/verify-media.py (see docs/MEDIA.md).
for skin in kiwi moonlight strawberry; do
  render_png "$ART_DIR/preview-$skin.svg" "$MEDIA_DIR/preview-$skin.png" 104 52
  render_png "$ART_DIR/preview-$skin.svg" "$MEDIA_DIR/preview-$skin@2x.png" 208 104
done

# Marketing renders: the README banner and the social preview card.
render_png "$ART_DIR/banner.svg" "$MEDIA_DIR/banner.png" 1280 640
render_png "$ART_DIR/og-image.svg" "$MEDIA_DIR/og-image.png" 1200 630

render_icon

echo "Media written to Resources/Media ($(du -sh "$MEDIA_DIR" | cut -f1)):"
printf '  %s\n' "$(ls -1 "$MEDIA_DIR" | tr '\n' ' ')"
