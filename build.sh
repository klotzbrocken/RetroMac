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
# Release builds are Universal (Intel + Apple Silicon) for distribution.
# Debug/dev builds stay native (host arch only) for fast iteration.
if [ "$MODE" = "release" ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
else
    ARCH_FLAGS=""
fi
echo "Building RetroMac ($MODE, signing: $(echo "$SIGN_ID" | cut -d: -f1)${ARCH_FLAGS:+, Universal})..."

swift build -c "$MODE" $ARCH_FLAGS --product RetroMac 2>&1 | tee /tmp/retromac_build.log | tail -3
if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "❌ RetroMac build FAILED:"; cat /tmp/retromac_build.log; exit 1; fi

echo "Building Camera Extension..."
swift build -c "$MODE" $ARCH_FLAGS --product RetroMacCameraExtension 2>&1 | tee /tmp/retromac_ext_build.log | tail -3
if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "❌ Camera Extension build FAILED:"; cat /tmp/retromac_ext_build.log; exit 1; fi

# Resolve the products dir (differs for universal builds → use --show-bin-path)
BIN_PATH=$(swift build -c "$MODE" $ARCH_FLAGS --show-bin-path 2>/dev/null | tail -1)
echo "  Products: $BIN_PATH"

# --- Camera Extension .systemextension bundle ---
EXT_BUNDLE=".build/com.retromac.app.camera.systemextension"
EXT_CONTENTS="$EXT_BUNDLE/Contents"
mkdir -p "$EXT_CONTENTS/MacOS"

cp "$BIN_PATH/RetroMacCameraExtension" "$EXT_CONTENTS/MacOS/RetroMacCameraExtension"
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
# Strip stale orphan helper from earlier builds — grayscale now runs in-process
# (DisplayFilterHelper.swift), so this arm64-only binary must not ship (breaks
# Universal notarization and isn't referenced by any code).
rm -rf "$CONTENTS/Resources/Helpers"

cp "$BIN_PATH/RetroMac" "$CONTENTS/MacOS/RetroMac"
# Add rpath so dyld finds Sparkle.framework in Contents/Frameworks
install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS/MacOS/RetroMac" 2>/dev/null || true
cp Info.plist "$CONTENTS/Info.plist"
# Debug builds use a separate bundle ID to avoid poisoning release TCC grants
if [ "$MODE" != "release" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.retromac.app.dev" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName 'RetroMac Dev'" "$CONTENTS/Info.plist"
fi
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
cp Resources/menubar_icon.png "$CONTENTS/Resources/menubar_icon.png"
cp Resources/menubar_icon@2x.png "$CONTENTS/Resources/menubar_icon@2x.png"
cp Resources/rainbow_apple.png "$CONTENTS/Resources/rainbow_apple.png"
cp Resources/aqua_apple.png "$CONTENTS/Resources/aqua_apple.png"
cp Resources/aqua_classic_apple.png "$CONTENTS/Resources/aqua_classic_apple.png"
cp Resources/apple_hell.png "$CONTENTS/Resources/apple_hell.png"

# Copy dock themes
if [ -d "Resources/Themes" ]; then
    mkdir -p "$CONTENTS/Resources/Themes"
    # 'icons-library/' holds source/staging art (e.g. the extracted System 6 icon set) that is
    # kept in the repo but must never ship in the bundle.
    rsync -a --delete --delete-excluded --exclude 'icons-library' --exclude '*.md' Resources/Themes/ "$CONTENTS/Resources/Themes/"
fi

# Copy sounds
if [ -d "Resources/Sounds" ]; then
    mkdir -p "$CONTENTS/Resources/Sounds"
    rsync -a --delete Resources/Sounds/ "$CONTENTS/Resources/Sounds/"
fi

# Copy desktop widgets (e.g. BeOS CPU Monitor HTML widget)
if [ -d "Resources/Widgets" ]; then
    mkdir -p "$CONTENTS/Resources/Widgets"
    rsync -a --delete Resources/Widgets/ "$CONTENTS/Resources/Widgets/"
fi

# Tube Mode bezel catalog
if [ -d "Resources/TV" ]; then
    mkdir -p "$CONTENTS/Resources/TV"
    rsync -a --delete Resources/TV/ "$CONTENTS/Resources/TV/"
fi

if [ -d "Resources/Cursors" ]; then
    mkdir -p "$CONTENTS/Resources/Cursors"
    rsync -a --delete Resources/Cursors/ "$CONTENTS/Resources/Cursors/"
fi

# Window-chrome glyph assets (XP.css caption buttons etc.)
if [ -d "Resources/Chrome" ]; then
    mkdir -p "$CONTENTS/Resources/Chrome"
    rsync -a --delete Resources/Chrome/ "$CONTENTS/Resources/Chrome/"
fi

# Real .saver screensaver modules (built by scripts/build-savers.sh)
if [ -d "Resources/Savers" ]; then
    mkdir -p "$CONTENTS/Resources/Savers"
    rsync -a --delete Resources/Savers/ "$CONTENTS/Resources/Savers/"
    # The .saver bundles ship ad-hoc signed (from build-savers.sh); re-sign their
    # Mach-O + bundle with the release identity so notarization accepts them.
    for saver in "$CONTENTS/Resources/Savers/"*.saver; do
        [ -d "$saver" ] || continue
        codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$saver/Contents/MacOS/"* 2>/dev/null
        codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$saver" 2>/dev/null
    done
fi

# Copy Doom CRT shader PK3
if [ -f "Resources/RetroMac-CRT.pk3" ]; then
    cp Resources/RetroMac-CRT.pk3 "$CONTENTS/Resources/RetroMac-CRT.pk3"
fi

# Copy Duke Nukem 3D shareware GRP (if bundled)
if [ -f "Resources/DUKE3D.GRP" ]; then
    cp Resources/DUKE3D.GRP "$CONTENTS/Resources/DUKE3D.GRP"
    echo "  ✓ Duke Nukem 3D shareware bundled"
fi

# Embed Camera Extension in app bundle
rsync -a --delete "$EXT_BUNDLE/" "$CONTENTS/Library/SystemExtensions/com.retromac.app.camera.systemextension/"

# Embed Sparkle.framework
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    mkdir -p "$CONTENTS/Frameworks"
    rsync -a --delete "$SPARKLE_FW/" "$CONTENTS/Frameworks/Sparkle.framework/"
    SPK_B="$CONTENTS/Frameworks/Sparkle.framework/Versions/B"
    if [ "$MODE" = "release" ]; then
        # Deep-sign Sparkle: inner bundles first, then outer framework
        codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$SPK_B/XPCServices/Downloader.xpc"
        codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$SPK_B/XPCServices/Installer.xpc"
        codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$SPK_B/Updater.app"
        codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$SPK_B/Autoupdate"
    else
        # Debug: the auto-updater is disabled in .dev builds, so drop Sparkle's helper bundles.
        # Otherwise the Apple-Development-signed Updater.app shares the bundle id
        # org.sparkle-project.Sparkle.Updater with an installed release app, and LaunchServices
        # can launch the (Gatekeeper-rejected) dev copy → "An error occurred while launching the
        # installer" for the RELEASE app. The Sparkle dylib stays, so the app still links/launches.
        rm -rf "$SPK_B/XPCServices" "$SPK_B/Updater.app" "$SPK_B/Autoupdate"
    fi
    codesign --force --sign "$SIGN_ID" $SIGN_FLAGS \
        "$CONTENTS/Frameworks/Sparkle.framework"
    echo "  ✓ Sparkle.framework embedded & signed"
fi

# --- BeOS Pac-Man demo (built from vendored GPLv2 source in vendor/pacman) ---
if [ -d "vendor/pacman/src" ] && [ -d "/opt/homebrew/include/SDL2" ]; then
    PAC_APP="$CONTENTS/Resources/Games/Pacman.app"
    PAC_C="$PAC_APP/Contents"
    rm -rf "$PAC_APP"; mkdir -p "$PAC_C/MacOS" "$PAC_C/Resources" "$PAC_C/Frameworks"
    if clang++ -std=c++14 -O2 -I/opt/homebrew/include -Ivendor/pacman/src \
         -DPACKAGE_DATA_DIR='"/unused"' \
         vendor/pacman/src/*.cpp -L/opt/homebrew/lib -lSDL2main -lSDL2 -lSDL2_ttf -lSDL2_mixer \
         -o "$PAC_C/MacOS/pacman" 2>/tmp/pacman_build.log; then
        cp -R vendor/pacman/data "$PAC_C/Resources/data"
        cat > "$PAC_C/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Pacman</string>
<key>CFBundleIdentifier</key><string>com.retromac.demo.pacman</string>
<key>CFBundleVersion</key><string>0.9.4</string>
<key>CFBundleShortVersionString</key><string>0.9.4</string>
<key>CFBundleExecutable</key><string>pacman</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
        command -v dylibbundler >/dev/null 2>&1 && \
            dylibbundler -of -cd -b -x "$PAC_C/MacOS/pacman" -d "$PAC_C/Frameworks" -p @executable_path/../Frameworks >/dev/null 2>&1
        for dy in "$PAC_C/Frameworks/"*.dylib; do [ -f "$dy" ] && codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$dy"; done
        codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$PAC_C/MacOS/pacman"
        codesign --force --sign "$SIGN_ID" $SIGN_FLAGS --identifier "com.retromac.demo.pacman" "$PAC_APP"
        echo "  ✓ Pac-Man demo built & embedded"
    else
        echo "  ⚠ Pac-Man demo build failed (see /tmp/pacman_build.log) — skipping"
    fi
else
    echo "  ⚠ SDL2/vendor sources missing — Pac-Man demo not bundled"
fi

# --- Warcraft I + II via Stratagus (GPL-2 engine, vendored as submodules) ---
# Compiling the engine takes minutes, so it is CACHED: it only builds when the binaries
# are missing. The submodules are fetched on demand — a plain clone of RetroMac never
# downloads them. Unlike Pac-Man, the result needs no Homebrew at all: SDL and friends
# are statically linked from the engine's own third-party tree.
WC_BUILD="vendor/peonpad/build/macos"
if [ ! -x "$WC_BUILD/stratagus" ] && command -v cmake >/dev/null 2>&1; then
    if [ ! -f "vendor/peonpad/CMakeLists.txt" ]; then
        echo "  ⏳ Fetching Warcraft engine submodules (one-time)…"
        git submodule update --init --depth 1 vendor/peonpad vendor/war1gus >/dev/null 2>&1 || true
    fi
    if [ -f "vendor/peonpad/CMakeLists.txt" ]; then
        echo "  ⏳ Building Stratagus engine (one-time, a few minutes)…"
        cmake -S vendor/peonpad -B "$WC_BUILD" -G "Unix Makefiles" \
            -DPEONPAD_ENABLE_ENGINE=ON -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release \
            -DPEONPAD_MACOS_ARCHITECTURE=arm64 -DPEONPAD_MACOS_DEPLOYMENT_TARGET=13.0 \
            >/tmp/wargus_build.log 2>&1 \
          && cmake --build "$WC_BUILD" --target peonpad_macos -j 8 >>/tmp/wargus_build.log 2>&1 \
          || echo "  ⚠ Stratagus build failed (see /tmp/wargus_build.log)"
    fi
fi

if [ -x "$WC_BUILD/stratagus" ]; then
    WC_DIR="$CONTENTS/Resources/Games/Warcraft"
    rm -rf "$WC_DIR"; mkdir -p "$WC_DIR"
    cp "$WC_BUILD/stratagus" "$WC_DIR/stratagus"
    [ -x "$WC_BUILD/wargus/wartool" ] && cp "$WC_BUILD/wargus/wartool" "$WC_DIR/wartool"
    # Ship the GPL game logic only; the media half always comes from the user's own copy
    # of the game. The engine's OWN scripts must be used — some distributions (e.g. the
    # PS Vita release) ship scripts patched for engine functions this build doesn't have.
    for pair in "wc2:vendor/peonpad/game/wargus" "wc1:vendor/war1gus"; do
        key="${pair%%:*}"; src="${pair#*:}"
        [ -d "$src/scripts" ] || continue
        mkdir -p "$WC_DIR/$key-base"
        # NOT shaders/: all seven of the game's own .cg.glsl files redeclare GLSL built-ins
        # (gl_Vertex, gl_MultiTexCoord0), which macOS' stricter compiler rejects — they would
        # only cost startup time and log noise. The engine's built-in CRT/VHS/xBRZ work.
        for d in scripts campaigns maps contrib; do
            [ -d "$src/$d" ] && cp -R "$src/$d" "$WC_DIR/$key-base/$d"
        done
    done
    codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$WC_DIR/stratagus"
    [ -f "$WC_DIR/wartool" ] && codesign --force --sign "$SIGN_ID" $SIGN_FLAGS "$WC_DIR/wartool"
    echo "  ✓ Warcraft engine (Stratagus) + WC1/WC2 game logic embedded"
else
    echo "  ⚠ Stratagus not built — Warcraft I/II not bundled (needs: brew install cmake pkg-config)"
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
if [ "$MODE" = "release" ]; then
    APP_IDENTIFIER="com.retromac.app"
else
    APP_IDENTIFIER="com.retromac.app.dev"
fi
codesign --force --sign "$SIGN_ID" \
    --entitlements "$APP_ENTITLEMENTS" \
    --identifier "$APP_IDENTIFIER" \
    $SIGN_FLAGS \
    --generate-entitlement-der \
    "$APP_BUNDLE"

# Notarize + staple (REQUIRED: under SIP a Developer ID camera system extension only
# loads if notarized). Runs for release when 'dmg' or 'notarize' is requested.
# Credentials come from a notarytool keychain profile (default: Retromac).
NOTARY_PROFILE="${NOTARY_PROFILE:-Retromac}"
if [ "$MODE" = "release" ] && { [ "${2}" = "dmg" ] || [ "${2}" = "notarize" ] || [ "${3}" = "notarize" ]; }; then
    echo "Notarizing (profile: $NOTARY_PROFILE)…"
    NOTARIZE_ZIP="/tmp/RetroMac-notarize.zip"
    rm -f "$NOTARIZE_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZE_ZIP"
    if xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee /tmp/retromac_notarize.log | grep -q "status: Accepted"; then
        # Staple the APP ONLY. Stapling the nested .systemextension would modify a
        # resource sealed by the app's signature and break it ("sealed resource is
        # invalid"). The app's notarization ticket already covers all nested code.
        xcrun stapler staple "$APP_BUNDLE"
        echo "  ✓ Notarized & stapled"
    else
        echo "  ❌ Notarization FAILED — see /tmp/retromac_notarize.log"; exit 1
    fi
    rm -f "$NOTARIZE_ZIP"
fi

# Install — debug goes to "RetroMac Dev.app" to protect release TCC permissions
if [ "$MODE" = "release" ]; then
    INSTALL_NAME="RetroMac.app"
else
    INSTALL_NAME="RetroMac Dev.app"
fi
rm -rf "/Applications/$INSTALL_NAME"
ditto "$APP_BUNDLE" "/Applications/$INSTALL_NAME"
# Re-sign at install path (bundle name changed for dev builds)
if [ "$MODE" != "release" ]; then
    codesign --force --deep --sign "$SIGN_ID" \
        --entitlements "$APP_ENTITLEMENTS" \
        --identifier "$APP_IDENTIFIER" \
        $SIGN_FLAGS \
        --generate-entitlement-der \
        "/Applications/$INSTALL_NAME"
fi
echo "  ✓ Installed to /Applications/$INSTALL_NAME"

echo ""
echo "  Architectures: $(lipo -archs "$CONTENTS/MacOS/RetroMac" 2>/dev/null || echo unknown)"
echo "✓ Built and installed /Applications/$INSTALL_NAME ($MODE)"
echo "  ✓ Camera Extension embedded in Library/SystemExtensions"
echo "  Run:  open /Applications/$INSTALL_NAME"
echo ""
echo "First launch: grant Screen Recording + Camera in System Settings → Privacy & Security"

# Debug: relaunch the freshly built dev app. Re-selecting a theme only reloads
# resources (theme.json / widget HTML) — compiled Swift changes need a full relaunch.
if [ "$MODE" = "debug" ]; then
    echo "  ↻ Relaunching $INSTALL_NAME (loads the fresh binary)…"
    pkill -f "/Applications/$INSTALL_NAME/Contents/MacOS/RetroMac" 2>/dev/null || true
    sleep 1
    open "/Applications/$INSTALL_NAME" || true
fi

# --- DMG creation (pass 'dmg' as second arg) ---
if [ "${2}" = "dmg" ]; then
    echo ""
    echo "Creating DMG..."
    DMG_DIR=".build/dmg_staging"
    rm -rf "$DMG_DIR"
    mkdir -p "$DMG_DIR"
    cp -R "$APP_BUNDLE" "$DMG_DIR/RetroMac.app"
    ln -s /Applications "$DMG_DIR/Applications"
    rm -f RetroMac.dmg
    hdiutil create -volname "RetroMac" -srcfolder "$DMG_DIR" -ov -format UDZO RetroMac.dmg
    rm -rf "$DMG_DIR"
    echo "  ✓ RetroMac.dmg created (with Applications shortcut)"

    # Notarize + staple the DMG itself so a downloaded image passes Gatekeeper cleanly.
    if [ "$MODE" = "release" ]; then
        echo "Notarizing DMG (profile: $NOTARY_PROFILE)…"
        if xcrun notarytool submit RetroMac.dmg --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee /tmp/retromac_dmg_notarize.log | grep -q "status: Accepted"; then
            xcrun stapler staple RetroMac.dmg
            echo "  ✓ DMG notarized & stapled"
        else
            echo "  ❌ DMG notarization FAILED — see /tmp/retromac_dmg_notarize.log"; exit 1
        fi
    fi
fi
