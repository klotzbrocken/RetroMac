# RetroMac Backlog

Open items captured from user feedback and reviews. Not blocking a release;
larger-effort or design-gated work.

## From user feedback (window-decoration creator, translations, etc.)

- **Window-decoration button states & affordance.** The close button needs a
  pressed/active state, and purely decorative buttons (e.g. the right-most
  frame button) should not look interactive. Add proper button states and a
  clear "this does nothing" affordance on the drawn retro window chrome.
  (Window chrome is drawn procedurally, see RetroFrameTheme / the *Controller
  overlays — there are no swappable PNGs for it yet.)

- **Localization layer + translations via GitHub.** Strings are partly
  hardcoded and some German leaked through (e.g. CPU monitor "Benutzer", fixed
  in 1.9.5; the Windows "Workstation" logo asset still German). Extract user-
  facing strings into a proper `Localizable.strings`, then open a GitHub
  "translations" issue so contributors can submit language files via PR.

- **"Workstation" logo asset.** Replace the German Windows logo asset used in
  the Windows themes with a language-neutral / localized version.

- **Theme-authoring documentation + opening up window decorations.** Publish a
  guide to the `.retromactheme` bundle format (theme.json + icons + wallpaper)
  so users can build and share themes. Custom *window decorations* are
  currently code-driven; opening that up needs a security model (shared
  bundles → sandbox / opt-in / signing + trust UI, especially because custom
  `.metal` shader import already allows arbitrary GPU code). Do NOT ship
  bundle sharing without that gate.

## v2.0 scope (decided earlier — see memory `retromac-v2-backlog`)

- Creator/Streamer webcam wedge (scenes/presets, lower-thirds, OBS guide).
- iPad retro second screen (opensidecar fork + CRT shader).
- Community themes / import (gated on the security model above).
- Apple-API resilience (wrap private dock + display APIs behind one layer with
  graceful degradation for future macOS) — partially done (CoreDockBridge).
- Dock-behavior hardening (watchdog helper to restore the system Dock if
  RetroMac crashes while it's hidden; window-space reservation).

## TV / Audit R3 (2026-07-04)
- **TVPlaybackSession / TVPresetPolicy**: Stream-Auswahl, Preset-Auflösung
  (Fenster-Override > Bookmark > Global > Default) und Last-Channel stecken
  heute 3× in Tube Mode, Classic TV Window und TV Settings — in ein kleines
  gemeinsames Modell ziehen.
- **Automatisierte Regressions-Checks** (SystemBridgeTests-Stil): Tube-Start
  ohne Metal/Shader, Appearance-/Terminal-Crash-Recovery, WebApp-Path-Escape,
  TV Web- vs. Stream-Preset.
