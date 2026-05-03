#!/usr/bin/env bash
# Cuts a signed, notarized DMG of X Free.
#
# One-time setup
# --------------
# 1. In Xcode → Settings → Accounts, sign in with your Apple ID and confirm the
#    "Developer ID Application" certificate is in your Login keychain.
# 2. Generate an app-specific password at https://appleid.apple.com → Sign-In
#    and Security → App-Specific Passwords.
# 3. Store notary credentials in the keychain (no plaintext secrets in this
#    repo, no env vars to leak):
#
#      xcrun notarytool store-credentials xfree-notary \
#          --apple-id  you@example.com \
#          --team-id   4LFT68A7T5 \
#          --password  <app-specific-password>
#
#    Override the profile name via XFREE_NOTARY_PROFILE if you prefer.
#
# Usage
# -----
#   scripts/release.sh 1.2.3
#
# Output
# ------
#   dist/X Free 1.2.3.dmg — signed, notarized, stapled.
#
# Publish
# -------
#   gh release create v1.2.3 "dist/X Free 1.2.3.dmg" --title v1.2.3 --notes "…"

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <version>" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
ARCHIVE="$DIST/XFree.xcarchive"
APP="$DIST/X Free.app"
DMG="$DIST/X Free $VERSION.dmg"

NOTARY_PROFILE="${XFREE_NOTARY_PROFILE:-xfree-notary}"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Archiving"
xcodebuild -project "$ROOT/XFree.xcodeproj" \
    -scheme XFree \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" \
    archive

echo "==> Exporting Developer ID app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$DIST" \
    -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist"

echo "==> Building DMG"
hdiutil create \
    -volname "X Free" \
    -srcfolder "$APP" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG"

echo "==> Notarizing (a few minutes)"
xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo
echo "Built $DMG"
echo "Publish with:"
echo "  gh release create v$VERSION \"$DMG\" --title v$VERSION --notes \"…\""
