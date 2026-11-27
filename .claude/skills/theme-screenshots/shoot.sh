#!/bin/bash
# Screenshot set of RetroMac themes in the dev app, three variants each:
#   1-clean    the desktop only
#   2-menu     the theme's main menu open (Start, K menu, Apple menu, ...) and the pointer resting on a dock item
#   3-windows  an empty TextEdit document under the theme's title bar, the theme's Read Me, and the main menu
# Only the desktop picture, the menu bar, RetroMac and TextEdit are captured; the user's windows stay out.
#
# usage: shoot.sh <outdir> <theme-id> [<theme-id> ...]
# Themes that keep the Mac menu bar wait until the Finder is in front (the user presses Cmd-Tab):
# macOS does not let a script bring another app forward while the user's app is active.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$1"; shift
APP="/Applications/RetroMac Dev.app"
DOMAIN=com.retromac.app.dev
THEMES_DIR="$(cd "$HERE/../../.." && pwd)/Resources/Themes"
HOVER=${RETROMAC_SHOT_HOVER:-3}   # dock item the pointer rests on in variant 2
mkdir -p "$OUT"

BIN="${TMPDIR:-/tmp}/retromac-capture"
[ "$BIN" -nt "$HERE/capture.swift" ] || swiftc -O "$HERE/capture.swift" -o "$BIN" 2>/dev/null || { echo "capture did not compile"; exit 1; }

front() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null; }
quit_app() { osascript -e "quit app \"RetroMac Dev\"" >/dev/null 2>&1; sleep 4; }
launch() {   # launch <theme> <env assignments...>
  local t=$1; shift
  quit_app
  defaults write $DOMAIN dockTheme "$t"
  env RETROMAC_AUTOACTIVATE_THEME=1 "$@" nohup "$APP/Contents/MacOS/RetroMac" >/dev/null 2>&1 &
  sleep 9
}
manifest() { grep -l "\"id\": \"$1\"" "$THEMES_DIR"/*/theme.json 2>/dev/null | head -1; }

OLD_THEME=$(defaults read $DOMAIN dockTheme 2>/dev/null)
OLD_BOOT=$(defaults read $DOMAIN bootPhaseMode 2>/dev/null)
TEXTEDIT_RAN=$(pgrep -xq TextEdit && echo 1 || echo 0)
restore() {
  quit_app
  [ -n "$OLD_THEME" ] && defaults write $DOMAIN dockTheme "$OLD_THEME"
  if [ -n "$OLD_BOOT" ]; then defaults write $DOMAIN bootPhaseMode "$OLD_BOOT"; else defaults delete $DOMAIN bootPhaseMode 2>/dev/null; fi
  [ "$TEXTEDIT_RAN" = 0 ] && osascript -e 'quit app "TextEdit" saving no' >/dev/null 2>&1
}
trap restore EXIT
defaults write $DOMAIN bootPhaseMode desktop   # no boot film between the shots

for T in "$@"; do
  M=$(manifest "$T"); [ -z "$M" ] && { echo "$T: no such theme"; continue; }
  NAME=$(basename "$(dirname "$M")" .retromactheme)
  MACBAR=$(grep -q '"hideMenuBarDefault": true' "$M" && echo 0 || echo 1)
  # Shoot only with the Finder in front: the Mac menu bar shows whichever app is. Asked again
  # before every picture, as the Finder can lose the front between the restarts.
  shot() {
    if [ "$MACBAR" = 1 ] && [ "$(front)" != Finder ]; then
      echo "$NAME: waiting for the Finder in front (Cmd-Tab to the Finder)..."
      for i in $(seq 300); do [ "$(front)" = Finder ] && break; sleep 1; done
      [ "$(front)" = Finder ] || { echo "$NAME: Finder never came forward, $1 skipped"; return 1; }
      sleep 1
    fi
    "$BIN" "$OUT/$NAME-$1.png" "${@:2}" && echo "$NAME-$1.png"
  }

  launch "$T" RETROMAC_ONLY_APPS=none
  shot 1-clean

  launch "$T" RETROMAC_ONLY_APPS=none RETROMAC_OPEN_START_MENU=1 RETROMAC_HOVER_DOCK=$HOVER
  shot 2-menu

  # A script-launched TextEdit starts hidden; unhiding does not bring it in front of the user's app.
  DOC=$(osascript -e 'tell application "TextEdit" to return name of (make new document)' 2>/dev/null)
  osascript -e 'tell application "System Events" to set visible of process "TextEdit" to true' \
            -e "tell application \"TextEdit\" to set bounds of (first window whose name is \"$DOC\") to {1040, 120, 1450, 520}" >/dev/null 2>&1
  launch "$T" RETROMAC_ONLY_APPS=com.apple.TextEdit RETROMAC_OPEN_README=1 RETROMAC_OPEN_START_MENU=1
  shot 3-windows com.apple.TextEdit
  [ -n "$DOC" ] && osascript -e "tell application \"TextEdit\" to close document \"$DOC\" saving no" >/dev/null 2>&1 || true
done
