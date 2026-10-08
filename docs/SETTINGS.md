# The Settings window

How RetroMac's settings are organised, and the rules that keep them that way. If you add a
setting, this is the page that says where it goes and what it looks like.

## Shape

One window, 700 × 640, a 200-point sidebar on the left and the tab on the right. Every tab is a
vertical stack of **cards** (`RMCard`), every setting a **row** (`RMRow`) inside a card. The
window is pinned to the light appearance; the palette is the `rm*` colours in `RMTheme.swift`.

The sidebar has three groups:

| Group | Tabs |
|---|---|
| (main) | Themes, Shader, Desktop, Favourite |
| Surfaces | Camera & Streaming, Games, Crashes |
| System | General, Shortcuts, Health Check, About |

Three tabs are split into sub-pages by a segmented switch: Shader (Presets & Effects, Screen &
Apps, Performance, On & Off), Themes and Camera & Streaming.

## What lives where

**Shader** — everything about the effect. Presets & Effects: the installed and imported
shaders, and the scanline and reflection overlays. Screen & Apps: the scope (whole screen,
wallpaper, desktop), what is hidden while the shader is on, and rules that switch presets by
frontmost app. Performance: quality and frame rate. On & Off: running now, on launch, per
theme, around sleep.

**Themes** — the selected theme and the retro dock. Behaviour (RetroMac in the Dock, activate
on launch, boot screens), Dock (on/off, position, per-theme dock styles, indicators, clock),
the theme's own extras (Plus! schemes, tray messenger, Re:Amp, Pac-Man, Doom Slayer), System
integration (everything the theme changes outside RetroMac's windows and undoes afterwards),
Apps in the dock, and under Advanced the dock's transparency, icon scale, target display and
the theme files. The second sub-page is the Screensaver.

**Desktop** — what the *active* theme puts on the desktop: wallpaper (bundled, own image,
reset), the menu bar (tint, Apple logo), desktop icons (show/hide, restore), icon size and
widgets. Stored per theme.

**Favourite** (called Retro Mode before 3.0) — the favourite look and what to hide in one click.

**Camera & Streaming** — the virtual camera (scenes, source, shader, lower third) and the
television bookmarks and tube mode.

**Games** — the CRT in games, where the game data lives, ROMs and emulators. Everything about
a *particular* game is in the Game Library window, not here.

**Crashes** — Retro Crashes: mode, how often, what can happen, boot failures, moments, the scene.

**Shortcuts** — Rescue Desktop on top, then the window switcher, then the global hotkeys.

**Window switcher** (⌃⌥Tab, Shift the other way) does what the active theme's era did, from a
release matrix per theme: Solaris moves the focus window by window, Snow Leopard opens Exposé,
Mountain Lion Mission Control. Themes whose era had none get none; the Windows Alt+Tab panels and
Flip wait for their reference screenshots. Its keys are only taken while the theme has a
switcher and "Use it in this theme" is on.

**Rescue Desktop** is also in the flyout and the menu-bar menu, and works with no theme on. If a
rescue was interrupted, the next launch turns nothing on and finishes it; launching with
`--rescue-desktop` (`open -a RetroMac --args --rescue-desktop`) does the same on request.

**General** — the Setup Assistant, start at login, and the three permissions with Grant buttons.

**Health Check** — read-only: system capabilities, capture status, GPU and displays, the theme.

**About** — version, updates, licence, credits, diagnostics. The one tab still built as a
system form, because it is a document rather than settings.

## Rules

1. **One owner per setting.** A key from `AppSettings` appears in exactly one row. If two tabs
   both seem to need it, one of them gets a sentence pointing to the other (see the subtitle
   of Themes ▸ Advanced ▸ Appearance).
2. **Cards and rows, not forms.** Tabs are `ScrollView { VStack(spacing: RMSpacing.section) {
   RMCard … } }` with `.padding(.horizontal, 24).padding(.vertical, 20)`. Cards holding rows
   pass `bodyPadding: 0` — the rows pad themselves. Free text inside a card body is `RMNote`.
3. **The hint is one line, two at most.** Under ~110 characters. What does not fit goes into a
   `.help()` tooltip or the card's subtitle, or is cut.
4. **Wide controls go under the label.** `RMRow` is label-left, control-right. A control wider
   than about 200 points — a segmented picker with three entries or long titles, a slider with
   its value, a text field with a button — uses `stacked: true`, which puts it under the text
   at full width. AppKit does not clip a segmented control to `.frame(width:)`: forced narrower
   than its content it draws over the hint and off the card.
5. **Three-way choices with explanations are radio lists**, one line each with its own
   sentence (Shader ▸ Where ▸ Effect scope), not a segmented control with a paragraph beside it.
6. **A switch takes effect now.** If a key is only read while something is built (the theme,
   the dock), the row re-applies it in `onChange`. Never leave a switch that silently waits for
   the next theme change.
7. **Buttons use the RM styles**: `RMPrimaryButtonStyle` for the one action of a tab,
   `RMDefaultButtonStyle` for everything else, `RMGhostButtonStyle` for secondary actions in a
   row, `RMDangerButtonStyle` for Revert and friends. No bare `.bordered`.
8. **Words.** British spelling (behaviour, colour, favourite), sentence case for card titles and
   labels ("Apps in the dock", not "Apps In The Dock"), the theme's display name in quotes when
   a row is about one theme. A paid feature carries the padlock through
   `LicenseManager.shared.label(_:)`.
9. **Every tab has a subtitle** in `SettingsTab.subtitle`, one sentence, what the tab is for.
10. **Conditional rows key on the selected theme** (`selectedThemeConfig` on Themes), not on
    the active one, so a row does not vanish because the theme is chosen but not yet switched on.
