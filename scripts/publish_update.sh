#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$ROOT/.release.env" ]] && source "$ROOT/.release.env"
VERSION="${1:?Verwendung: scripts/publish_update.sh <version> [build-number] [release-notes.md]}"
BUILD_NUMBER="${2:-1}"
NOTES_SOURCE="${3:-}"
TAG="v$VERSION"
DIST="$ROOT/dist"
APP="$DIST/ServerObserver.app"
ARCHIVE="$DIST/ServerObserver-$VERSION.zip"
FEED_DIR="$ROOT/release-feed"
SPARKLE_ACCOUNT="dev.serverobserver.app"
SPARKLE_TOOLS="$ROOT/.build/ReleaseDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
API_KEY="${APPLE_API_KEY_PATH:-}"
API_KEY_ID="${APPLE_API_KEY_ID:-}"
API_ISSUER_ID="${APPLE_API_ISSUER_ID:-}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT/scripts/build_release.sh" "$VERSION" "$BUILD_NUMBER"
fi

if [[ -n "$API_KEY" && -n "$API_KEY_ID" && -n "$API_ISSUER_ID" && -f "$API_KEY" ]] \
  && codesign -dv "$APP" >/dev/null 2>&1; then
  echo "▸ Notarisierung wird an Apple übermittelt …"
  NOTARY_RESULT="$(xcrun notarytool submit "$ARCHIVE" \
    --key "$API_KEY" \
    --key-id "$API_KEY_ID" \
    --issuer "$API_ISSUER_ID" \
    --wait \
    --output-format json)"
  printf '%s\n' "$NOTARY_RESULT"
  NOTARY_STATUS="$(printf '%s' "$NOTARY_RESULT" | plutil -extract status raw -o - -- -)"
  [[ "$NOTARY_STATUS" == "Accepted" ]] || { echo "✗ Apple-Notarisierung: $NOTARY_STATUS"; exit 1; }

  NOTARY_WORK="$(mktemp -d "${TMPDIR:-/tmp}/server-observer-notary.XXXXXX")"
  ditto -x -k "$ARCHIVE" "$NOTARY_WORK"
  STAPLE_APP="$NOTARY_WORK/ServerObserver.app"
  xcrun stapler staple "$STAPLE_APP"
  xcrun stapler validate "$STAPLE_APP"
  xattr -cr "$STAPLE_APP"
  xcrun stapler validate "$STAPLE_APP"
  rm -f "$ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$STAPLE_APP" "$ARCHIVE"
  rm -rf "$APP"
  ditto "$STAPLE_APP" "$APP"
  rm -rf "$NOTARY_WORK"
else
  echo "⚠ Notarisierung übersprungen: API-Key oder Developer-ID-Signatur fehlt."
fi

rm -rf "$FEED_DIR"
mkdir -p "$FEED_DIR"
cp "$ARCHIVE" "$FEED_DIR/"
cp "$ROOT/appcast.xml" "$FEED_DIR/appcast.xml"

if [[ -n "$NOTES_SOURCE" ]]; then
  cp "$NOTES_SOURCE" "$FEED_DIR/ServerObserver-$VERSION.md"
else
  printf '# Server Observer %s\n\nNeue Version von Server Observer.\n' "$VERSION" \
    > "$FEED_DIR/ServerObserver-$VERSION.md"
fi

"$SPARKLE_TOOLS/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://github.com/shortcutchris/server-observer/releases/download/$TAG/" \
  --release-notes-url-prefix "https://github.com/shortcutchris/server-observer/releases/download/$TAG/" \
  --link "https://github.com/shortcutchris/server-observer" \
  -o "$FEED_DIR/appcast.xml" \
  "$FEED_DIR"

cp "$FEED_DIR/appcast.xml" "$ROOT/appcast.xml"
cp "$FEED_DIR/ServerObserver-$VERSION.md" "$DIST/ServerObserver-$VERSION.md"

echo "✓ Signierter Appcast: $ROOT/appcast.xml"
echo "✓ Release-Dateien: $DIST"
