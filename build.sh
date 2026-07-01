#!/bin/bash
# Build Kotha (Release), install into /Applications, and launch it.
set -e
cd "$(dirname "$0")"

APP_NAME="Kotha.app"
DEST="/Applications/$APP_NAME"

if [ ! -d "Kotha.xcodeproj" ] || [ project.yml -nt Kotha.xcodeproj ]; then
  echo "→ Generating Xcode project…"
  xcodegen generate
fi

echo "→ Building Release…"
xcodebuild -project Kotha.xcodeproj -scheme Kotha -configuration Release \
  -derivedDataPath build build -quiet

BUILT="build/Build/Products/Release/$APP_NAME"
if [ ! -d "$BUILT" ]; then
  echo "✗ Build product not found at $BUILT" >&2
  exit 1
fi

echo "→ Quitting any running instance…"
pkill -x Kotha 2>/dev/null || true
sleep 0.5

echo "→ Installing to $DEST…"
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

# Re-sign with the stable self-signed identity (if set up) so Accessibility/Mic
# permission persists across rebuilds. Falls back to the ad-hoc signature.
IDENTITY="Kotha Code Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "→ Signing with '$IDENTITY'…"
  codesign --force --deep --sign "$IDENTITY" "$DEST"
else
  echo "ℹ︎ No stable identity found — run ./setup-signing.sh once so Accessibility"
  echo "  permission stops resetting on every build."
fi

echo "→ Launching…"
open "$DEST"
echo "✓ Kotha installed to /Applications and running in the menu bar."
