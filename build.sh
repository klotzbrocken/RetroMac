#!/bin/bash
set -e
cd "$(dirname "$0")"

MODE="${1:-debug}"

# Use Developer ID for release builds (distributable), Apple Development for debug
if [ "$MODE" = "release" ]; then
    SIGN_ID="Developer ID Application: Maik Klotz (FTJLR8JRNS)"
    SIGN_FLAGS="--timestamp --options runtime"
    APP_ENTITLEMENTS="RetroMac-release.entitlements"
else
    SIGN_ID="Apple Development: Maik Klotz (VB63U5MZD7)"
    SIGN_FLAGS="--timestamp=none"
    APP_ENTITLEMENTS="RetroMac.entitlements"
fi
echo "Building RetroMac ($MODE, signing: $(echo "$SIGN_ID" | cut -d: -f1))..."

swift build -c "$MODE" --product RetroMac 2>&1 | tee /tmp/retromac_build.log | tail -3
if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "❌ RetroMac build FAILED:"; cat /tmp/retromac_build.log; exit 1; fi

echo "Building Camera Extension..."
swift build -c "$MODE" --product RetroMacCameraExtension 2>&1 | tee /tmp/retromac_ext_build.log | tail -3
if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "❌ Camera Extension build FAILED:"; cat /tmp/retromac_ext_build.log; exit 1; fi

# --- Camera Extension .systemextension bundle ---
EXT_BUNDLE=".build/com.retromac.app.camera.systemextension"
EXT_CONTENTS="$EXT_BUNDLE/Contents"
mkdir -p "$EXT_CONTENTS/MacOS"

cp ".build/$MODE/RetroMacCameraExtension" "$EXT_CONTENTS/MacOS/RetroMacCameraExtension"
cp CameraExtension-Info.plist "$EXT_CONTENTS/Info.plist"

codesign --force --sign "$SIGN_ID" \
    --entitlements CameraExtension.entitlements \
    --identifier "com.retromac.app.camera" \
    $SIGN_FLAGS \
    --generate-entitlement-der \
    "$EXT_BUNDLE"

echo "  ✓ Camera Extension built"

# --- Main App Bundle ---
APP_BUNDLE=".build/RetroMac.app"
CONTENTS="$APP_BUNDLE/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Library/SystemExtensions"

cp ".build/$MODE/RetroMac" "$CONTENTS/MacOS/RetroMac"
# Add rpath so dyld finds Sparkle.framework in Contents/Frameworks
install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS/MacOS/RetroMac" 2>/dev/null || true
cp Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
cp Resources/menubar_icon.png "$CONTENTS/Resources/menubar_icon.png"
cp Resources/menubar_icon@2x.png "$CONTENTS/Resources/menubar_icon@2x.png"

# Copy dock themes
if [ -d "Resources/Themes" ]; then
    mkdir -p "$CONTENTS/Resources/Themes"
    rsync -a --delete Resources/Themes/ "$CONTENTS/Resources/Themes/"
fi

# Copy sounds
if [ -d "Resources/Sounds" ]; then
    mkdir -p "$CONTENTS/Resources/Sounds"
    rsync -a --delete Resources/Sounds/ "$CONTENTS/Resources/Sounds/"
fi

# Embed Camera Extension in app bundle
rsync -a --delete "$EXT_BUNDLE/" "$CONTENTS/Library/SystemExtensions/com.retromac.app.camera.systemextension/"

# Embed Sparkle.framework
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    mkdir -p "$CONTENTS/Frameworks"
    rsync -a --delete "$SPARKLE_FW/" "$CONTENTS/Frameworks/Sparkle.framework/"
    # Deep-sign Sparkle: inner bundles first, then outer framework
    codesign --force --sign "$SIGN_ID" $SIGN_FLAGS \
        "$CONTENTS/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --sign "$SIGN_ID" $SIGN_FLAGS \
        "$CONTENTS/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    codesign --force --sign "$SIGN_ID" $SIGN_FLAGS \
        "$CONTENTS/Frameworks/Sparkle.framework/Versions/B/Updater.app"
    codesign --force --sign "$SIGN_ID" $SIGN_FLAGS \
        "$CONTENTS/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
    codesign --force --sign "$SIGN_ID" $SIGN_FLAGS \
        "$CONTENTS/Frameworks/Sparkle.framework"
    echo "  ✓ Sparkle.framework embedded & signed"
fi

cat > "$CONTENTS/PkgInfo" <<'PKG'
APPL????
PKG

# Embed provisioning profile (required for system-extension.install entitlement)
if [ "$MODE" = "release" ]; then
    PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/RetroMac_Developer_ID.provisionprofile"
else
    PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/80aeb44c-9e5a-4578-892e-092ebc27c57f.provisionprofile"
fi
if [ -f "$PROFILE" ]; then
    cp "$PROFILE" "$CONTENTS/embedded.provisionprofile"
    echo "  ✓ Provisioning profile embedded"
else
    echo "  ⚠ Provisioning profile not found — system extension activation may fail"
fi

# Sign the main app (extension must be signed first, then app wraps it)
codesign --force --sign "$SIGN_ID" \
    --entitlements "$APP_ENTITLEMENTS" \
    --identifier "com.retromac.app" \
    $SIGN_FLAGS \
    --generate-entitlement-der \
    "$APP_BUNDLE"

# Install to /Applications (required for system extension activation)
rm -rf /Applications/RetroMac.app
cp -R "$APP_BUNDLE" /Applications/RetroMac.app
echo "  ✓ Installed to /Applications"

echo ""
echo "✓ Built and installed /Applications/RetroMac.app ($MODE)"
echo "  ✓ Camera Extension embedded in Library/SystemExtensions"
echo "  Run:  open /Applications/RetroMac.app"
echo ""
echo "First launch: grant Screen Recording + Camera in System Settings → Privacy & Security"
