#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="Sweet No Sleep — Kiwi Cat.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
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
if [[ -d "$ROOT_DIR/Resources/PetSkins" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/PetSkins"
  cp -R "$ROOT_DIR/Resources/PetSkins/." "$APP_DIR/Contents/Resources/PetSkins/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
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
