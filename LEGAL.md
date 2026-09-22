# What is in the box, and whose it is

RetroMac recreates the desktops of the 1980s, 90s and 2000s. Some of what it ships was written
for RetroMac, some is free software from other people, and some is the original artwork of the
companies whose machines it imitates. This page says which is which, under what terms, and
whom to write to if you hold rights in any of it and disagree with its presence here.

RetroMac is not affiliated with, sponsored by, or endorsed by Apple, Microsoft, Be, IBM, Silicon
Graphics, Commodore, NeXT, Iomega, id Software, 3D Realms, Raven Software, Blizzard, Namco,
Berkeley Systems, or 20th Century Studios. Their names and products are named here because the
themes are about them.

## RetroMac's own code

Everything under `Sources/`, `Tests/`, the build scripts and this documentation is
© Maik Klotz and released under the [GNU GPL v3.0](LICENSE). The optional Pro unlock is a way
to support the project; it does not change the licence of anything in this repository.

## Free software RetroMac links or bundles

| What | Where | Licence |
|---|---|---|
| Sparkle (updates) | `Package.swift` | MIT, © Sparkle Project |
| Px437 IBM VGA 9x16 (text-mode crash screens) | `Resources/Fonts/` | CC BY-SA 4.0, VileR, [int10h.org](https://int10h.org/oldschool-pc-fonts/) |
| ChiKareGo2 (Chicago 12 as a bitmap face: the Platinum menus and the Application menu of Mac OS 9 (authentic), the Applications widget's list) | `Resources/Fonts/ChiKareGo2.ttf`, `Resources/Widgets/AppFolder/ChiKareGo2.woff2` | CC BY, Giles Booth, [BitFontMaker2 gallery #3780](https://www.pentacom.jp/pentacom/bitfontmaker2/gallery/?id=3780) |
| Pixel Operator (desktop icon labels of Mac OS 9 (authentic)) | `Resources/Fonts/PixelOperator.ttf` | CC0 1.0, Jayvee Enaguas, [fontlibrary.org](https://fontlibrary.org/en/font/pixel-operator) — full text in `PixelOperator-LICENSE.txt` |
| Retrosmart cursor set (Windows 3.1, 95, Me pointers) | `Resources/Cursors/Retrosmart`, `Resources/Cursors/Windows95` | GPL v3 |
| XP.css caption buttons | `Resources/Chrome/winxp/` | MIT, © 2020 Adam Hammad, Jordan Scales |
| 7.css colours and gradients | `Sources/Desktop/` (drawn natively) | MIT, © 2021 Khang Nguyen Duy |
| three.js (Pipes screensaver, Hover) | `Resources/Widgets/Screensavers/Pipes/lib`, `Resources/Widgets/Hover/scripts` | MIT |
| Flurry-WebGL (Flurry screensaver) | `Resources/Widgets/Screensavers/Flurry` | MIT, © 2014 Roy Adrian Curtis, derived with permission from Calum Robinson's Flurry |
| Starfield Simulation (the Windows 2000 screen saver) | `Resources/Widgets/Screensavers/Starfield` | RetroMac's own canvas port; the simulation's constants and integer arithmetic follow Ilya Kalimulin's macOS port (github.com/ilirium/starfield_simulation_screensaver_win2k_for_macos, MIT, © 2026 Ilya Kalimulin). The Windows saver itself is Microsoft's |
| Stratagus / Wargus / War1gus (the Warcraft engine) | `vendor/peonpad`, `vendor/war1gus` (submodules) | GPL v2 |
| Pac-Man clone (BeOS demo) | `vendor/pacman` | GPL v2, see its README |
| Shader presets | `Sources/Shaders/`, listed in About ▸ Shader Credits | Per preset: GPL-2.0 (zfast-crt, crt-geom, crt-royale-lite, crt-gdv-mini-ultra, retro-crisis, crt-easymode), MIT (crt-lottes, crt-hyllian-glow), CC BY-NC-SA 3.0 (newpixie-crt), Apache-2.0/MIT (NLO VHS SP, parameters only), and RetroMac's own |

Game engines are not bundled: the Game Library downloads GZDoom, Raze, vkQuake and Yamagi
Quake II from their own release pages when a game needs them, each under its own GPL, and only
the episodes their publishers released to be copied (Freedoom under its BSD-style licence; the
id Software, Raven and 3D Realms shareware episodes under their shareware terms). Emulators
(ares, Dolphin, DuckStation, PCSX2, Stella) are likewise fetched from their projects, never
shipped. Commercial game data always comes from the user's own copy.

## Artwork that belongs to the companies being recreated

The themes reproduce how those systems looked. That means icons, wallpapers, cursors, sounds
and window chrome that Apple, Microsoft and the others drew, which RetroMac carries as an
**unofficial fan tribute**: no ownership is claimed, nothing is presented as official, and the
files are not offered for any use outside the app. Where a set has a written credit, it is in a
`CREDITS.txt` or `README.txt` next to the files.

| Owner | What RetroMac uses | Where |
|---|---|---|
| Apple | System 6, Mac OS 9, Mac OS X, Snow Leopard and Mountain Lion icons, wallpapers, cursors and boot screens; the Chicago, Geneva and Courier bitmap faces of System 6; the bomb and Sad Mac of the crash screens | `Resources/Themes/MacOS*`, `Resources/Cursors/Apple*`, `Resources/Cursors/MacOSX`, `Resources/Crashes/` |
| Microsoft | Windows 3.1, 95, 98, Me, XP and 7 icons, wallpapers and pattern tiles, the Plus! schemes, the XP and 7 cursors, the Start orb, boot screens, the blue-screen wording, and Hover! (the 2013 HTML5 remake Microsoft published at hover.ie) | `Resources/Themes/Windows*`, `Resources/Cursors/WindowsXP`, `Resources/Cursors/Win98-*`, `Resources/Widgets/Hover` |
| Be Inc. (now ACCESS) | BeOS icons, the Deskbar and the yellow tab | `Resources/Themes/BeOSClassic.retromactheme` |
| IBM | OS/2 Warp 4 icons and WarpCenter | `Resources/Themes/OS2-Warp.retromactheme` |
| Silicon Graphics | IRIX icons, Toolchest and 4Dwm look | `Resources/Themes/SGI-IRIX.retromactheme` |
| Cloanto / Hyperion | AmigaOS Workbench 4.1 icons | `Resources/Themes/AmigaWorkbench41.retromactheme` |
| NeXT | NeXTSTEP icons and the Workspace shelf | `Resources/Themes/NeXTSTEP.retromactheme` |
| Iomega | The Zip drive in the click-of-death scene (pixel art drawn for RetroMac, of a product whose trade dress is Iomega's) | `Resources/Crashes/zipdrive.png` |
| id Software, Raven, 3D Realms, Blizzard | Game logos in the Game Library | `Resources/GameIcons/` |
| Namco | Pac-Man, as the GPL clone above | `vendor/pacman` |
| Berkeley Systems | The Flying Toasters are RetroMac's own drawing of an After Dark idea | `Resources/Widgets/Screensavers/FlyingToasters` |
| 20th Century Studios | The Futurama theme is a fan tribute; its artwork was drawn for RetroMac | `Resources/Themes/Futurama.retromactheme` |
| Chris Torres | Nyanochrome is a one-bit nod to Nyan Cat | `Resources/Widgets/Nyanochrome` |

The Windows 7 icons come by way of the B00merang-Artwork GTK theme, which ships without a
licence file of its own; that, too, is recorded in the theme's `CREDITS.txt`.

## Drawn or written for RetroMac

The crash screens (blue screens, Stop errors, ScanDisk, CHKDSK, the update screens, the
kernel panic curtain), the synthesised sounds (the hard disk, the Zip click, the floppy seek,
Defrag's drive), the television bezels, the Defrag simulation, the widgets, the dock and window
chrome drawing code, the pattern tiles' re-creations where noted, and the README's screenshots
are RetroMac's own. The wording on the crash screens quotes the original messages because a
blue screen that says something else is not a blue screen.

## If you hold rights in something here

Write to the maintainer through [klotzbrocken.de](https://www.klotzbrocken.de) or open an
issue on [GitHub](https://github.com/klotzbrocken/RetroMac/issues). Say which files, and the
files come out in the next release; no argument required. The same address takes corrections
to this page, which is kept as accurate as one person's memory of where things came from allows.
