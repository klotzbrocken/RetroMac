#!/bin/bash
# download_dock_icons.sh
# Extracts app icons from the local system for use in RetroMac dock themes.
# Only extracts icons from apps installed on YOUR system -- no external downloads.
# Usage: ./download_dock_icons.sh [theme-dir]

set -e

THEME_DIR="${1:-Resources/Themes/MacOSX-Aqua.retromactheme/icons}"
ICON_SIZE="${2:-128}"

mkdir -p "$THEME_DIR"

declare -A APPS=(
    [finder]="/System/Library/CoreServices/Finder.app"
    [safari]="/Applications/Safari.app"
    [mail]="/System/Applications/Mail.app"
    [photos]="/System/Applications/Photos.app"
    [messages]="/System/Applications/Messages.app"
    [notes]="/System/Applications/Notes.app"
    [calendar]="/System/Applications/Calendar.app"
    [settings]="/System/Applications/System Settings.app"
    [music]="/System/Applications/Music.app"
    [terminal]="/System/Applications/Utilities/Terminal.app"
)

for name in "${!APPS[@]}"; do
    app_path="${APPS[$name]}"
    out_path="$THEME_DIR/${name}.png"

    if [ ! -d "$app_path" ]; then
        echo "SKIP $name -- $app_path not found"
        continue
    fi

    # Find the .icns file
    icns=""
    plist="$app_path/Contents/Info.plist"
    if [ -f "$plist" ]; then
        icon_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$plist" 2>/dev/null || true)
        if [ -n "$icon_name" ]; then
            # Add .icns extension if missing
            [[ "$icon_name" != *.icns ]] && icon_name="${icon_name}.icns"
            icns="$app_path/Contents/Resources/$icon_name"
        fi
    fi

    if [ ! -f "$icns" ]; then
        echo "SKIP $name -- no icon found in $app_path"
        continue
    fi

    # Convert .icns to .png at desired size
    sips -s format png -z "$ICON_SIZE" "$ICON_SIZE" "$icns" --out "$out_path" >/dev/null 2>&1
    if [ -f "$out_path" ]; then
        echo "OK   $name (${ICON_SIZE}x${ICON_SIZE}) -> $out_path"
    else
        echo "FAIL $name -- sips conversion failed"
    fi
done

echo ""
echo "Done. Icons saved to $THEME_DIR"
