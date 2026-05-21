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
    var defaultPreset: String? = nil
    var iconMappings: [String: String]

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
        var orientation: String?
        var position: String?
        var fullWidth: Bool?
        var startButton: Bool?
        var startButtonLabel: String?
        var startButtonIcon: String?
        var showClock: Bool?
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

    var isPixelated: Bool { icon.renderStyle == "pixelated" }
    var isVertical: Bool { dock.orientation == "vertical" }
    var isFullWidth: Bool { dock.fullWidth == true }
    var hasStartButton: Bool { dock.startButton == true }
    var hasClock: Bool { dock.showClock == true }
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
