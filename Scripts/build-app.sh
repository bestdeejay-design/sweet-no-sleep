#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="Sweet No Sleep — Kiwi Cat.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
"$ROOT_DIR/Scripts/render-media.sh"
swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --configuration "$CONFIGURATION" --show-bin-path)"
BINARY="$BIN_DIR/SweetNoSleep"
if [[ ! -x "$BINARY" ]]; then
  echo "Build succeeded, but executable was not found at: $BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/SweetNoSleep"
shopt -s nullglob
RESOURCE_BUNDLES=("$BIN_DIR"/*.bundle)
if [[ ${#RESOURCE_BUNDLES[@]} -eq 0 ]]; then
  echo "Build succeeded, but SwiftPM localization resource bundle was not found in: $BIN_DIR" >&2
  exit 1
fi
cp -R "${RESOURCE_BUNDLES[@]}" "$APP_DIR/Contents/Resources/"
if [[ -d "$ROOT_DIR/Resources/PetSkins" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/PetSkins"
  cp -R "$ROOT_DIR/Resources/PetSkins/." "$APP_DIR/Contents/Resources/PetSkins/"
fi

MEDIA_DIR="$ROOT_DIR/Resources/Art/Rendered"
ICON_FILE="$MEDIA_DIR/SweetNoSleep.icns"
if [[ ! -s "$ICON_FILE" ]]; then
  echo "Rendered app icon is missing: $ICON_FILE" >&2
  exit 1
fi
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/SweetNoSleep.icns"
mkdir -p "$APP_DIR/Contents/Resources/Media"
for media in \
  menubar-awake.png menubar-awake@2x.png \
  menubar-asleep.png menubar-asleep@2x.png \
  preview-kiwi.png preview-kiwi@2x.png \
  preview-moonlight.png preview-moonlight@2x.png \
  preview-strawberry.png preview-strawberry@2x.png \
  preview-kot-arbuz.png preview-kot-arbuz@2x.png; do
  if [[ ! -s "$MEDIA_DIR/$media" ]]; then
    echo "Rendered app media is missing: $MEDIA_DIR/$media" >&2
    exit 1
  fi
  cp "$MEDIA_DIR/$media" "$APP_DIR/Contents/Resources/Media/$media"
done

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SweetNoSleep</string>
    <key>CFBundleIdentifier</key>
    <string>com.sweetnosleep.kiwicat</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Sweet No Sleep — Kiwi Cat</string>
    <key>CFBundleDisplayName</key>
    <string>Sweet No Sleep — Kiwi Cat</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>SweetNoSleep.icns</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>Sweet No Sleep Agent Bridge</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>sweetnosleep</string>
            </array>
        </dict>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# An ad-hoc signature is enough for local testing. Distribution should use a
# Developer ID signature and notarization instead.
codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
echo "Open it with: open \"$APP_DIR\""
