#!/bin/bash
# Creates a notarized DMG for distribution.
#
# Prerequisites:
#   1. Developer ID Application certificate installed
#   2. App-specific password stored in keychain:
#      xcrun notarytool store-credentials "RetroMac" \
#        --apple-id maik.klotz@me.com --team-id FTJLR8JRNS
#   3. Developer ID provisioning profile for com.retromac.app
#
# Usage:
#   ./package.sh              # build, package, notarize
#   ./package.sh --skip-build # package existing build
set -e
cd "$(dirname "$0")"

SKIP_BUILD=false
[ "$1" = "--skip-build" ] && SKIP_BUILD=true

APP_NAME="RetroMac"
APP_BUNDLE=".build/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_DIR=".build/dmg-staging"
KEYCHAIN_PROFILE="Retromac"

# --- Step 1: Release build ---
if [ "$SKIP_BUILD" = false ]; then
    echo "=== Building release ==="
    ./build.sh release
else
    echo "=== Skipping build (using existing app) ==="
fi

# Verify signature and identity stability
echo ""
echo "=== Verifying code signature ==="
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -5
echo "  ✓ Signature valid"

# Verify release identity: Team ID, Bundle ID, designated requirement
echo ""
echo "=== Verifying release identity (TCC stability) ==="
DR=$(codesign -d -r- "$APP_BUNDLE" 2>&1)
echo "$DR"
echo "$DR" | grep -q 'identifier "com.retromac.app"' || { echo "❌ Bundle ID mismatch!"; exit 1; }
echo "$DR" | grep -q 'FTJLR8JRNS' || { echo "❌ Team ID mismatch!"; exit 1; }
spctl -a -vvv -t exec "$APP_BUNDLE" 2>&1 | tail -3
echo "  ✓ Identity stable (com.retromac.app / FTJLR8JRNS)"

# --- Step 2: Create DMG ---
echo ""
echo "=== Creating DMG ==="
rm -rf "$DMG_DIR" "$DMG_NAME"
mkdir -p "$DMG_DIR"
cp -R "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_NAME"

rm -rf "$DMG_DIR"
echo "  ✓ DMG created: $DMG_NAME ($(du -h "$DMG_NAME" | cut -f1))"

# --- Step 3: Notarize ---
echo ""
echo "=== Submitting for notarization ==="
echo "  (this may take a few minutes)"
xcrun notarytool submit "$DMG_NAME" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

# --- Step 4: Staple ---
echo ""
echo "=== Stapling notarization ticket ==="
xcrun stapler staple "$DMG_NAME"

echo ""
echo "✅ Done! Distributable DMG: $(pwd)/$DMG_NAME"
echo "   Size: $(du -h "$DMG_NAME" | cut -f1)"
