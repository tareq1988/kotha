#!/bin/bash
# Cut a Sparkle release: build → package → EdDSA-sign → update appcast →
# commit/push appcast → create the GitHub release with the zip.
#
# Bump BOTH versions in project.yml before running:
#   MARKETING_VERSION      (e.g. "1.1")  — user-facing version
#   CURRENT_PROJECT_VERSION (e.g. "2")   — MUST increase; Sparkle compares this
#
# Usage: ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

REPO="tareq1988/kotha"
APP="/Applications/Kotha.app"
DIST="dist"
APPCAST="appcast.xml"
SIGN_TOOL="build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

echo "→ Building release…"
./build.sh >/dev/null

SHORT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
TAG="v$SHORT"
ZIP="$DIST/Kotha-$SHORT.zip"
URL="https://github.com/$REPO/releases/download/$TAG/Kotha-$SHORT.zip"

[ -x "$SIGN_TOOL" ] || { echo "✗ sign_update not found at $SIGN_TOOL"; exit 1; }
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "✗ Release $TAG already exists. Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION first."; exit 1
fi
if grep -q ">Kotha $SHORT<" "$APPCAST"; then
    echo "✗ $APPCAST already has an entry for $SHORT."; exit 1
fi

mkdir -p "$DIST"; rm -f "$ZIP"
echo "→ Packaging $ZIP (build $BUILD)…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "→ EdDSA-signing…"
SIG=$("$SIGN_TOOL" "$ZIP")          # -> sparkle:edSignature="…" length="…"
DATE=$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")

ITEM="        <item>
            <title>Kotha $SHORT</title>
            <pubDate>$DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$SHORT</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url=\"$URL\" $SIG type=\"application/octet-stream\"/>
        </item>"

# Newest item goes right after the <!-- ITEMS --> marker.
python3 - "$APPCAST" "$ITEM" <<'PY'
import sys
path, item = sys.argv[1], sys.argv[2]
xml = open(path).read()
xml = xml.replace("<!-- ITEMS -->", "<!-- ITEMS -->\n" + item, 1)
open(path, "w").write(xml)
PY
echo "→ Updated $APPCAST"

echo "→ Publishing appcast + release…"
git add "$APPCAST"
git commit -q -m "Release $SHORT"
git push -q origin main
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Kotha $SHORT" \
    --notes "Kotha $SHORT. Existing users update automatically via Sparkle."

echo "✓ Released $SHORT ($TAG)."
