#!/usr/bin/env bash
# Packages dist/Helper.app into dist/Helper-<version>.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
[ -d dist/Helper.app ] || { echo "Run scripts/build-app.sh first"; exit 1; }
STAGE="$(mktemp -d)"
cp -R dist/Helper.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
OUT="dist/Helper-${VERSION}.dmg"
rm -f "$OUT"
hdiutil create -volname "Helper" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
