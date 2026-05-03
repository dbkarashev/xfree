#!/usr/bin/env bash
# Builds an unsigned (ad-hoc) DMG of X Free for distribution.
#
# We don't have a paid Apple Developer Program membership, so notarization
# is off the table. The script builds with whatever cert the project ships
# with, then strips the development provisioning profile and re-signs the
# bundle ad-hoc — that lets the app launch on any Mac without crashing on
# profile validation. Gatekeeper still says "unidentified developer" on
# first run; users right-click → Open → Open in the dialog once.
#
# Usage:
#   scripts/release.sh 1.2.3
#
# Output:
#   dist/X Free 1.2.3.dmg
#
# Publish:
#   gh release create v1.2.3 "dist/X Free 1.2.3.dmg" --title v1.2.3 --notes "…"

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <version>" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="X Free.app"
APP_PATH="$DIST/$APP_NAME"
DMG="$DIST/X Free $VERSION.dmg"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Building Release"
xcodebuild -project "$ROOT/XFree.xcodeproj" \
    -scheme XFree \
    -configuration Release \
    -derivedDataPath "$DIST/build" \
    MARKETING_VERSION="$VERSION" \
    build

BUILT_APP="$DIST/build/Build/Products/Release/$APP_NAME"
cp -R "$BUILT_APP" "$APP_PATH"

echo "==> Stripping dev provisioning profile, re-signing ad-hoc"
rm -f "$APP_PATH/Contents/embedded.provisionprofile"
codesign --remove-signature "$APP_PATH"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --verbose=2 "$APP_PATH"

echo "==> Building DMG"
hdiutil create \
    -volname "X Free" \
    -srcfolder "$APP_PATH" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG"

echo
echo "Built $DMG"
echo "Publish with:"
echo "  gh release create v$VERSION \"$DMG\" --title v$VERSION --notes \"…\""
echo
echo "First-launch UX: users right-click the app → Open → Open in the dialog."
