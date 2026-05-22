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

All dock settings are in the "Dock" tab of RetroMac Settings:

- **Enable/Disable** the retro dock
- **Auto-show** only when System Dock is set to auto-hide
- **Theme** selection from built-in and custom themes
- **Transparency** slider
- **Target display** for multi-monitor setups
- **Hotkey** configuration
- **App list** management

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
