# Making a theme

A RetroMac theme is a folder named `Something.retromactheme` with a `theme.json` inside. That
file is the whole manifest: the dock, the wallpapers, which icon stands for which app, what
lies on the desktop, the boot screen, and how the windows are drawn. Everything else in the
folder is a picture the manifest points at.

This page is the reference for that file. It describes what the current build reads. Keys the
app does not know are ignored on load and **dropped when the theme is saved** from Settings, so
do not keep notes in the manifest.

## Where themes live

| | Path |
|---|---|
| Bundled themes | `RetroMac.app/Contents/Resources/Themes/` (read-only, the source is `Resources/Themes/`) |
| Your themes | `~/Library/Application Support/RetroMac/DockThemes/` |

Settings ▸ Themes ▸ Advanced ▸ **Import…** copies a `.retromactheme` folder into the second
place; **Duplicate** makes an editable copy of a bundled theme there, with a fresh `id`. Both
places are scanned at launch and when the theme list is refreshed.

For a quick round trip while editing, launch the dev build with the theme already on:

```bash
RETROMAC_AUTOACTIVATE_THEME=1 open "/Applications/RetroMac Dev.app"
```

## The folder

```
Windows98.retromactheme/
├── theme.json          the manifest (required)
├── preview.jpg         shown in the theme picker; preview.png also works
├── appIcon.png         small square icon for the launcher's theme strip (icon.png also works)
├── readme.html         optional "About this theme" page, opened from the desktop's readme icon
├── wallpaper.jpg       whatever the manifest names; several files are fine
├── tile-*.png          pattern tiles, if the theme offers any
├── splash.png          boot screen still (or boot.mp4 / boot.gif, see below)
├── icons/              every icon the manifest refers to, PNG, plus CREDITS.txt if borrowed
└── fonts/              .ttf/.otf registered for the process while the theme is on
```

Paths in the manifest are relative to the folder (`wallpaper`, `splashScreen`, …) or to
`icons/` (`iconMappings`, `desktopIcons[].icon`, `dock.startButtonIcon`, `fallbackIcon`). A path
that leaves the folder (`../`, a symlink out) is refused, since RetroMac runs unsandboxed and
imports themes it did not write.

## Identity

```json
{
  "schemaVersion": 2,
  "id": "com.example.windows98-remix",
  "name": "Windows 98 Remix",
  "version": "1.0",
  "author": "You",
  "minAppVersion": "2.9",
  "family": { "id": "microsoft", "name": "Microsoft Windows", "order": 2 },
  "release": { "label": "Windows 98", "year": 1998 },
  "experienceLevel": "full",
  "chrome": { "style": "win98" }
}
```

- **`id`** is the permanent key for every per-theme setting the user makes (wallpaper choice,
  dock position, icon overrides). Lowercase ASCII, digits, `.` and `-`, at most 128 characters,
  reverse-DNS by convention. Never change it once the theme is out. A manifest without one gets
  a generated `legacy.<slug>.<hash>` id, written back into the file on first load.
- **`name`** is what people see. Renaming is safe because nothing keys off it.
- **`minAppVersion`** — the oldest RetroMac the theme works on, compared numerically
  (`"2.9"` = `"2.9.0"`, and `2.10` is newer than `2.9`). A theme that needs a desktop icon type
  or manifest key this build does not have is skipped with a line in the log rather than loaded
  half-way. Leave it out for anything a 2.x understands.
- **`family.id`** groups the picker: `apple`, `microsoft`, `be`, `ibm`, `sgi`, `amiga`, `next`,
  `personal`, `screen`. `order` sorts families; `release.year` sorts inside one.
- **`experienceLevel`**: `full` (dock, desktop, windows, boot, everything), `partial`, `minimal`.
- **`chrome.style`** picks how windows, widgets and menus are drawn. One of `win31`, `win98`,
  `winxp`, `win7`, `macos6`, `macos9`, `macosx`, `snowleopard`, `beos`, `nextstep`, `futurama`,
  `maiksfav`, `default`. There is no "custom" chrome yet; pick the nearest.

## Dock and taskbar

Everything under `"dock"`. Sizes are points.

