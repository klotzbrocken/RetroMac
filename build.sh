#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building RetroMac..."
swift build -c debug 2>&1 | tail -3

APP_BUNDLE=".build/RetroMac.app"
CONTENTS="$APP_BUNDLE/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp .build/debug/RetroMac "$CONTENTS/MacOS/RetroMac"
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

cat > "$CONTENTS/PkgInfo" <<'PKG'
APPL????
PKG

# Sign with Apple Development cert so macOS TCC remembers the permission across rebuilds
codesign --force --sign "Apple Development: Maik Klotz (VB63U5MZD7)" --identifier "com.retromac.app" "$APP_BUNDLE"

echo ""
echo "✓ Built $APP_BUNDLE"
echo "  Run:  open $APP_BUNDLE"
echo ""
echo "First launch: grant Screen Recording in System Settings → Privacy & Security"
