import AppKit

struct DockThemeConfig: Codable {
    var name: String
    var version: String = "1.0"
    var author: String = "RetroMac"
    var dock: DockStyle
    var icon: IconStyle
    var indicator: IndicatorStyle
    var fallbackIcon: String? = nil
    var wallpaper: String? = nil
    var wallpapers: [WallpaperOption]? = nil
    var defaultPreset: String? = nil
    var iconMappings: [String: String]
    var desktopIcons: [DesktopIconEntry]? = nil
    var desktopIconSize: CGFloat? = nil        // per-theme desktop icon size (e.g. Win98: 40)
    var programManager: ProgramManagerConfig? = nil
    var sgiDesktop: SGIDesktopConfig? = nil
    var splashScreen: String? = nil   // boot splash image shown briefly on theme activation
    var splashFullscreen: Bool? = nil // true = fill the whole screen (e.g. Win 98 boot)

    struct WallpaperOption: Codable {
        var name: String
        var file: String
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
        var borderStyle: String? // nil = normal bevel/border; "pacman" = animated pellet border
        var showTrash: Bool?     // show trash icon at end of dock
        var showUrlLauncher: Bool?   // editable URL-launcher tile, placed left of the trash
        var pinstripe: Bool?         // fine horizontal Aqua pinstripe texture over the dock bg
        var showLabels: Bool?        // show the app name above the magnified icon (Aqua dock)
        var showGrip: Bool?      // show grip dots handle (BeOS deskbar style)
        var startMenuStyle: String?  // "classic" (Win98-style), "xp" (Luna Blue two-column)
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
    }

    struct IconStyle: Codable {
        var renderStyle: String = "smooth"
        var reflectionEnabled: Bool = true
        var reflectionOpacity: Float = 0.3
        var hoverScale: CGFloat = 1.15
        var hoverAnimationDuration: Double = 0.15
    }

    struct IndicatorStyle: Codable {
        var style: String = "dot"
        var color: String = "#FFFFFF"
        var size: CGFloat = 4
        var offset: CGFloat = 4
    }
}

extension DockThemeConfig {
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
        if let p = AppSettings.shared.themeDockPositionOverride[name],
           ["top", "bottom", "left", "right"].contains(p) { return p }
        return dock.position ?? "bottom"
    }

    var isVertical: Bool {
        // A user position override on the left/right edges forces vertical layout.
        if let p = AppSettings.shared.themeDockPositionOverride[name] {
            return p == "left" || p == "right"
        }
        if let override = AppSettings.shared.themeOrientationOverrides[name] {
            return override == "vertical"
        }
        return dock.orientation == "vertical"
    }

    /// Themes whose real-world dock/taskbar supported auto-hide.
    var supportsAutoHide: Bool {
        ["Snow Leopard", "Mountain Lion", "Windows XP", "Windows 98", "OS/2 Warp 4", "Sleek Retro"].contains(name)
    }
    var dockAutoHideEnabled: Bool {
        supportsAutoHide && (AppSettings.shared.themeDockAutoHide[name] ?? false)
    }
    var isFullWidth: Bool { dock.fullWidth == true }
    var hasStartButton: Bool { dock.startButton == true }
    var hasClock: Bool { dock.showClock == true }
    var hasMagnification: Bool { dock.magnification == true }
    var magnificationMaxScale: CGFloat { dock.magnificationScale ?? 2.0 }
    var has3DShelf: Bool { dock.shelfStyle == "3d" }
    var dockAlignment: String { dock.alignment ?? "center" }
    var dockEdgeOffset: CGFloat { dock.edgeOffset ?? 8 }
    var hasTrash: Bool { dock.showTrash == true }
    var hasUrlLauncher: Bool { dock.showUrlLauncher == true }
    var hasGrip: Bool { dock.showGrip == true }
    var startMenuStyle: String { dock.startMenuStyle ?? "classic" }
    var isXPStartMenu: Bool { startMenuStyle == "xp" }
    var hasDiskFree: Bool { dock.showDiskFree == true }
    var isControlStrip: Bool { dock.dockStyle == "controlStrip" }
    /// Maiks-Favourite extras: hover a running icon → window preview; click a folder → file fan.
    var hasWindowPreview: Bool { dock.windowPreview == true }
    var hasFolderStacks: Bool { dock.folderStacks == true }
    /// BeOS Classic Deskbar — a vertical panel (Be menu + status + app list) replacing the dock.
    var isDeskbar: Bool { dock.dockStyle == "deskbar" }
    /// When true, no dock/taskbar bar is shown (e.g. Windows 3.1 Program Manager desktop,
    /// or the BeOS Deskbar which provides its own panel instead).
    var hidesDock: Bool { dock.dockStyle == "none" || dock.dockStyle == "deskbar" }
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
