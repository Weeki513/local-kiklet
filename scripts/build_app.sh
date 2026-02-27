#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="LocalKiklet"
APP_BUNDLE="dist/${APP_NAME}.app"
BUILD_DIR=".build/release"
ICON_SOURCE="packaging/icon.png"
ICON_NAME="${APP_NAME}.icns"

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ -f "$ICON_SOURCE" ]]; then
  ICON_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/localkiklet.icon.XXXXXX")"
  ICONSET_DIR="$ICON_TMP_DIR/${APP_NAME}.iconset"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/$ICON_NAME"
  rm -rf "$ICON_TMP_DIR"
fi

if [[ -d "$BUILD_DIR/${APP_NAME}_LocalKiklet.bundle" ]]; then
  cp -R "$BUILD_DIR/${APP_NAME}_LocalKiklet.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

if [[ "${LOCAL_KIKLET_SKIP_SIGN:-0}" != "1" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "App bundle created: $ROOT_DIR/$APP_BUNDLE"
