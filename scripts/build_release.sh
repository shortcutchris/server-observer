#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUILD_NUMBER="${2:-1}"
DERIVED_DATA="$ROOT/.build/ReleaseDerivedData"
DIST="$ROOT/dist"
OUTPUT_APP="$DIST/ServerObserver.app"
ARCHIVE="$DIST/ServerObserver-$VERSION.zip"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/server-observer-release.XXXXXX")"
APP="$WORK_DIR/ServerObserver.app"
trap 'rm -rf "$WORK_DIR"' EXIT
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
    | head -1)"
fi

mkdir -p "$DIST"
rm -rf "$OUTPUT_APP" "$ARCHIVE"

cd "$ROOT"
xcodegen generate

SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
SIGNED_BUILD=0
if [[ -n "$SIGNING_IDENTITY" ]] && security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
  SIGNED_BUILD=1
  echo "▸ Developer-ID-Signatur nach dem Build: $SIGNING_IDENTITY"
else
  echo "⚠ Keine Developer ID gefunden; der Build bleibt unsigniert."
fi

xcodebuild \
  -project ServerObserver.xcodeproj \
  -scheme ServerObserver \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${SIGNING_ARGS[@]}" \
  clean build

ditto "$DERIVED_DATA/Build/Products/Release/ServerObserver.app" "$APP"
xattr -cr "$APP"

if [[ "$SIGNED_BUILD" == "1" ]]; then
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
  SPARKLE_VERSION="$SPARKLE/Versions/B"

  # Swift Package Manager signs Sparkle on copy, but not all nested helpers for
  # Developer-ID distribution. Sparkle's documented inside-out order is required.
  xattr -cr "$APP"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc"
  xattr -cr "$APP"
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
    --sign "$SIGNING_IDENTITY" "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
  xattr -cr "$APP"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_VERSION/Autoupdate"
  xattr -cr "$APP"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_VERSION/Updater.app"
  xattr -cr "$APP"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$SPARKLE"
  # File-provider metadata can be reattached while nested bundles are read.
  # Clear it again before sealing the outer application bundle.
  xattr -cr "$APP"
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/ServerObserver/ServerObserverRelease.entitlements" \
    --sign "$SIGNING_IDENTITY" "$APP"
  xattr -cr "$APP"

  codesign --verify --deep --strict --verbose=2 "$APP"
fi

ditto "$APP" "$OUTPUT_APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

echo "✓ App: $OUTPUT_APP"
echo "✓ Update-Archiv: $ARCHIVE"
