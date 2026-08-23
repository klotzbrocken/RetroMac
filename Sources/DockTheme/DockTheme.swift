import AppKit

struct DockThemeConfig: Codable {
    var name: String
    var version: String = "1.0"
    var author: String = "RetroMac"

    // ── Manifest 2.0 identity (all optional — a 1.x theme.json still decodes unchanged) ──
    //
    // `name` used to be the theme's ONLY identity: display name, stored selection, and the key
    // for every per-theme setting. That made renaming lossy and let two themes collide. These
    // fields separate a stable, never-localised `id` from the human-facing `name`.
    //
    // NOTE: `ThemeBundle.save(config:)` re-encodes only the fields modelled here, so anything a
    // theme author puts in theme.json that is NOT in this struct is dropped on save. Every
    // manifest field we intend to preserve must therefore be declared.
    var schemaVersion: Int? = nil
    /// Permanent, lowercase, non-localised identifier (e.g. "com.retromac.microsoft.windows98").
    /// Never derived from the folder name — the folder and the display name can disagree
    /// (MacOSX-Aqua.retromactheme is called "Mountain Lion"). See `ThemeBundle.stableID`.
    var id: String? = nil
    var family: Family? = nil
    var release: Release? = nil
    /// How complete this theme's era illusion is: "full" | "partial" | "minimal".
    var experienceLevel: String? = nil
    /// Refuse/warn if the running RetroMac is older than this (e.g. "2.4").
    var minimumRetroMacVersion: String? = nil
    /// Declared window/widget chrome. `chrome.style` replaces the display-name heuristic in
    /// `RetroFrameTheme.key()` — see that file.
    var chrome: ChromeDecl? = nil

    /// The OS family this theme belongs to, for grouping themes in the UI.
    struct Family: Codable {
        var id: String                // "windows", "apple", "be", …
        var name: String? = nil       // "Microsoft Windows"
        var order: Int? = nil         // sort position among families
    }

    /// The specific OS release this theme recreates.
    struct Release: Codable {
        var label: String? = nil      // "Windows 98"
        var year: Int? = nil          // 1998
    }

    /// Declarative chrome selection. `style` is the key every chrome/border/widget renderer
    /// already switches on ("win98", "winxp", "win7", "macos9", "macos6", "macosx", "win31",
    /// "beos", "maiksfav", "default").
    struct ChromeDecl: Codable {
        var style: String? = nil
    }
    var dock: DockStyle
    var icon: IconStyle
    var indicator: IndicatorStyle
    var fallbackIcon: String? = nil
    var wallpaper: String? = nil
    var wallpaperTiled: Bool? = nil   // true = wallpaper is a small pattern tile (e.g. System 6 8×8) — pre-rendered per screen
    var wallpapers: [WallpaperOption]? = nil
    var defaultPreset: String? = nil
    var iconMappings: [String: String]
    var desktopIcons: [DesktopIconEntry]? = nil
    var desktopIconSize: CGFloat? = nil        // per-theme desktop icon size (e.g. Win98: 40)
    var programManager: ProgramManagerConfig? = nil
    var sgiDesktop: SGIDesktopConfig? = nil
    var menuBarApple: String? = nil   // default menu-bar Apple cover for this theme: off|rainbow|aqua|aqua-classic
    var hideMenuBarDefault: Bool? = nil   // when set, activating this theme applies it to Settings.hideMenuBar (Win 95/XP hide it)
    var appearance: String? = nil     // system appearance to match when "Match appearance" is on: light|dark
    var accentColor: String? = nil    // system accent to match: graphite|blue|red|orange|yellow|green|purple|pink
    var splashScreen: String? = nil   // boot splash image shown briefly on theme activation
    var splashFullscreen: Bool? = nil // true = fill the whole screen (e.g. Win 98 boot)
    var splashVideo: String? = nil    // boot video (H.264 mp4) played fullscreen with sound, if present
    var splashWelcome: Bool? = nil    // true = draw the classic "Welcome to Macintosh" boot screen (System 6)
    var screensaver: String? = nil    // default screensaver id for this theme (pipes/flowerbox/flying-toasters/flurry/none)
    var systemTweaks: [SystemTweak]? = nil   // optional "Classic Finder" defaults writes (see SystemTweaksAdapter)
    var chromeColors: ChromeColors? = nil    // per-scheme window-chrome palette (Win98 Plus! themes); nil = built-in defaults

    struct WallpaperOption: Codable {
        var name: String
        var file: String
    }

