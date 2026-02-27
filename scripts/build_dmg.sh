#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="LocalKiklet"
APP_BUNDLE="dist/${APP_NAME}.app"
DMG_PATH="dist/${APP_NAME}.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/localkiklet-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/build_app.sh"

rm -f "$DMG_PATH"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/Install Local Kiklet.txt" <<'EOF'
1) Перетащите LocalKiklet.app в Applications
2) Запустите LocalKiklet из папки Applications
EOF

hdiutil create \
  -volname "Local Kiklet" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "DMG created: $ROOT_DIR/$DMG_PATH"
