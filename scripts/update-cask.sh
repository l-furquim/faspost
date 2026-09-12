#!/bin/bash
set -euo pipefail

VERSION="${1:?version required}"
SHA256="${2:?sha256 required}"
FILE="${3:-Casks/fastpost.rb}"

[[ -f "$FILE" ]] || { echo "Cask file not found: $FILE" >&2; exit 1; }

if [[ "$(uname -s)" == "Darwin" ]]; then
  sed -i '' -E "s/version \"[^\"]+\"/version \"${VERSION}\"/" "$FILE"
  sed -i '' -E "s/sha256 \"[^\"]+\"/sha256 \"${SHA256}\"/" "$FILE"
else
  sed -i -E "s/version \"[^\"]+\"/version \"${VERSION}\"/" "$FILE"
  sed -i -E "s/sha256 \"[^\"]+\"/sha256 \"${SHA256}\"/" "$FILE"
fi
