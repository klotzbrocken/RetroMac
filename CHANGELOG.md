# Changelog

All notable changes to RetroMac are documented here. For older releases and the
downloadable DMGs, see the [GitHub Releases](https://github.com/klotzbrocken/RetroMac/releases).

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
