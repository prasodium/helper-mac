#!/usr/bin/env bash
# Builds dist/Helper.app (universal when possible) from the Swift package.
#   VERSION=1.0.0 BUILD=1 scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
APP="dist/Helper.app"

echo "▸ Building release binaries"
ARCHS=()
for arch in arm64 x86_64; do
  if swift build -c release --product Helper --triple "${arch}-apple-macosx14.0" >/dev/null 2>&1; then
    ARCHS+=("$arch")
    BIN="$(swift build -c release --product Helper --triple "${arch}-apple-macosx14.0" --show-bin-path 2>/dev/null)"
    cp "${BIN}/Helper" ".build/Helper-${arch}"
  else
    echo "  (skipping ${arch}: build failed)"
  fi
done
[ ${#ARCHS[@]} -gt 0 ] || { echo "No architecture built"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ ${#ARCHS[@]} -eq 2 ]; then
  lipo -create .build/Helper-arm64 .build/Helper-x86_64 -output "$APP/Contents/MacOS/Helper"
else
  cp ".build/Helper-${ARCHS[0]}" "$APP/Contents/MacOS/Helper"
fi
echo "  architectures: $(lipo -archs "$APP/Contents/MacOS/Helper")"

sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD}/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Building icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for base in 16 32 128 256 512; do
  sips -z $base $base Resources/AppIcon.png --out "$ICONSET/icon_${base}x${base}.png" >/dev/null
  sips -z $((base*2)) $((base*2)) Resources/AppIcon.png --out "$ICONSET/icon_${base}x${base}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing"
# Developer ID when available (SIGN_IDENTITY="Developer ID Application: …"), ad-hoc otherwise.
codesign --force --deep --options runtime --sign "${SIGN_IDENTITY:--}" "$APP" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --deep --strict "$APP" && echo "  signature OK"
echo "✓ $APP (v${VERSION})"
