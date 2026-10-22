#!/bin/bash
# Makes Scripts/dmg/DS_Store: the Finder layout of the release DMG's window, which package.sh
# copies in. Only Finder writes that file, so this opens a Finder window on a scratch disk image
# for a few seconds. Run it again only when the window or the background changes.
set -euo pipefail
cd "$(dirname "$0")"
VOL="RetroMac"
[ -e "/Volumes/$VOL" ] && { echo "Eject /Volumes/$VOL first."; exit 1; }
TMP=$(mktemp -d)
trap 'hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src/RetroMac.app" "$TMP/src/.background"
ln -s /Applications "$TMP/src/Applications"
cp background.tiff "$TMP/src/.background/background.tiff"
hdiutil create -volname "$VOL" -srcfolder "$TMP/src" -ov -format UDRW "$TMP/layout.dmg" >/dev/null
hdiutil attach "$TMP/layout.dmg" -noautoopen >/dev/null

osascript <<EOF
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 520}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "RetroMac.app" of container window to {150, 170}
        set position of item "Applications" of container window to {450, 170}
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
sleep 2
cp "/Volumes/$VOL/.DS_Store" DS_Store
echo "✓ Scripts/dmg/DS_Store written"
