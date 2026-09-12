#!/bin/bash
# Signs Fastpost.app with Developer ID and notarizes the DMG/PKG when secrets exist.
set -euo pipefail

APP="${1:?app path required}"
DMG="${2:?dmg path required}"
PKG="${3:?pkg path required}"

if [[ -z "${APPLE_DEVELOPER_ID_P12:-}" ]]; then
  echo "APPLE_DEVELOPER_ID_P12 is not set; skipping signing and notarization."
  exit 0
fi

for required in \
  APPLE_DEVELOPER_ID_P12_PASSWORD \
  APPLE_TEAM_ID \
  APPLE_API_KEY \
  APPLE_API_KEY_ID \
  APPLE_API_ISSUER_ID
do
  if [[ -z "${!required:-}" ]]; then
    echo "$required is required when APPLE_DEVELOPER_ID_P12 is set." >&2
    exit 1
  fi
done

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/fastpost-sign.XXXXXX")"
KEYCHAIN="$WORKDIR/fastpost.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
P12="$WORKDIR/developer-id.p12"
API_KEY="$WORKDIR/AuthKey_${APPLE_API_KEY_ID}.p8"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "$APPLE_DEVELOPER_ID_P12" | base64 --decode > "$P12"
printf '%s' "$APPLE_API_KEY" > "$API_KEY"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productsign
security list-keychain -d user -s "$KEYCHAIN" "$(security list-keychain -d user | tr -d '"')"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
  | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
if [[ -z "$IDENTITY" ]]; then
  echo "No Developer ID Application identity found in the imported certificate." >&2
  exit 1
fi

echo "Signing $APP with $IDENTITY"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
DEST="$(cd "$(dirname "$DMG")" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/package.sh" "$APP" "$VERSION" "$DEST"

echo "Notarizing $DMG"
xcrun notarytool submit "$DMG" --wait \
  --key "$API_KEY" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID"
xcrun stapler staple "$DMG"

echo "Notarizing $PKG"
xcrun notarytool submit "$PKG" --wait \
  --key "$API_KEY" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID"
xcrun stapler staple "$PKG"

echo "Signed and notarized $DMG and $PKG"
