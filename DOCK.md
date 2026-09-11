# RetroMac Retro-Dock

An alternative, themable Dock that sits at the bottom of your screen. Designed to complement the RetroMac shader overlay with matching retro aesthetics.

## Features

- Themed dock bar with app icons, running indicators, hover animations
- Three built-in themes: Mac OS X Aqua, Mac OS 9 Platinum, Windows 95
- Custom theme support via `.retromactheme` bundles
- Auto-show when System Dock is hidden
- Drag & drop to add apps, right-click context menus
- Per-app custom icons
- Hotkey toggle (default: Ctrl+Option+Cmd+D)
- Hides automatically when a fullscreen app is active

## Settings

The dock is configured under **Settings ▸ Themes**:

- **Theme** — pick a built-in or custom theme; "Add custom…" imports a `.retromactheme` bundle
- **Behaviour** — RetroMac in the macOS Dock, activate the theme on launch, boot screens
- **Dock** — on/off, show only when the system Dock is hidden, position, per-theme dock styles,
  running-app indicators, 24-hour clock
- **Theme extras** — what a particular theme brings along (Plus! schemes, the tray messenger,
  Re:Amp, Pac-Man, the Doom Slayer)
- **System integration** — window borders, appearance, cursor, Terminal profile, Classic Finder,
  theme icons for system apps
- **Apps in the dock** — the app list, with per-app custom icons
- **Advanced** — transparency, icon scale, target display, and the theme files

The dock hotkey is under **Settings ▸ Shortcuts**; the desktop icons, their size, the wallpaper and
the menu bar under **Settings ▸ Desktop**. `docs/SETTINGS.md` describes the whole settings window.

## Themes

### Built-in Themes

| Theme | Style | Icon Size |
|-------|-------|-----------|
| Mac OS X Aqua | Glossy white bar, rounded corners, reflections | 64px |
| Mac OS 9 Platinum | Flat gray, 3D beveled edges, pixelated icons | 32px |
| Windows 95 | Silver gray, 3D bevel, pixelated icons, square indicators | 32px |

### Custom Themes

Themes are directory bundles with the extension `.retromactheme`:

```
MyTheme.retromactheme/
  theme.json       -- Theme configuration
  icons/           -- Custom app icons (PNG)
  preview.png      -- Preview image for settings UI
```

Place custom themes in:
`~/Library/Application Support/RetroMac/DockThemes/`

Or double-click a `.retromactheme` bundle to import it.

### theme.json

See the built-in themes in `Resources/Themes/` for the full schema. Key properties:

- `dock.height`, `dock.iconSize`, `dock.spacing`, `dock.padding`
- `dock.backgroundColor` (hex with alpha, e.g. `#FFFFFFCC`)
- `dock.cornerRadius`, `dock.borderColor`, `dock.borderWidth`
- `dock.bevelTopColor`, `dock.bevelBottomColor`, `dock.bevelWidth` (for 3D look)
- `icon.renderStyle`: `"smooth"` or `"pixelated"`
- `icon.hoverScale`, `icon.hoverAnimationDuration`
- `indicator.style`: `"dot"` or `"square"`
- `iconMappings`: maps bundle IDs to icon filenames in the `icons/` folder

### Icon Licensing

The built-in themes ship with placeholder icons (solid-color squares). For authentic retro icons, place your own PNGs in the theme's `icons/` directory.

Recommended sources for retro icons:
- macOS system icons (extracted from your own system)
- Open-source icon sets
- Your own pixel art

Do not redistribute copyrighted icons without permission.

## Dock Apps

The app list is stored in:
`~/Library/Application Support/RetroMac/dock-apps.json`

Default apps are populated on first launch. You can:
- Add apps via the Settings tab or by dragging `.app` files onto the dock
- Remove apps via right-click context menu
- Reorder in the Settings tab
- Set custom icons per app via right-click
