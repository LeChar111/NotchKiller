#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NotchKiller"
VERSION="$(command grep -m1 '^VERSION=' "$ROOT_DIR/build.sh" | cut -d'"' -f2)"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
STAGE="$DIST_DIR/stage"

echo "── NotchKiller $VERSION ──────────────────────────────────"

# Binaire universel : l'app tourne aussi sur les Mac Intel sous Sequoia.
NK_UNIVERSAL=1 "$ROOT_DIR/build.sh"

ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/$APP_NAME")"
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
  echo "Binaire non universel ($ARCHS) — arrêt."
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# ── Archive ──────────────────────────────────────────────────────────────────
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP"

# ── Image disque ─────────────────────────────────────────────────────────────
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$APP_NAME $VERSION" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
rm -rf "$STAGE"

# ── Vérification ─────────────────────────────────────────────────────────────
codesign --verify --deep --strict "$APP_DIR" 2>/dev/null \
  && SIGN_STATUS="signature ad hoc valide" \
  || SIGN_STATUS="signature non vérifiable"

cd "$DIST_DIR"
shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS.txt

echo
echo "Architectures : $ARCHS"
echo "Signature     : $SIGN_STATUS"
echo
ls -lh "$DIST_DIR" | tail -n +2 | awk '{printf "  %-34s %s\n", $9, $5}'
echo
cat SHA256SUMS.txt | awk '{printf "  %s  %s\n", substr($1,1,16)"…", $2}'
echo
cat <<NOTE
Distribution : l'app est signée ad hoc, pas notariée — sur une autre machine,
macOS affichera un avertissement au premier lancement (clic droit → Ouvrir,
ou Réglages Système → Confidentialité et sécurité → Ouvrir quand même).
Une notarisation demande un compte Apple Developer et un certificat
Developer ID ; le script est prêt à l'accueillir si vous en avez un.
NOTE