    /// A Windows-style appearance colour scheme (from a `.theme` `[Control Panel\Colors]` section):
    /// recolours the title bar, window face, and 3D button bevels. All hex ("#RRGGBB"), all optional
    /// so a partial scheme falls back to the built-in look. Fed to `ChromeStyle`, the dock, and the
    /// widgets (as CSS variables) so one scheme recolours every Win98 surface consistently.
    struct ChromeColors: Codable {
        var activeTitle: String? = nil       // active title bar (gradient start / solid)
        var activeTitleEnd: String? = nil    // gradient end (nil → solid activeTitle)
        var titleText: String? = nil
        var inactiveTitle: String? = nil
        var inactiveTitleText: String? = nil
        var face: String? = nil              // ButtonFace — the 3D grey (window/body/button fill)
        var hilight: String? = nil           // ButtonHilight — lightest bevel edge
        var light: String? = nil             // ButtonLight
        var shadow: String? = nil            // ButtonShadow
        var dkShadow: String? = nil          // ButtonDkShadow — darkest bevel edge
        var window: String? = nil            // content background
        var windowText: String? = nil
        var menu: String? = nil
        var menuText: String? = nil
        var selection: String? = nil         // Hilight (selection background)
        var selectionText: String? = nil
    }

    /// A single cosmetic `defaults write` that makes the real Finder/system look like this
    /// theme's era. Applied only when the user opts in (Settings ▸ Dock ▸ "Classic Finder");
    /// snapshotted + fully reverted by SystemTweaksAdapter. STRICTLY cosmetic — never security.
    struct SystemTweak: Codable {
        var domain: String        // "-g" (NSGlobalDomain) | "com.apple.finder" | "com.apple.dock" | "com.apple.universalaccess"
        var key: String
        var type: String          // "bool" | "int" | "float" | "string"
        var value: String         // literal, e.g. "true" | "36" | "0.001" | "Nlsv"
        var refresh: String? = nil // app to killall so the change shows: "Finder" | "Dock" | nil
    }

    /// Windows 3.1 Program Manager — outer MDI frame containing group windows.
    struct ProgramManagerConfig: Codable {
        var title: String = "Program Manager"
        var groups: [ProgramGroup]
    }

    /// A Program Manager group window (Main, Accessories, Games, Applications).
    struct ProgramGroup: Codable {
        var name: String                  // Title bar text ("Main")
        var x: Int? = nil                 // Initial frame within workspace (top-left origin)
        var y: Int? = nil
        var width: Int? = nil
        var height: Int? = nil
        var minimized: Bool? = nil        // Start collapsed to a group icon
        var items: [DesktopIconEntry]     // Program items (reuses DesktopIconEntry)
    }

    /// SGI IRIX (4Dwm) desktop — Toolchest menu, Icon Catalog window(s), and Shelf icons.
    struct SGIDesktopConfig: Codable {
        var toolchest: [ToolchestEntry]
        var iconCatalog: [ProgramGroup]    // reuse ProgramGroup as catalog pages/windows
        var shelf: [DesktopIconEntry]      // icons placed directly on the desktop
    }

    /// A Toolchest menu entry — either a submenu or a leaf that launches something.
    struct ToolchestEntry: Codable {
        var title: String
        var submenu: [ToolchestEntry]? = nil
        var item: DesktopIconEntry? = nil
    }

    /// A desktop icon defined by the theme — shown on the wallpaper overlay.
    struct DesktopIconEntry: Codable {
        var name: String             // Display label ("Trash", "Doom", "My Computer")
        var icon: String             // Filename in theme's icons/ dir ("trash_empty.png")
        var iconFull: String? = nil  // For type "trash" — full trash icon ("trash_full.png")
        var type: String             // "trash", "app", "folder", "url"
        var bundleID: String? = nil  // For type "app" — e.g. "org.gzdoom"
        var args: [String]? = nil    // For type "app" — launch arguments
        var url: String? = nil       // For type "url" — e.g. "https://..."
        var path: String? = nil      // For type "folder" — e.g. "~/Documents"
        var gridX: Int? = nil        // Column position (0-based, from right)
        var gridY: Int? = nil        // Row position (0-based, from top)
    }

