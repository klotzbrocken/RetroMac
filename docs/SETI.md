# SETI@home Classic in RetroMac

A simulation of the SETI@home Classic client (1999–2005) as a window, in the background and as
a screensaver, after Maik's requirements specification of 13 November 2026. Nothing is
analysed, nothing goes over the network, no account is needed.

## Where it is

| Theme | Client | Opened from |
|---|---|---|
| Windows 95, 98, Me, XP (`win98`, `winxp`) | Windows 3.08 | Start ▸ Programs ▸ SETI@home |
| System 7.1 (authentic), Mac OS 8 (Copland), Mac OS 9 (authentic) | Macintosh 2.01 | The telescope in the menu bar ▸ Launch |
| Mac OS X 10.0 | Mac OS X (reconstruction, shown as 3.07) | The telescope in the menu bar ▸ Launch |
| any | as above, or as chosen | Settings ▸ Themes ▸ Screensaver ▸ SETI@home; the saver picker |

Mac OS 9.2 Classic is left as it is (no telescope). NT 4.0 and Windows 2000 have no theme yet.

## How it is built

- `Sources/Desktop/SETI/SETISimulation.swift` — the state and its rules: phases, overall progress,
  CPU time, the work unit's data, the random find (first after 2 + 4…12 visible minutes, then at
  least 5 minutes apart, on visible time only). Seeded, so the same seed gives the same sky.
- `Sources/Desktop/SETI/SETIController.swift` — owns the state, saves it to
  `~/Library/Application Support/RetroMac/seti-state.json`, runs the clock, feeds every view a
  snapshot, draws the telescope.
- `Resources/Widgets/SETI/SETI.html` — draws a snapshot at the reference size, scaled by whole
  numbers where it fits, black around it.
- Tests: `Tests/RetroMacTests/SETISimulationTests.swift`.

## What is original and what is reconstructed

| Part | Source | Status |
|---|---|---|
| Windows main view: layout, purple frame, colours, texts, spectrum perspective | Classic 3.08 screenshot, Wikimedia Commons (760 × 491) | measured off the picture |
| Macintosh main view (power axis left, time right) | Client 2.01 screenshot, 12 Feb 2000 | measured off the picture |
| Status names (Doing Baseline Smoothing, Computing Fast Fourier Transform, …) | Berkeley's own description of the analysis | as documented |
| Logo (globe, wave, dish) | — | drawn for RetroMac |
| Windows menu contents, Preferences and Login dialogs, About | Mac manual of June 1999 for what they do | reconstruction |
| "Best Pulse" / "Best Triplet" wording, pulse and triplet graphs | Berkeley's explanations | reconstruction |
| Mac OS X client | ReadMe up to 3.07 for its flow | reconstruction, no picture |
| Times, speeds, how often a find turns up | — | RetroMac's choices, not measurements |

## Open (needed for the 100 % acceptance)

From the specification's register: one client version per Mac profile (OFF-01); pictures of
the Classic Mac dialogs and menus (OFF-02) and of the Mac OS X client (OFF-03); a recording for
frame rate, drawing order and timing (OFF-04); the Windows dialogs per theme (OFF-05); the
historical profiles' versions (OFF-06); window and saver details such as the hot corner and
⌘⇧S, which RetroMac does not wire up yet (OFF-07); original fonts and icons in their sizes
(OFF-08); performance budgets (OFF-09); historical speed (OFF-10).
