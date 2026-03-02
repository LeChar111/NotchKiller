#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NotchKiller"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
BIN_PATH="$APP_DIR/Contents/MacOS/$APP_NAME"
PLIST_PATH="$APP_DIR/Contents/Info.plist"

if ! /usr/bin/xcodebuild -license check >/dev/null 2>&1; then
  echo "Xcode license not accepted. Run: sudo xcodebuild -license accept"
  exit 69
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.flux.notchkiller</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

xcrun swiftc \
  -sdk "$SDK_PATH" \
  -parse-as-library \
  -O \
  -framework AppKit \
  -framework SwiftUI \
  -framework IOKit \
  "$ROOT_DIR/Sources/NotchKillerApp.swift" \
  -o "$BIN_PATH"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Build OK: $APP_DIR"