| Key | What it does |
|---|---|
| `height`, `iconSize`, `padding`, `spacing` | The bar and the tiles in it |
| `position` | `bottom` (default), `top`, `left`, `right`; `orientation` `horizontal`/`vertical` |
| `fullWidth` | `true` for a taskbar spanning the screen edge |
| `alignment`, `edgeOffset` | Where a floating dock sits (`center`/`left`/`right`, distance from the edge) |
| `backgroundColor`, `backgroundGradientTop/Bottom`, `backgroundImage`, `backgroundImageMode` | The bar's face; hex `#RRGGBB` or `#RRGGBBAA` |
| `borderColor`, `borderWidth`, `cornerRadius`, `shadow*` | Outline and shadow |
| `bevelTopColor`, `bevelBottomColor`, `bevelWidth` | The 3D edge of the Windows 9x bar |
| `pinstripe` | Aqua's fine horizontal texture |
| `shelfStyle` | `flat` or `3d` (Snow Leopard's perspective shelf); `shelfLineColor` |
| `startButton`, `startButtonLabel`, `startButtonIcon`, `startButtonImage`, `startButtonStyle`, `startButtonColor`, `startButtonGradientTop/Bottom` | The Start button; `startButtonImage` is a sprite sheet with three states stacked vertically (normal, hover, pressed); `startButtonStyle` `raised`, `sunken`, `flat` |
| `startMenuStyle` | `classic` (Windows 95/98/Me cascade) or `xp` (Luna's two columns) |
| `showQuickLaunch` | `false` for Windows 95, which had none |
| `showClock`, `clockFormat`, `clockFontSize` | The tray clock; `clockFormat` in the `h:mm a` / `HH:mm` family |
| `showTrash`, `showUrlLauncher`, `showGrip`, `showDiskFree`, `showLabels` | Extra tiles: trash, an editable URL tile, the BeOS grip, OS/2's disk-free readout, Aqua's name labels |
| `magnification`, `magnificationScale` | Aqua magnification |
| `windowPreview`, `folderStacks` | Hover previews and folder fans |
| `borderStyle` | `pacman` or `doomslayer` — the animated dock borders |
| `dockStyle` | `dock` (default), `controlStrip` (Mac OS 9.2 Classic: a strip of apps), `controlStripModules` (Mac OS 9 (authentic): a Control Strip of system modules — network, battery, media bay, sharing, keychain, colours, resolution, printer, volume, sound source, mirroring — and no dock at all; it needs `icons/controlstrip-left.png` and `controlstrip-right.png` for the tab and the size box, and takes `icons/strip-<module id>.png` (32 px) for a module's picture and `strip-arrow-left/right.png` (24 px) for the scroll arrows), `deskbar` (BeOS), `none` (no bar; Windows 3.1's Program Manager and NeXTSTEP bring their own) |
| `appIcon` | RetroMac's own Dock icon while the theme is on, from `icons/` |

`"icon"` holds `renderStyle` (`smooth` or `pixelated` — nearest-neighbour for 16-colour art),
`reflectionEnabled`, `reflectionOpacity`, `hoverScale`, `hoverAnimationDuration`, and
`monochrome` (`true` desaturates apps the theme has no icon for, as System 6 does).

`"indicator"` is the running-app mark: `style` `dot`, `square`, `triangle`, `glow`, `highlight`
or `none`, plus `color`, `size`, `offset`.

## Icons

```json
"fallbackIcon": "generic.png",
"iconMappings": {
  "com.apple.Safari": "ie.png",
  "com.apple.finder": "finder.png",
  "__folder__~/Downloads": "downloads.png"
}
```

Keys are bundle identifiers; the value is a file in `icons/`. Apps without a mapping get their
real macOS icon (or `fallbackIcon`, or the monochrome treatment). Folder tiles in the dock are
addressed as `__folder__~/Path`, with `~` for the home directory. The user can override any
mapping from the dock's context menu; those overrides are stored per theme `id`, not in the
manifest.

## Wallpaper

```json
"wallpaper": "wallpaper.jpg",
"wallpapers": [
  { "name": "Teal", "file": "wallpaper-teal.png" },
  { "name": "Black Thatch", "file": "tile-black-thatch.png", "tiled": true }
],
"wallpaperTiled": false
```

`wallpaper` is the default; `wallpapers` the list Settings ▸ Desktop offers. `tiled: true` on an
option repeats a small pattern edge to edge instead of stretching it; `wallpaperTiled` on the
theme tiles everything (System 6's 8×8 patterns). Tiles are pre-rendered per screen at 1:1
pixels, so supply them at their native size.

## The desktop

```json
"desktopIconsSide": "left",
"desktopIconSize": 40,
"desktopIcons": [
  { "name": "My Computer", "icon": "computer.png", "type": "folder", "path": "/", "gridX": 0, "gridY": 0 },
  { "name": "Recycle Bin", "icon": "trash_empty.png", "iconFull": "trash_full.png", "type": "trash", "gridX": 0, "gridY": 6 },
  { "name": "Doom", "icon": "doom.png", "type": "app", "bundleID": "org.gzdoom", "gridX": 1, "gridY": 0 },
  { "name": "ZIP 100 (D:)", "icon": "", "type": "zipdrive", "gridX": 1, "gridY": 8 }
]
```

`gridX`/`gridY` are cells from the top-left (Windows) or top-right (Mac, the default) corner;
leave them out and the icon takes the next free cell. Users can move and remove icons; that
too is stored per theme `id`. The `type` decides what a double-click does:

| Type | Opens |
|---|---|
| `folder` | `path` in Finder (`~` allowed) |
| `app` | `bundleID`, with optional `args` |
| `url` | `url` in the default browser |
| `webapp` | `url` inside a themed window (the era's chrome around a web page) |
| `trash` | The Trash; `iconFull` is shown while it has contents |
| `network` | Network Neighbourhood: the Network pane |
| `appfolder` | A themed "Programs" window listing `/Applications` |
| `tvfolder` | The television bookmarks as a folder |
| `readme` | The theme's `readme.html` |
| `screensaver` | Starts the theme's screensaver |
| `defrag`, `zipdrive`, `funstuff`, `pacman`, `sheep`, `expose`, `dashboard` | Era toys: Defrag, the Iomega Zip (click of death), the Windows 95 Fun Stuff CD, Pac-Man, the desktop pet, Exposé, Dashboard |
| `clock`, `cpumonitor`, `calculator`, `notepad`, `nyanochrome`, `tictactoe` | Widgets, as windows on the desktop |

Two themes replace the desktop wholesale: `programManager` (Windows 3.1's groups, each a list
of these same entries) and `sgiDesktop` (IRIX's Toolchest, Icon Catalog and Shelf). Copy the
bundled manifest if you need either; the shapes are in `DockTheme.swift`.

## Boot, screensaver, the rest of the Mac

| Key | What it does |
|---|---|
| `splashScreen` | Still shown while the theme switches on; `splashFullscreen: true` fills the screen |
| `splashVideo` | An H.264 `.mp4` played full screen with sound instead of the still |
| `splashWelcome` | `true` draws the "Welcome to Macintosh" screen (System 6) |
| `screensaver` | `pipes`, `flowerbox`, `flying-toasters`, `flurry` or `none` |
| `defaultPreset` | The shader preset the theme suggests |
| `menuBarApple` | What covers the Apple menu: `off`, `rainbow`, `aqua`, `aqua-classic`, `hell`, `futurama` |
| `desktopLabel` | How the desktop icons are labelled: `font` (PostScript name of an installed or shipped face — `PixelOperator`, `ChiKareGo2`, `Px437_IBM_VGA_9x16`), `size`, `color`, and `background`, a plate behind the text (Mac OS 9 (authentic): Pixel Operator 16 on `#CFCFE1`). Absent: white system text with a shadow |
| `menuBar.appleMenu` | `true` makes the Apple cover a menu of its own — Mac OS 9's: About This Computer, Applications, Apple System Profiler, Calculator, Chooser, Control Panels, Favorites, Network Browser, Recent Applications / Documents / Servers, Sherlock 2, Stickies — each pointed at what macOS has today |
| `menuBar.applicationMenu` | `true` puts Mac OS 9's Application menu at the right end of the menu bar: the front app's icon, and Hide / Hide Others / Show All / the running apps under it (as far right as macOS lets a status item go) |
| `hideMenuBarDefault` | `true` hides the menu bar while the theme is on (the Windows themes) |
| `appearance`, `accentColor` | System appearance (`light`/`dark`) and accent to match when the user allows it |
| `chromeColors` | A Windows colour scheme (title bars, button face, bevels) for the `win98` chrome; the Plus! themes use it |
| `systemTweaks` | Cosmetic `defaults write` entries applied only when the user turns on "Classic Finder", snapshotted and reverted. Only the allow-listed keys in `SystemTweaksAdapter` are accepted |

## Cursors

Cursor sets are not part of the manifest yet. Settings ▸ Themes assigns a bundled set by theme
name (`CursorThemeManager+Classic.swift`); a new theme gets the system pointer until the user
picks a set. A set is a folder of PNGs with a `manifest.json` naming each cursor's `size`,
`hotspot`, `frameCount` and frame `dur`; `Resources/Cursors/` has the bundled ones.

## Checklist before sharing

1. `id` is set and yours; `minAppVersion` names the build you tested on.
2. Every file the manifest names exists, inside the folder, with the exact case.
3. `preview.jpg` is a real screenshot of the theme, about 800 px wide.
4. `icons/CREDITS.txt` says where borrowed artwork came from and under what terms. See
   [LEGAL.md](../LEGAL.md) for how RetroMac handles that itself.
5. It loads cleanly: `~/Library/Logs/RetroMac/retromac.log` shows no `[Theme] Failed to load`.
