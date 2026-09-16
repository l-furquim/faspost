#!/bin/bash
set -euo pipefail

VERSION="${1:?version required}"
SHA256="${2:?sha256 required}"
FILE="${3:-Casks/fastpost.rb}"

[[ -f "$FILE" ]] || { echo "Cask file not found: $FILE" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Version must look like 1.2.3, got $VERSION" >&2
  exit 1
}
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "sha256 must be 64 hex characters, got $SHA256" >&2
  exit 1
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  sed -i '' -E "s/^  version \"[^\"]+\"/  version \"${VERSION}\"/" "$FILE"
  sed -i '' -E "s/^  sha256 \"[^\"]+\"/  sha256 \"${SHA256}\"/" "$FILE"
else
  sed -i -E "s/^  version \"[^\"]+\"/  version \"${VERSION}\"/" "$FILE"
  sed -i -E "s/^  sha256 \"[^\"]+\"/  sha256 \"${SHA256}\"/" "$FILE"
fi

grep -q "^  version \"${VERSION}\"" "$FILE" || {
  echo "Failed to write version ${VERSION} to $FILE" >&2
  exit 1
}
grep -q "^  sha256 \"${SHA256}\"" "$FILE" || {
  echo "Failed to write sha256 to $FILE" >&2
  exit 1
}

echo "Updated $FILE to $VERSION"
