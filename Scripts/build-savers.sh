#!/bin/bash
# Builds the four RetroMac screensavers as REAL macOS .saver bundles.
# Each bundle is a WKWebView host (scripts/saver/RetroMacSaverView.swift) plus the
# same HTML/canvas saver the in-app screensaver uses.
# Output: Resources/Savers/<Name>.saver (shipped in the app; installed from Settings).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=scripts/saver/RetroMacSaverView.swift
OUT=Resources/Savers
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# name : source HTML dir (under Resources/Widgets/Screensavers)
SAVERS=(
  "RetroMac Pipes:Pipes"
  "RetroMac FlowerBox:FlowerBox"
  "RetroMac Flying Toasters:FlyingToasters"
  "RetroMac Flurry:Flurry"
)

# Compile once per arch, lipo into a universal loadable library.
for arch in arm64 x86_64; do
  swiftc -parse-as-library -emit-library "$SRC" \
    -o "$TMP/lib-$arch" -module-name RetroMacSaver \
    -framework ScreenSaver -framework WebKit \
    -target "$arch-apple-macos13.0" 2>/dev/null
done
lipo -create "$TMP/lib-arm64" "$TMP/lib-x86_64" -output "$TMP/RetroMacSaver"

rm -rf "$OUT"; mkdir -p "$OUT"
for entry in "${SAVERS[@]}"; do
  name="${entry%%:*}"; srcdir="${entry##*:}"
  bundle="$OUT/$name.saver"
  mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/saver"
  cp "$TMP/RetroMacSaver" "$bundle/Contents/MacOS/$name"
  cp -R "Resources/Widgets/Screensavers/$srcdir/." "$bundle/Contents/Resources/saver/"
  ident="com.retromac.saver.$(echo "$srcdir" | tr '[:upper:]' '[:lower:]')"
  cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$ident</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>RetroMacSaverView</string>
</dict></plist>
PLIST
  codesign --force --deep -s - "$bundle" 2>/dev/null || true
  echo "built: $bundle"
done
du -sh "$OUT"