    struct DockStyle: Codable {
        var height: CGFloat = 80
        var iconSize: CGFloat = 64
        var padding: CGFloat = 12
        var spacing: CGFloat = 8
        var cornerRadius: CGFloat = 16
        var backgroundColor: String = "#FFFFFFCC"
        var backgroundImage: String? = nil
        var backgroundImageMode: String = "tile"
        var borderColor: String = "#00000040"
        var borderWidth: CGFloat = 1
        var shadowEnabled: Bool = true
        var shadowColor: String = "#00000060"
        var shadowRadius: CGFloat = 12
        var bevelTopColor: String? = nil
        var bevelBottomColor: String? = nil
        var bevelWidth: CGFloat = 0
        var backgroundGradientTop: String?
        var backgroundGradientBottom: String?
        var shelfLineColor: String?
        var orientation: String?
        var position: String?
        var fullWidth: Bool?
        var startButton: Bool?
        var startButtonLabel: String?
        var startButtonIcon: String?
        var showClock: Bool?
        var magnification: Bool?
        var magnificationScale: CGFloat?
        var shelfStyle: String?  // "flat" (default) or "3d" (Snow Leopard perspective)
        var alignment: String?   // "center" (default), "left", "right"
        var edgeOffset: CGFloat? // distance from screen edge in px (default 8)
        var borderStyle: String? // nil = normal bevel/border; "pacman" = animated pellet border; "doomslayer" = Doom Slayer patrols the lower edge
        var showTrash: Bool?     // show trash icon at end of dock
        var showUrlLauncher: Bool?   // editable URL-launcher tile, placed left of the trash
        var pinstripe: Bool?         // fine horizontal Aqua pinstripe texture over the dock bg
        var showLabels: Bool?        // show the app name above the magnified icon (Aqua dock)
        var showGrip: Bool?      // show grip dots handle (BeOS deskbar style)
        var startMenuStyle: String?  // "classic" (Win98-style), "xp" (Luna Blue two-column)
        var showQuickLaunch: Bool?   // Windows Quick Launch (pinned tiles + Show Desktop); false = Win95, which had none
        var startButtonColor: String?
        var startButtonGradientTop: String?
        var startButtonGradientBottom: String?
        var startButtonImage: String?  // sprite sheet PNG with 3 vertical states (normal/hover/pressed)
        var startButtonStyle: String?  // "raised" (default, Win98), "sunken" (OS/2 WarpCenter tray), "flat"
        var clockFormat: String?       // strftime-style: "h:mm a" (default), "hh:mm:ss a", "HH:mm", etc.
        var clockFontSize: CGFloat?    // explicit clock font size override
        var showDiskFree: Bool?        // show disk free space tray (OS/2 WarpCenter style)
        var dockStyle: String?         // nil/"dock" (default), "controlStrip" (Mac OS 9 Control Strip)
        var windowPreview: Bool?       // hover a running app's icon ~2s → show a (pixel) window preview
        var folderStacks: Bool?        // click a folder dock item → fan out its recent files
        var appIcon: String?           // icons/<file>: app's Dock icon in Dock Mode (theme-aware)
    }

    struct IconStyle: Codable {
        var renderStyle: String = "smooth"
        var reflectionEnabled: Bool = true
        var reflectionOpacity: Float = 0.3
        var hoverScale: CGFloat = 1.15
        var hoverAnimationDuration: Double = 0.15
        var monochrome: Bool? = nil   // true = un-mapped (system) app icons are desaturated to B/W
    }

    struct IndicatorStyle: Codable {
        var style: String = "dot"
        var color: String = "#FFFFFF"
        var size: CGFloat = 4
        var offset: CGFloat = 4
    }
}

extension DockThemeConfig {
    /// THE key for every per-theme setting (preset, wallpaper, dock position, auto-hide, …).
    /// `ThemeBundle` guarantees `id` is populated for every loaded theme — a legacy theme gets a
    /// generated `legacy.*` id written into its manifest on first load — so this is the stable
    /// identity, not the renameable display name. The `name` fallback only covers a config that
    /// was built in memory rather than loaded through `ThemeBundle`.
    var settingsKey: String { id ?? name }

    var parsedBackgroundColor: NSColor { NSColor.fromHex(dock.backgroundColor) }
    var parsedBorderColor: NSColor { NSColor.fromHex(dock.borderColor) }
    var parsedShadowColor: NSColor { NSColor.fromHex(dock.shadowColor) }
    var parsedIndicatorColor: NSColor { NSColor.fromHex(indicator.color) }
    var parsedBevelTopColor: NSColor? { dock.bevelTopColor.map { NSColor.fromHex($0) } }
    var parsedBevelBottomColor: NSColor? { dock.bevelBottomColor.map { NSColor.fromHex($0) } }
    var parsedGradientTop: NSColor? { dock.backgroundGradientTop.map { NSColor.fromHex($0) } }
    var parsedGradientBottom: NSColor? { dock.backgroundGradientBottom.map { NSColor.fromHex($0) } }
    var parsedShelfLineColor: NSColor? { dock.shelfLineColor.map { NSColor.fromHex($0) } }
    var hasGradientBackground: Bool { dock.backgroundGradientTop != nil && dock.backgroundGradientBottom != nil }

