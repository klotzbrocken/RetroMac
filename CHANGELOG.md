# Changelog

All notable changes to RetroMac are documented here. For older releases and the
downloadable DMGs, see the [GitHub Releases](https://github.com/klotzbrocken/RetroMac/releases).

## Unreleased

- **Defrag has the drive to go with it.** The spindle spins up when you press Start and coasts
  down when the job stops, the head clatters across the platter on every cluster it moves, and a
  short tick lands as each one is written — all of it tied to what the window is showing rather
  than looped underneath it. A seek's texture follows how far the head just travelled, so a
  freshly fragmented disk stutters and a nearly sorted one only ticks, and the whole thing calms
  down as the progress bar fills. Pause leaves the platter turning and stops the seeking, because
  that is what a paused job sounded like. Nothing is sampled: it is three synthesised ingredients,
  so no recording of somebody else's drive ships under an unclear licence. There is a Sound button
  in the toolbar, and it remembers what you chose.

- **Retro Crashes.** Simulated system failures in period: the Windows 9x blue screen ("An error
  has occurred", the fatal exception, Windows protection error), the illegal-operation dialog, and
  the NT Stop screen with its memory dump for Windows XP and 7. A crash freezes the desktop —
  by laying a photograph of it over itself, so nothing is actually frozen — shows the error, and
  offers the recovery the machine of the day offered. Choose Ctrl+Alt+Delete and the screen goes
  black and the theme's boot screen plays.

  Nothing ever really crashes: no application is quit, no document closed, no restart issued, and
  no system setting is changed. That last part is the recovery story rather than a detail — since
  nothing global is touched, force-quitting RetroMac is itself a complete repair. Esc always ends
  it, switching to another app ends it, and it ends by itself after a minute.

  The Macintosh side is there too: the System 6 bomb with its always-dead Resume button, Mac OS 9's
  bus error with the advice to restart holding Shift, Mac OS X 10.0's text-console panic, and the
  grey "You need to restart your computer" curtain in its four languages for Snow Leopard and
  Mountain Lion.

  In Authentic mode a crash is a scene rather than a picture. For five or six seconds the pointer
  falls behind and then sticks, the picture starts tearing, and a hard disk spins up and begins to
  hunt — then the error arrives. Choose Restart and the screen goes black, the theme's boot screen
  plays, and the desktop comes back exactly as it was, because it was never touched.

  The drive is synthesised, not sampled: a spindle spinning up, the actuator seeking, and then the
  slow regular click of a head that has hit the stop and is retrying. Nobody's recording is
  shipped, and the sound can follow the length of the scene instead of being a fixed clip.

  The graphics glitches are the ones these machines really produced. Redraw trails — a window
  smeared across a desktop that has stopped repainting — only appear where they were possible:
  drawing straight into the frame buffer, so every Windows up to XP and both classic Mac systems,
  but not Windows 7 with its Desktop Window Manager and not Mac OS X, which composited from the
  start. Where the desktop ran in 256 colours the palette goes wrong; where it ran in millions, a
  colour channel arrives displaced instead.

  Each era has several failures rather than one, and picks between them: the 9x blue screens, the
  "System is busy" screen, and the invalid page fault blamed on whichever of EXPLORER, RUNDLL32,
  MSGSRV32 or IEXPLORE was unlucky; XP's "has encountered a problem" with Send Error Report, and
  Windows 7's "has stopped working"; the Macintosh bomb naming its fault the way each system
  version did, from "Bus Error" to "error type 11", and the plainer "application has unexpectedly
  quit" that did not take the machine with it; and on Mac OS X the panic plus the same news in
  Aqua. Every screen also fills its own blanks — addresses, stop codes and module names differ
  each time.

  The Windows dialogs are laid out the way the originals were, down to the buttons stacked in a
  column on the right and the register dump that unfolds behind "Details". Closing one does not
  always let you off: a program that had just performed an illegal operation often took the
  machine with it a moment later, so sometimes it does. There are two antivirus finds as well —
  Norton on the 9x machines, Symantec's notification window on XP — which are not crashes at all:
  nothing restarts, because nothing broke.

  No two crashes in a row look alike. The picker avoids the last scenario and the last shape of
  failure, so a blue screen is followed by a dialog or by the shell dying rather than by another
  blue screen — half the Windows 9x catalogue is a blue screen with different words on it, which
  is how a correct random pick can still feel like the same crash every time. The warning varies
  too: sometimes the pointer falls behind, sometimes the picture comes apart, sometimes both in
  turn, and sometimes the failure simply arrives.

  Dialogs keep the mouse pointer. Blue screens still take it away, because the machine was not
  answering, but a dialog you are meant to click needs something to aim with.

  One of them is not a screen at all: Explorer stops responding, the taskbar and the desktop icons
  disappear for a few seconds, and then the shell comes back. That was the most common Windows
  failure of the era by a distance, and it needs no overlay — RetroMac simply takes its own
  taskbar away and puts it back.

  A red "simulated crash" sits in the corner, and can be switched off for a video.

  Off by default. Set how often it may happen, from once a week to a demo mode, or leave it on
  manual. It stays quiet while the virtual camera is running, while something is being recorded,
  in front of Keynote, Zoom or Teams, and in the first ten minutes after launch. Part of the
  licence.

  The Windows 9x screen is drawn in the real 720x400 VGA text mode with the real VGA font
  (Px437 IBM VGA by VileR, CC BY-SA 4.0, credited in About), scaled up whole-number so the pixels
  stay square.

## 2.8.3

- **Putting your system cursors back is reliable now.** Restoring used to delete its own backup,
  so the next themed cursor re-captured whatever was on screen; after one imperfect restore the
  theme's cursors became the stored "originals" and the real ones were gone. The backup is kept
  for good now, capture refuses to run while a theme is applied, and restore tears the old state
  down before putting the originals back. It also restores per cursor identifier rather than per
  logical slot, which matters more than it sounds: five of the twelve slots have variants whose
  artwork genuinely differs, and the spinner alone is a 24x24 image of 24 frames under one name
  and a 28x40 image of 15 frames under another.
- **"Apply to Full Screen" is in the menu bar.** Only "Apply to Window..." had an entry, so once
  you had put the effect on a single window there was no visible way back. Both entries now sit
  together and the active one is ticked.
- Under the hood: the dock works out its row once instead of in four separate places that had to
  be kept in step by hand. That is what let the trash escape the bar in 2.8, and it had quietly
  caused two more mismatches nobody had noticed.

## 2.8.2

- **The trash sat outside the dock** on Snow Leopard and Mac OS X, and only snapped into place
  while the pointer was over the dock. The bar's width is worked out by listing every tile it will
  hold, and that list had no entry for the Dashboard icon, which was added to the dock later. The
  bar came out exactly one tile too narrow, so the last item — the trash — was drawn beside it;
  hovering hid the symptom because magnification reflows the row inside the bar. Mountain Lion was
  a tile short too, but has no trash, so nothing showed.

## 2.8.1

- **Exposé no longer hides RetroMac's own windows.** The window list skipped anything owned by
  RetroMac itself, which on a theme desktop is a large share of what you see: Television, the CPU
  monitor, Notepad, Calculator and App Folder windows are all ours. With only those open, Exposé
  reported "No windows" over a screen full of them. Nothing unwanted comes in as a result — the
  dock, Dashboard, the Exposé sheet, the pet, menus and desktop icons all sit above the window
  layer Exposé reads and were already excluded.
- With a second display attached, the screen that happened to hold no windows announced "No
  windows" while the other was showing them all. That message now means nothing anywhere.

## 2.8

- **Snow Leopard has its own chrome**: 10.6 no longer borrows Cheetah's early-Aqua look. Three
  themes used to share one chrome key, so a 2009 desktop wore a 2001 window. The title bar is
  measured off the original — unified grey, flat traffic lights, the separator along the bottom —
  and it comes with blue gel scrollers, period-correct icons for Chrome, iWork, Claude and
  ChatGPT, and the striped Macintosh HD.
- **Dashboard is back**: the widget layer macOS dropped in Catalina, rebuilt. Ctrl+F12 brings up
  Clock, Calculator, Weather (Open-Meteo, no key, no account), Calendar, Stickies, a Google search
  pill and a CPU monitor. Add and remove them from the bar, drag them where you like, and they
  stay put.
- **Exposé**: every window on the desktop, shrunk so none overlap, each card travelling from where
  its window actually sits. Ctrl+F9 for all of them, Ctrl+F10 for the front app — or hold a dock
  icon, the way 10.6 changed that gesture to work.
- **Stacks, drawn the way 10.6 drew them**: Applications and Downloads open as a grid with real
  Quick Look previews, sitting next to the Trash where they belong, and hanging from the callout
  nose that points back at the dock icon.
- **Disk Defragmenter**: the Windows 95 and 98 themes get the defrag widget, with its authentic
  icon, a working scrollbar and a period-correct pace.
- **Desktop extras**: the real Flurry screensaver for the Mac OS X themes, five more Snow Leopard
  wallpapers (Rocks, Earth, Aurora Blue, Zebra, Stones), and an optional tint for the menu bar so
  a modern translucent one stops fighting the theme.
- **Phosphor persistence**: afterglow across frames, applied to the signal ahead of the mask, in
  every Metal renderer.
- **Settings have a Shader tab**: what was "Advanced" is now Shader, and it leads the sidebar.
  The effect's settings used to be spread over three tabs and five sections; they are in one place
  now — Preset, Look, Where, Per-App, Performance and When. Hotkeys and system setup moved to tabs
  of their own.
- **Fixes**: the shader's per-theme on/off is no longer overruled at launch, and switching it off
  no longer discards which preset the theme was assigned; the Quality picker stops resetting a
  frame rate you chose, and 120 fps is offered only on panels that reach it; a failed theme import
  can no longer lose the theme it was replacing; Hover! is genuinely offline (its last two remote
  references are gone); the shader and the dock pin their display by UUID rather than by display
  id, so they stay put across a reconnect; widgets stop rendering a cached copy of themselves
  after an update; every readme window can be dragged; file paths coming from the App Folder web
  view are validated; every boot screen shows for the same five seconds; and beta disk images are
  named after their version, so a beta can never again be shipped as the release.

## 2.7

- **Windows 95 theme**: the one that started it all. Solid navy title bars, the silver
  `#C0C0C0` chrome, the clouds wallpaper, an authentic boot screen, and Win95 shell icons
  throughout. The Start menu is period-correct: large icons in a narrow first level, small
  ones in the wider submenus, and no Windows Update or Log Off (Windows 95 had neither).
- **Fun Stuff (D:)**: the CD-ROM is back on the desktop. Open it and browse `FUNSTUFF` into
  `HOVER`, `VIDEOS` and `PICTURES` — music videos play in a bare title-bar window, and
  `Clouds.exe` / `WINBMP.EXE` set your wallpaper the way a 1995 CD-ROM would.
- **Hover! plays again**: the Microsoft HTML5 remake, self-hosted and fully offline in its
  classic pixel-graphics mode. No Wine, no emulator, no internet.
- **Authentic Win95/98 details**: scrollbars with a single arrow at each end, raised bevels
  and a dithered track; the status bar below its own scrollbar row; the program icon back in
  the title bar; and no running-app dots under quick-launch icons on 98/Me/XP, where the
  taskbar already shows running programs.
- **Readmes overhauled**: every theme's "About This Theme" is closable again, fills its
  window edge-to-edge, sizes itself so it needs no scrolling, and shows its hero artwork.
  Futurama finally has one too.
- **Start into your theme**: a new opt-in setting activates your last theme right at launch
  instead of the clean desktop.
- **Fixes**: Windows 95 title bars no longer showed the Windows 98 gradient (which also
  repaired every Windows 98 Plus! colour scheme), file lists are white instead of grey,
  desktop icon labels stop colliding, boot videos are no longer cropped at the bottom,
  `sheep.exe` works on Windows 95, and the Classic Teal wallpaper is the canonical `#008080`.

## 2.6

- **Windows Me theme**: Millennium Edition joins the family — the Me Start-menu banner in its
  brush-script logo, a 4K-remastered wallpaper, an authentic boot splash, and Me shell icons
  (oval Recycle Bin, Media Player). "Windows Update" sits atop the Start menu, and it gets the
  full special-theme treatment (systray, taskbar auto-hide, desktop pet).
- **Windows 7 Aero, refined**: the Start menu now has its glass frame and the account picture that
  peeks above the top edge; the taskbar is real translucent Aero glass; and the notification area
  is authentic — a flat tray with an up-chevron, network + volume icons that open the matching
  macOS settings, and a two-line time/date clock.
- **100% themes**: the marker on the fully-realised themes is now a 100% badge shown after the
  theme name (Futurama counts too).
- **Flyout upgrades**: drag Quick Access tiles to reorder them in Edit mode, double-click the
  floating button to toggle your last theme, and the menu-bar Apple-logo cycle now includes the
  Futurama teal apple.
- **New shaders**: NLO VHS SP — a real single-pass NTSC comb-demodulation with authentic dot crawl
  and cross-colour — and CRT EasyMode, a clean, sharp mask-and-scanline CRT.
- **Windows 98 / Me icon fixes**: Safari maps to the IE icon, and running Chrome/Firefox show their
  real icons again instead of IE.
- **Fix**: a pasted licence key is no longer white-on-white in the Activate field.

## 2.5

- **Futurama theme**: a Planet Express take on the desktop. The dock is the show's riveted metal
  girder: a pressure-gauge control panel on the left, a recessed glass shelf your icons rest on,
  and a grille end cap on the right. It comes with a teal Bender-and-friends icon set, the Planet
  Express wallpaper, a teal Apple logo, and bold cel-shaded window outlines.
- **Restore system cursor**: a new button in Cursor settings puts the normal macOS pointer straight
  back if a themed cursor ever gets stuck. RetroMac also recovers the cursor reliably on the next
  launch now, even if it was force-quit while a themed cursor was active.
- **Fix (all custom docks)**: minimizing or restoring a window, or changing your pinned apps, now
  resizes the dock immediately instead of leaving it the wrong size until you moused over it.

## 2.4

- **NeXTSTEP theme**: the full NeXT desktop, rebuilt natively. A vertical Workspace menu top-left,
  a right-edge dock of grey tiles with a live clock/calendar and the Recycler, black title bars with
  the miniaturize box left and close box right, the four-grey chiseled bevel throughout, and the
  MegaPixel grey-violet wallpaper. Running apps float free on the workspace as draggable icons that
  snap to a grid, and the NeXT cursor replaces the pointer.
- **File Viewer**: the NeXT Workspace file browser, with the shelf of category drawers, a
  current-location path strip, the icon grid of your installed apps and TV streams, and the
  authentic left-side scroller (arrows grouped at the bottom, dimpled knob). It opens on its own
  when the theme starts, as it always did on NeXTSTEP.
- **Change any dock or app icon**: right-click a tile and pick from 120 authentic NeXT "Fleet"
  icons or your own image. A "fill the whole tile" option decides whether the pick covers the
  cell edge-to-edge or sits inset on the silver tile.
- **TV in themed windows**: the Classic Themed Window for TV streams now wears the NeXT window
  chrome too (it already matched BeOS, Mac OS 9, Windows XP and System 6).
- **Stable theme identity (under the hood)**: themes now carry a stable id, so renaming or
  duplicating a theme keeps its wallpaper, dock position, preset and other per-theme settings, and
  two themes can share a name without clashing. Existing settings migrate automatically on first run.
- **Fixes**: bringing a running app back to the front from its NeXT icon now works reliably; the
  System Tweaks boolean restore and the wallpaper restore both round-trip correctly.

## 2.3

- **Windows 7 Aero theme**: the Superbar taskbar with the Start orb, translucent glass window
  titles, and the Aero wallpaper.
- **Windows 98 Plus! themes**: pick a scheme under Settings ▸ Dock ▸ Scheme (Dangerous Creatures,
  Leonardo da Vinci, More Windows). Each recolours the whole Windows 98 look (title bars, windows,
  start menu) and swaps the wallpaper, desktop icons and mouse cursors.
- **Mac OS System 9**: pixel-accurate Platinum title bars, proxy icons, a Finder info bar,
  WindowShade collapse, authentic desktop/proxy icons, an expanded icon set, imported classic
  wallpapers, colour Nyanochrome and Tic-Tac-Toe widgets, and a cleaner inactive-window state.
- **Dockable Control Strip**: the System 9 Control Strip now snaps flush to the left or right
  screen edge (Settings ▸ Dock), mirrors correctly, and gains scroll chevrons when it overflows,
  just like the historical original.
- **Window borders**: per-window themed borders are steadier when windows change focus or space,
  and clear more promptly on minimize.
- **Calculator widget** for the Windows 98 and XP themes, plus an authentic Windows 98 screensaver
  icon and a working Edit/View/Help menu bar on the Windows calculator.
- **Warcraft I + II**: a theme-matched title bar drawn by the engine, so the game sits in a normal
  window on the themed desktop with the dock beside it (hidden only in fullscreen).
- **Setup Assistant**: a Games step to point RetroMac at your Doom, Quake, Duke Nukem and Warcraft
  files (and add desktop shortcuts), and a final step to pick the theme to start with. The
  "shader on theme change" default is now off.
- **Security**: imported themes can no longer run system tweaks or reach files outside their
  bundle; system tweaks are only dropped from the restore snapshot once they are actually reverted,
  so a transient failure can no longer strand a changed setting; a refunded or revoked licence is
  now detected on revalidation.
- **Fixes**: the real macOS Dock is restored when RetroMac's dock is turned off; Mac OS X Cheetah
  title-bar hover no longer flickers; assorted polish.

## 2.2

- **One-time manual update**: 2.2 changes how updates are delivered (a new signing key), so
  existing copies cannot install it automatically. Download 2.2 once and drag it into
  Applications; automatic updates resume from 2.3 on.
- **Authentic Mac System 6**: a true 1-bit black and white theme.
- **Warcraft I + II**: play them natively on the bundled Stratagus engine with your own game data.
- **Mac OS X boot animation** for the Mac OS X and Snow Leopard themes.
- Clearer Pro unlocks and assorted polish.

## 2.0

- **Themed mouse cursors**: each theme can replace the whole system cursor (classic Mac pointer
  with ticking wristwatch / rotating spinner, Mac OS X Aqua with the spinning beach ball,
  Windows XP, retro Windows 3.1). Toggle under Settings ▸ Dock ▸ "Match cursor"; your own cursor
  is captured and restored exactly when the theme goes off.
- **Windows XP cursor sizes**: Normal, Large or XL while the XP theme is active.
- **BeOS unified**: "BeOS" and "BeOS Classic" are one theme now, with a switch between the corner
  Deskbar and a regular dock.
- **Per-theme icon sizes**: dock and desktop icon-size sliders are remembered per theme.
- **Setup Assistant**: opt in (on by default) to matching the macOS colour scheme and the cursor.
- Fixes: menu-bar Apple logo resets when a theme or the app turns off, opaque System 6 Control
  Strip with a new boot splash, plus TV-Tube and Duke Nukem / GZDoom launch fixes.

For the 1.9.2 through 1.9.7 and 2.1 releases, see the
[GitHub Releases](https://github.com/klotzbrocken/RetroMac/releases).

## 1.9.1.1

- **iPhone as a camera source** — pick your iPhone (Continuity Camera) or any webcam in
  Settings ▸ Camera & Streaming; the list updates live as devices connect, and the CRT
  shader runs on the feed.
- **"Dock only" really means dock only** — switching a theme with Dock only on no longer
  touches the wallpaper, desktop icons, widgets or boot splash, and won't start a
  full-screen shader.
- **Multi-monitor Lite shaders** — the lightweight (Lite) presets now appear on the
  selected display, not just the main one.
- **TV windows** no longer borrow the last used theme's menu bar / chrome when no theme
  is active.
- **Tidier quick-access flyout** — the shader toggle and preset dropdown stay correct
  after switching presets; active theme highlighted correctly; Settings/Quit are icons;
  floating launcher on by default.
- **Dock fixes** — clicking a Dock tile reliably brings a running app's window to the
  front; correct flyout & Dock-Mode icons across themes; desktop-icon visibility respects
  other apps.

> Supersedes 1.9.1, which was retracted before wide distribution.

## 1.9.0

- **Dock Mode & quick launcher** — optionally show RetroMac in the Dock; click its icon
  for a slim launcher to switch themes and toggle the shader or virtual camera.
- **Authentic Windows taskbar** — Windows 98 and XP show one elongated taskbar button per
  open window; click to minimize or restore.
- **Shaders on all displays** — the CRT shader now works on secondary monitors.
- **New "Retro Crisis" GDV-NTSC shaders** (Composite & RGB) and softer, more authentic
  phosphor masks.
- Setup Assistant, redesigned Settings, custom Metal shader import, and reliability fixes.

## 1.8.x and earlier

See the [GitHub Releases](https://github.com/klotzbrocken/RetroMac/releases) page for
release notes and downloads.
