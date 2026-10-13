import AppKit
import ScreenSaver

enum TextContent: Int, CaseIterable {
    case text
    case time

    var title: String {
        switch self {
        case .text: return "Text"
        case .time: return "Time"
        }
    }
}

enum RotationStyle: Int, CaseIterable {
    case none
    case spin
    case seeSaw
    case wobble
    case tumble

    var title: String {
        switch self {
        case .none: return "None"
        case .spin: return "Spin"
        case .seeSaw: return "See-Saw"
        case .wobble: return "Wobble"
        case .tumble: return "Tumble"
        }
    }
}

enum TextSurface: Int, CaseIterable {
    case solid
    case chrome
    case marble
    case wood
    case granite

    var title: String {
        switch self {
        case .solid: return "Solid color"
        case .chrome: return "Chrome"
        case .marble: return "Marble"
        case .wood: return "Wood"
        case .granite: return "Granite"
        }
    }

    var texture: RetroTexture? {
        switch self {
        case .marble: return .marble
        case .wood: return .wood
        case .granite: return .granite
        case .solid, .chrome: return nil
        }
    }
}

struct TextFont: Equatable {
    let title: String
    let postScriptName: String

    /// Classic fonts that ship with macOS.
    static let all = [
        TextFont(title: "Arial Black", postScriptName: "Arial-Black"),
        TextFont(title: "Impact", postScriptName: "Impact"),
        TextFont(title: "Helvetica Neue", postScriptName: "HelveticaNeue-Bold"),
        TextFont(title: "Futura", postScriptName: "Futura-Bold"),
        TextFont(title: "Georgia", postScriptName: "Georgia-Bold"),
        TextFont(title: "Times New Roman", postScriptName: "TimesNewRomanPS-BoldMT"),
        TextFont(title: "Courier New", postScriptName: "CourierNewPS-BoldMT"),
        TextFont(title: "American Typewriter", postScriptName: "AmericanTypewriter-Bold"),
        TextFont(title: "Copperplate", postScriptName: "Copperplate-Bold"),
        TextFont(title: "Comic Sans MS", postScriptName: "ComicSansMS-Bold"),
        TextFont(title: "Chalkduster", postScriptName: "Chalkduster"),
    ]

    func font(size: CGFloat) -> NSFont {
        NSFont(name: postScriptName, size: size) ?? .boldSystemFont(ofSize: size)
    }
}

struct TextColor: Equatable {
    let title: String
    let color: NSColor

    static let all = [
        TextColor(title: "Red", color: NSColor(srgbRed: 0.86, green: 0.1, blue: 0.08, alpha: 1)),
        TextColor(title: "Orange", color: NSColor(srgbRed: 0.96, green: 0.48, blue: 0.08, alpha: 1)),
        TextColor(title: "Gold", color: NSColor(srgbRed: 0.95, green: 0.72, blue: 0.15, alpha: 1)),
        TextColor(title: "Green", color: NSColor(srgbRed: 0.1, green: 0.72, blue: 0.12, alpha: 1)),
        TextColor(title: "Teal", color: NSColor(srgbRed: 0.08, green: 0.66, blue: 0.7, alpha: 1)),
        TextColor(title: "Blue", color: NSColor(srgbRed: 0.12, green: 0.32, blue: 0.95, alpha: 1)),
        TextColor(title: "Purple", color: NSColor(srgbRed: 0.5, green: 0.18, blue: 0.85, alpha: 1)),
        TextColor(title: "Pink", color: NSColor(srgbRed: 0.92, green: 0.3, blue: 0.62, alpha: 1)),
        TextColor(title: "White", color: NSColor(white: 0.9, alpha: 1)),
    ]
}

struct Text3DSettings: Equatable {
    var content: TextContent = .text
    var text = "Retro 3D Text"
    var fontIndex = 0
    var rotation: RotationStyle = .wobble
    /// Multiplies the rotation speed.
    var speed = 1.0
    /// How much of the screen width the text spans.
    var size = 0.75
    var surface: TextSurface = .chrome
    /// Used by the solid colour surface.
    var colorIndex = 5
    var showsHighlights = true

    static let speedRange = 0.25...2.5
    static let sizeRange = 0.3...1.0
    static let maximumTextLength = 40

    var font: TextFont { TextFont.all[fontIndex.clamped(to: 0...(TextFont.all.count - 1))] }
    var color: TextColor { TextColor.all[colorIndex.clamped(to: 0...(TextColor.all.count - 1))] }

    /// Settings are stored per bundle identifier, which project.yml derives from BUNDLE_ID_PREFIX.
    private static let moduleName = Bundle(for: Text3DSaverView.self).bundleIdentifier ?? "RetroText3D"

    private enum Key {
        static let content = "content"
        static let text = "text"
        static let font = "font"
        static let rotation = "rotation"
        static let speed = "speed"
        static let size = "size"
        static let surface = "surface"
        static let color = "color"
        static let showsHighlights = "showsHighlights"
    }

    private static var defaults: UserDefaults? {
        ScreenSaverDefaults(forModuleWithName: moduleName)
    }

    static func load() -> Text3DSettings {
        var settings = Text3DSettings()
        guard let defaults else { return settings }
        if let raw = defaults.object(forKey: Key.content) as? Int, let content = TextContent(rawValue: raw) {
            settings.content = content
        }
        if let text = defaults.string(forKey: Key.text), !text.isEmpty {
            settings.text = String(text.prefix(maximumTextLength))
        }
        if let index = defaults.object(forKey: Key.font) as? Int {
            settings.fontIndex = index.clamped(to: 0...(TextFont.all.count - 1))
        }
        if let raw = defaults.object(forKey: Key.rotation) as? Int, let rotation = RotationStyle(rawValue: raw) {
            settings.rotation = rotation
        }
        if let speed = defaults.object(forKey: Key.speed) as? Double {
            settings.speed = speed.clamped(to: speedRange)
        }
        if let size = defaults.object(forKey: Key.size) as? Double {
            settings.size = size.clamped(to: sizeRange)
        }
        if let raw = defaults.object(forKey: Key.surface) as? Int, let surface = TextSurface(rawValue: raw) {
            settings.surface = surface
        }
        if let index = defaults.object(forKey: Key.color) as? Int {
            settings.colorIndex = index.clamped(to: 0...(TextColor.all.count - 1))
        }
        if let showsHighlights = defaults.object(forKey: Key.showsHighlights) as? Bool {
            settings.showsHighlights = showsHighlights
        }
        return settings
    }

    func save() {
        guard let defaults = Self.defaults else { return }
        defaults.set(content.rawValue, forKey: Key.content)
        defaults.set(text, forKey: Key.text)
        defaults.set(fontIndex, forKey: Key.font)
        defaults.set(rotation.rawValue, forKey: Key.rotation)
        defaults.set(speed, forKey: Key.speed)
        defaults.set(size, forKey: Key.size)
        defaults.set(surface.rawValue, forKey: Key.surface)
        defaults.set(colorIndex, forKey: Key.color)
        defaults.set(showsHighlights, forKey: Key.showsHighlights)
        defaults.synchronize()
    }
}
