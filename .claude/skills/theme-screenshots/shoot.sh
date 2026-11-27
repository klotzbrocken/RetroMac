#!/bin/bash
# Screenshot set of RetroMac themes in the dev app, three variants each:
#   1-clean    the desktop only
#   2-menu     the theme's main menu open (Start, K menu, Apple menu, ...) and the pointer resting on a dock item
#   3-windows  an empty TextEdit document under the theme's title bar, the theme's Read Me, and the main menu
# Only the desktop picture, the menu bar, RetroMac and TextEdit are captured; the user's windows stay out.
#
# usage: shoot.sh <outdir> <theme-id> [<theme-id> ...]
# Themes that keep the Mac menu bar are shot with the Finder in front. The script brings it forward
# when macOS lets it (while the user's Claude is in front); otherwise it waits for Cmd-Tab.
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
  # Mac menu bar themes are shot with the Finder in front, as the bar shows whichever app is.
  # RetroMac's start hands the front back to Claude, and a later switch closes an opened menu, so
  # the hooks wait (RETROMAC_QA_DELAY) while the script brings the Finder forward after the start.
  # macOS lets it while Claude is in front; otherwise the user must (Cmd-Tab).
  finder_front() {
    [ "$(front)" = Finder ] && return 0
    osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1; sleep 1
    [ "$(front)" = Finder ] && return 0
    echo "$NAME: waiting for the Finder in front (Cmd-Tab to the Finder)..."
    for i in $(seq 300); do [ "$(front)" = Finder ] && { sleep 1; return 0; }; sleep 1; done
    return 1
  }
  # variant <suffix> "<extra bundle ids>" <launch env...>: launch, capture; again if the Finder lost the front.
  variant() {
    local suf=$1 extra=$2; shift 2
    for try in 1 2 3; do
      if [ "$MACBAR" = 0 ]; then
        launch "$T" "$@"
      else
        quit_app
        defaults write $DOMAIN dockTheme "$T"
        env RETROMAC_AUTOACTIVATE_THEME=1 RETROMAC_QA_DELAY=6 "$@" nohup "$APP/Contents/MacOS/RetroMac" >/dev/null 2>&1 &
        sleep 4
        finder_front || { echo "$NAME: no Finder in front, $suf skipped"; return 1; }
        sleep 8
      fi
      if [ "$MACBAR" = 0 ] || [ "$(front)" = Finder ]; then
        "$BIN" "$OUT/$NAME-$suf.png" $extra && echo "$NAME-$suf.png"; return
      fi
      echo "$NAME: the Finder lost the front during $suf, once more"
    done
  }

  variant 1-clean "" RETROMAC_ONLY_APPS=none
  variant 2-menu "" RETROMAC_ONLY_APPS=none RETROMAC_OPEN_START_MENU=1 RETROMAC_HOVER_DOCK=$HOVER

  # A script-launched TextEdit starts hidden; unhiding does not bring it in front of the user's app.
  DOC=$(osascript -e 'tell application "TextEdit" to return name of (make new document)' 2>/dev/null)
  osascript -e 'tell application "System Events" to set visible of process "TextEdit" to true' \
            -e "tell application \"TextEdit\" to set bounds of (first window whose name is \"$DOC\") to {1040, 120, 1450, 520}" >/dev/null 2>&1
  variant 3-windows com.apple.TextEdit RETROMAC_ONLY_APPS=com.apple.TextEdit RETROMAC_OPEN_README=1 RETROMAC_OPEN_START_MENU=1
  [ -n "$DOC" ] && osascript -e "tell application \"TextEdit\" to close document \"$DOC\" saving no" >/dev/null 2>&1 || true
done
