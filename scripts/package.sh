#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 <Fastpost.app> <version> <destination>" >&2
  exit 1
}

APP="${1:-}"
VERSION="${2:-}"
DEST="${3:-}"

[[ -n "$APP" && -n "$VERSION" && -n "$DEST" ]] || usage
[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }

APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

DMG="$DEST/Fastpost-${VERSION}.dmg"
PKG="$DEST/Fastpost-${VERSION}.pkg"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fastpost-dmg.XXXXXX")"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/fastpost-pkg.XXXXXX")"
cleanup() {
  rm -rf "$STAGE" "$ROOT"
}
trap cleanup EXIT

cp -R "$APP" "$STAGE/Fastpost.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create \
  -volname Fastpost \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

cp -R "$APP" "$ROOT/Fastpost.app"
rm -f "$PKG"
pkgbuild \
  --root "$ROOT" \
  --identifier furqas.fastpost \
  --version "$VERSION" \
  --install-location /Applications \
  "$PKG"

echo "Wrote $DMG"
echo "Wrote $PKG"
