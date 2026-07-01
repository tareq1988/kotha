#!/bin/bash
# Standardized release — one command cuts a Sparkle auto-update release.
#
#   ./release.sh <version> [release notes]
#   ./release.sh 1.2
#   ./release.sh 1.2 "Fix paste on Sonoma; faster startup"
#
# It bumps the version, builds, packages, EdDSA-signs, updates the appcast,
# commits + tags + pushes, and creates the GitHub release with the zip attached.
# See RELEASING.md for details.
set -euo pipefail
cd "$(dirname "$0")"

REPO="tareq1988/kotha"
APP="/Applications/Kotha.app"
DIST="dist"
APPCAST="appcast.xml"
SIGN_TOOL="build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

die() { echo "✗ $1" >&2; exit 1; }

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
  || die "Usage: ./release.sh <version> [notes]   e.g. ./release.sh 1.2"
NOTES="${2:-Kotha $VERSION. Existing users update automatically via Sparkle.}"
TAG="v$VERSION"

# ---- pre-flight -------------------------------------------------------------
command -v gh       >/dev/null || die "gh (GitHub CLI) not found."
command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)."
gh auth status >/dev/null 2>&1 || die "gh not authenticated (gh auth login)."
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "Not on the main branch."
git diff --quiet && git diff --cached --quiet || die "Working tree not clean — commit or stash first."
git fetch -q origin main
[ "$(git rev-list --count HEAD..origin/main)" -eq 0 ] || die "Local main is behind origin — pull first."
git rev-parse "$TAG" >/dev/null 2>&1 && die "Tag $TAG already exists."
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && die "Release $TAG already exists."
grep -q ">Kotha $VERSION<" "$APPCAST" && die "$APPCAST already has an entry for $VERSION."

# Revert the version bump if anything fails before we commit, so re-running is clean.
COMMITTED=0
trap '[ "$COMMITTED" -eq 0 ] && git checkout -- project.yml Sources/App/Info.plist "$APPCAST" 2>/dev/null || true' EXIT

# ---- bump versions ----------------------------------------------------------
CUR_BUILD=$(grep -E 'CURRENT_PROJECT_VERSION:' project.yml | grep -oE '[0-9]+' | head -1)
NEXT_BUILD=$((CUR_BUILD + 1))
echo "→ Releasing $VERSION (build $NEXT_BUILD)…"
sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$NEXT_BUILD\"/" project.yml

# ---- build & verify ---------------------------------------------------------
echo "→ Building…"
xcodegen generate >/dev/null
./build.sh >/dev/null
SHORT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
[ "$SHORT" = "$VERSION" ]    || die "Built version $SHORT != $VERSION (version keys not wired?)."
[ "$BUILD" = "$NEXT_BUILD" ] || die "Built build $BUILD != $NEXT_BUILD."

# ---- package & sign ---------------------------------------------------------
[ -x "$SIGN_TOOL" ] || die "sign_update not found — run ./build.sh once so SPM fetches Sparkle."
mkdir -p "$DIST"; ZIP="$DIST/Kotha-$VERSION.zip"; rm -f "$ZIP"
echo "→ Packaging & EdDSA-signing $ZIP…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIG=$("$SIGN_TOOL" "$ZIP")   # -> sparkle:edSignature="…" length="…"
URL="https://github.com/$REPO/releases/download/$TAG/Kotha-$VERSION.zip"
DATE=$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")

ITEM="        <item>
            <title>Kotha $VERSION</title>
            <pubDate>$DATE</pubDate>
            <sparkle:version>$NEXT_BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url=\"$URL\" $SIG type=\"application/octet-stream\"/>
        </item>"
python3 - "$APPCAST" "$ITEM" <<'PY'
import sys
path, item = sys.argv[1], sys.argv[2]
xml = open(path).read()
open(path, "w").write(xml.replace("<!-- ITEMS -->", "<!-- ITEMS -->\n" + item, 1))
PY

# ---- commit, tag, push, release --------------------------------------------
echo "→ Committing, tagging, pushing…"
git add project.yml Sources/App/Info.plist "$APPCAST"
git commit -q -m "Release $VERSION"
COMMITTED=1
git tag -a "$TAG" -m "Kotha $VERSION"
git push -q origin main
git push -q origin "$TAG"

echo "→ Creating GitHub release…"
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Kotha $VERSION" --notes "$NOTES" --verify-tag \
  || die "Push done, but release upload failed. Finish with:
    gh release create $TAG \"$ZIP\" --title \"Kotha $VERSION\" --notes \"$NOTES\" --verify-tag"

echo "✓ Released $VERSION → https://github.com/$REPO/releases/tag/$TAG"