    var isPixelated: Bool { icon.renderStyle == "pixelated" }

    /// The dock edge after applying any user override: "top"/"bottom"/"left"/"right".
    var effectiveDockPosition: String {
        if let p = AppSettings.shared.themeDockPositionOverride[settingsKey],
           ["top", "bottom", "left", "right"].contains(p) { return p }
        return dock.position ?? "bottom"
    }

    var isVertical: Bool {
        // A user position override on the left/right edges forces vertical layout.
        if let p = AppSettings.shared.themeDockPositionOverride[settingsKey] {
            return p == "left" || p == "right"
        }
        if let override = AppSettings.shared.themeOrientationOverrides[settingsKey] {
            return override == "vertical"
        }
        return dock.orientation == "vertical"
    }

    /// Themes whose real-world dock/taskbar supported auto-hide.
    var supportsAutoHide: Bool {
        ["Snow Leopard", "Mountain Lion", "Windows XP", "Windows 98", "Windows 95", "Windows Me", "Windows 7", "OS/2 Warp 4"].contains(name)
    }
    var dockAutoHideEnabled: Bool {
        supportsAutoHide && (AppSettings.shared.themeDockAutoHide[settingsKey] ?? false)
    }
    var isFullWidth: Bool { dock.fullWidth == true }
    var hasStartButton: Bool { dock.startButton == true }
    var hasClock: Bool { dock.showClock == true }
    var hasMagnification: Bool { dock.magnification == true }
    var magnificationMaxScale: CGFloat { dock.magnificationScale ?? 2.0 }
    var has3DShelf: Bool { dock.shelfStyle == "3d" }
    /// This theme's default menu-bar Apple style (0 off, 1 rainbow, 2 aqua, 3 aqua classic), or nil to leave as-is.
    var menuBarAppleStyleDefault: Int? {
        switch menuBarApple?.lowercased() {
        case "off": return 0
        case "rainbow": return 1
        case "aqua": return 2
        case "aqua-classic", "aquaclassic", "classic": return 3
        case "hell", "apple-hell", "doom": return 4
        case "futurama", "teal": return 5
        default: return nil
        }
    }
    var dockAlignment: String { dock.alignment ?? "center" }
    var dockEdgeOffset: CGFloat { dock.edgeOffset ?? 8 }
    var hasTrash: Bool { dock.showTrash == true }
    var hasUrlLauncher: Bool { dock.showUrlLauncher == true }
    var hasGrip: Bool { dock.showGrip == true }
    var startMenuStyle: String { dock.startMenuStyle ?? "classic" }
    var showQuickLaunch: Bool { dock.showQuickLaunch ?? true }
    var isXPStartMenu: Bool { startMenuStyle == "xp" }
    var hasDiskFree: Bool { dock.showDiskFree == true }
    var isControlStrip: Bool { dock.dockStyle == "controlStrip" }
    /// Maiks-Favourite extras: hover a running icon → window preview; click a folder → file fan.
    var hasWindowPreview: Bool { dock.windowPreview == true }
    var hasFolderStacks: Bool { dock.folderStacks == true }
    /// BeOS Classic Deskbar — a vertical panel (Be menu + status + app list) replacing the dock.
    var isDeskbar: Bool { dock.dockStyle == "deskbar" }
    /// When true, no dock/taskbar bar is shown (e.g. Windows 3.1 Program Manager desktop,
    /// the BeOS Deskbar, or NeXTSTEP — all provide their own panel instead of RetroMac's DockView).
    var hidesDock: Bool { dock.dockStyle == "none" || dock.dockStyle == "deskbar" || isNextStep }

    /// NeXTSTEP theme: shows the always-on-screen vertical Workspace menu (top-left). Gated on the
    /// declared chrome so only the NeXT theme brings up that panel.
    var isNextStep: Bool { chrome?.style == "nextstep" }
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }

        var rgba: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgba)

        let r, g, b, a: CGFloat
        switch h.count {
        case 6:
            r = CGFloat((rgba >> 16) & 0xFF) / 255
            g = CGFloat((rgba >> 8) & 0xFF) / 255
            b = CGFloat(rgba & 0xFF) / 255
            a = 1.0
        case 8:
            r = CGFloat((rgba >> 24) & 0xFF) / 255
            g = CGFloat((rgba >> 16) & 0xFF) / 255
            b = CGFloat((rgba >> 8) & 0xFF) / 255
            a = CGFloat(rgba & 0xFF) / 255
        default:
            return .white
        }
        return NSColor(red: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FFFFFFFF" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        let a = Int(c.alphaComponent * 255)
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
