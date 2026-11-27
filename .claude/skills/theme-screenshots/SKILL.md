---
name: theme-screenshots
description: Screenshot set of RetroMac themes in three variants (clean desktop; main menu open with the pointer on the dock; TextEdit window under the theme's title bar, the Read Me and the main menu). Use whenever Maik asks for screenshots, a screenshot set, or pictures of one or more themes.
---

# Theme screenshot set

Maik wants every theme in three variants:

1. **clean**: the desktop only.
2. **menu**: the theme's main menu open (Start menu, K menu, Apple menu, GEM's APPS) and, on dock themes, the pointer resting on a dock item (magnification and label).
3. **windows**: an empty TextEdit document under the theme's title bar, the theme's Read Me (About screen) and the main menu open.

## Run

```bash
.claude/skills/theme-screenshots/shoot.sh <outdir> <theme-id> [<theme-id> ...]
```

- **Theme IDs** are the `"id"` in `Resources/Themes/*/theme.json`.
- **Output:** files land as `<outdir>/<Bundle>-1-clean.png`, `-2-menu.png` and `-3-windows.png`, 2940 × 1912 from the built-in display. Use the scratchpad as `<outdir>` unless Maik names a place, and send the pictures with SendUserFile.
- **Long runs:** each theme takes about 40 s. Run longer sets with `run_in_background`.
- **Dock item:** `RETROMAC_SHOT_HOVER=<n>` picks the item the pointer rests on (default 3).

## How it works, and what it needs

- **Dev app:** the script runs `/Applications/RetroMac Dev.app`. Run `./build.sh debug` first if the code changed.
- **Restarts:** it starts the app once per variant, using QA hooks in `AppDelegate`:
  - `RETROMAC_AUTOACTIVATE_THEME` turns the theme on.
  - `RETROMAC_OPEN_START_MENU` opens the theme's main menu.
  - `RETROMAC_HOVER_DOCK=<n>` puts the pointer on dock item n.
  - `RETROMAC_OPEN_README` opens the Read Me.
  - `RETROMAC_ONLY_APPS` limits which apps get taskbar buttons and title bars.
- **What is captured:** only the desktop picture, the menu bar, RetroMac's windows and TextEdit. Maik's own windows never appear, and with `RETROMAC_ONLY_APPS` they also give no taskbar buttons or floating title bars. The floating launcher button is left out.
- **Themes that keep the Mac menu bar** (everything without `"hideMenuBarDefault": true`, including Mac OS and Atari TOS): the menu bar shows the frontmost app, and macOS does not let a script bring the Finder forward while Maik's app is active.
  - The script waits up to 5 min for the Finder in front.
  - **Before starting, tell Maik: "Cmd-Tab zum Finder".**
  - Start the run in the background so he can read the message.
  - The check runs again before every picture. If the Finder lost the front in between (it can, across the restarts), the script prints the waiting line again: watch the output and tell him again.
- **TextEdit:** the script opens an empty document, places it at the right, beside the centred Read Me, closes it without saving and quits TextEdit if it was not running before.
- **Settings:** afterwards it puts back the theme and the boot-screen setting (it sets `bootPhaseMode desktop` while shooting) and quits the dev app.

## Never

- Click, type or move the pointer on Maik's screen. Everything goes through the QA hooks.
- Capture the whole screen with `screencapture`. It shows Maik's private windows.

## Before sending

Look at each picture and tell Maik:

- **Personal details:** the Apple menu says "Log Out Maik Klotz", Windows Me's Start menu "Log Off Maik Klotz...", the K menu's Applications lists his installed apps, the Mac menu bar shows his status icons, and drive icons show his volume names.
- **What did not come out as intended:** for example a menu that closed, or a boot picture still on screen.
