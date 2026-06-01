# Amiga Workbench 4.1 — RetroMac Theme Mapping

Reproduces the **AmigaOS 4.1 Final Edition** (PowerPC era) default GUI — the neutral
gray *ReAction* ("Brücke"/bridge-style) look, Glow-icon style, antialiased sans-serif.
NOT Workbench 1.x/3.x (no blue/orange palette).

## How RetroMac represents themes

RetroMac themes are **auto-discovered** by scanning `Resources/Themes/*.retromactheme`
(`ThemeManager.reload()`), so no registry edit is needed. Each theme is a *dock/taskbar*
plus optional *desktop overlay* (`desktopIcons`, `programManager`, `sgiDesktop`). There is
**no dedicated window-titlebar / menu-bar color struct** in the schema — window chrome is
drawn by the overlay views. The closest analogue to the Amiga *screen title bar / menu bar*
(which sits at the top of the screen) is a top-positioned, full-width dock bar with the
ReAction 3D bevel + steel-gray gradient. SGI-IRIX is the closest existing template (flat
gray bar, bevel, desktop icons).

### Supported theme variables (the ones RetroMac actually honours)
- **dock**: height, iconSize, padding, spacing, cornerRadius, backgroundColor,
  backgroundImage, backgroundImageMode, borderColor, borderWidth, shadowEnabled/Color/Radius,
  bevelTopColor, bevelBottomColor, bevelWidth, backgroundGradientTop, backgroundGradientBottom,
  shelfLineColor, orientation, position (`top`/`bottom`), fullWidth, alignment, edgeOffset,
  startButton(+Label/Icon/Style), showClock, clockFormat, clockFontSize, magnification(+Scale),
  shelfStyle, showTrash, showGrip, startMenuStyle, showDiskFree, dockStyle (`dock`/`controlStrip`/`none`)
- **icon**: renderStyle (`smooth`/`pixelated`), reflectionEnabled, reflectionOpacity, hoverScale, hoverAnimationDuration
- **indicator**: style (`dot`/`square`/`none`), color, size, offset
- **top-level**: name, version, author, wallpaper, wallpapers[], defaultPreset (CRT shader),
  fallbackIcon, iconMappings{}, desktopIcons[], programManager{}, sgiDesktop{}, splashScreen, splashFullscreen

## Workbench-4.1 element → researched hex → RetroMac variable

| Workbench 4.1 element | Approx. hex | RetroMac variable |
|---|---|---|
| Desktop/screen background (neutral gray) | `#9B9B9F` (flat) / `#A6A6AA`→`#8E8E92` gradient | `wallpaper.png` (generated) |
| Screen title / menu bar fill | `#AEAEB2` | `dock.backgroundColor` |
| Title-bar gradient (active, top-lit steel) | `#D4D8DE` → `#A8AEB6` | `dock.backgroundGradientTop` / `…Bottom` |
| 3D bevel highlight edge (ReAction) | `#E6E6EA` | `dock.bevelTopColor` |
| 3D bevel shadow edge | `#6E6E72` | `dock.bevelBottomColor` (bevelWidth 1) |
| Window/bar frame outline | `#5E5E62` | `dock.borderColor` (borderWidth 1) |
| Clock/text on bar | black `#000000` | (rendered black by dock) |
| Bar position (Amiga bar = top of screen) | — | `dock.position: "top"`, `fullWidth: true` |
| Icons (Glow style, smooth/antialiased) | — | `icon.renderStyle: "smooth"` |
| Disk/drawer/RAM desktop icons | — | `desktopIcons[]` → generated Glow-ish PNGs |

### Glow / ReAction selection accent (researched, not directly settable)
- ReAction selection blue ≈ `#4A6CA8`; pressed-gadget darker gray ≈ `#888890`.
  RetroMac has no per-theme window-selection color slot, so this is **not represented**
  (would require window-chrome rendering the schema lacks).

## Deliberate compromises / remaining differences
1. **No real window chrome.** AmigaOS draws per-window title bars with depth/zoom/sizing
   gadgets and the iconify (Amiga-key) gadget. RetroMac's schema has no window-titlebar
   color struct, so the *screen bar* is approximated by the top dock bar only. Largest visual gap.
2. **Menu bar is right-mouse pull-down on real Amiga** (hidden until RMB). RetroMac shows a
   persistent top bar instead — closest available behavior.
3. **ReAction glass-button gadgets** (subtle vertical glass gradient on buttons) cannot be
   themed individually; approximated only by the bar's bevel + gradient.
4. **Glow icons** are copyrighted; bundled icons are simple original bevel/gradient
   stand-ins (`drawer.png`, `harddrive.png`, `ramdisk.png`) in the Glow color spirit
   (warm-gray drawer, steel HD, blue RAM), not the real artwork.
5. **Wallpaper** is an original solid/subtle-gray gradient PNG matching the default OS4
   desktop gray — no copyrighted Boing/AmigaOS imagery bundled.
6. **Font**: real WB default is an antialiased sans (DejaVu-like). RetroMac renders bar/label
   text in the system font; not separately settable per theme.
7. `defaultPreset` set to `lcd-sharp-lite` for a clean flat-panel look (OS4 ran on
   modern monitors, so no heavy CRT curvature).
