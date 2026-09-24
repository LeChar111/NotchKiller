#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NotchKiller"
VERSION="2.1.0"
BUNDLE_ID="com.flux.notchkiller"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
BIN_PATH="$APP_DIR/Contents/MacOS/$APP_NAME"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
PLIST_PATH="$APP_DIR/Contents/Info.plist"

# NK_UNIVERSAL=1 produit un binaire arm64 + x86_64 (utilisé par release.sh).
UNIVERSAL="${NK_UNIVERSAL:-0}"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Compilateur Swift introuvable. Installez Xcode ou les Command Line Tools."
  exit 69
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$RESOURCES_DIR"

# ── Icône ────────────────────────────────────────────────────────────────────
ICON_SRC="$ROOT_DIR/Tools/make-icon.swift"
ICON_OUT="$RESOURCES_DIR/AppIcon.icns"
if [[ -f "$ICON_SRC" ]] && { [[ ! -f "$ICON_OUT" ]] || [[ "$ICON_SRC" -nt "$ICON_OUT" ]]; }; then
  echo "Génération de l'icône…"
  WORK="$(mktemp -d)"
  xcrun swift "$ICON_SRC" "$WORK" >/dev/null
  iconutil -c icns "$WORK/AppIcon.iconset" -o "$ICON_OUT"
  rm -rf "$WORK"
fi

# ── Info.plist ───────────────────────────────────────────────────────────────
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>NotchKiller affiche votre prochain rendez-vous dans l'encoche.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotchKiller pilote Musique et Spotify pour la lecture, et Ghostty pour ouvrir une nouvelle fenêtre.</string>
    <key>NSHumanReadableCopyright</key>
    <string>NotchKiller $VERSION</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# ── Compilation ──────────────────────────────────────────────────────────────
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

SWIFT_FILES=()
while IFS= read -r -d '' file; do
  SWIFT_FILES+=("$file")
done < <(find "$ROOT_DIR/Sources" -name '*.swift' -print0)

if [[ ${#SWIFT_FILES[@]} -eq 0 ]]; then
  echo "Aucun fichier Swift dans Sources/"
  exit 1
fi

compile() {
  local target="$1" output="$2"
  xcrun swiftc \
    -sdk "$SDK_PATH" \
    -target "$target" \
    -parse-as-library \
    -O \
    -framework AppKit \
    -framework SwiftUI \
    -framework IOKit \
    -framework CoreAudio \
    "${SWIFT_FILES[@]}" \
    -o "$output"
}

if [[ "$UNIVERSAL" == "1" ]]; then
  echo "Compilation de ${#SWIFT_FILES[@]} fichiers Swift (arm64 + x86_64)…"
  TMP="$(mktemp -d)"
  compile arm64-apple-macos15.0 "$TMP/$APP_NAME.arm64"
  compile x86_64-apple-macos15.0 "$TMP/$APP_NAME.x86_64"
  lipo -create "$TMP/$APP_NAME.arm64" "$TMP/$APP_NAME.x86_64" -output "$BIN_PATH"
  rm -rf "$TMP"
else
  echo "Compilation de ${#SWIFT_FILES[@]} fichiers Swift (arm64)…"
  compile arm64-apple-macos15.0 "$BIN_PATH"
fi

# Signature. Une signature ad hoc change à chaque compilation, donc macOS
# redemande les autorisations à chaque fois : renseignez NK_SIGN_IDENTITY avec
# une identité stable (voir Tools/setup-signing.sh) pour qu'elles tiennent.
SIGN_IDENTITY="${NK_SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP_DIR" >/dev/null 2>&1 \
  || codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 \
  || true

echo "Build OK : $APP_DIR ($(lipo -archs "$BIN_PATH" 2>/dev/null || echo arm64))"
