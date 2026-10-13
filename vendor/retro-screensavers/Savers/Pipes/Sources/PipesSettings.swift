import Foundation
import ScreenSaver

enum JointStyle: Int, CaseIterable {
    case elbow
    case ball
    case mixed

    var title: String {
        switch self {
        case .elbow: return "Elbows"
        case .ball: return "Ball joints"
        case .mixed: return "Mixed"
        }
    }
}

/// The original's "Surface style": solid colours or a texture wrapped around the pipes.
enum Surface: Int, CaseIterable {
    case solid
    case marble
    case wood
    case granite
    case mixedTextures

    var title: String {
        switch self {
        case .solid: return "Solid colors"
        case .marble: return "Marble"
        case .wood: return "Wood"
        case .granite: return "Granite"
        case .mixedTextures: return "Mixed textures"
        }
    }

    /// The textures pipes are drawn with, one picked per pipe; empty for solid colours.
    var textures: [RetroTexture] {
        switch self {
        case .solid: return []
        case .marble: return [.marble]
        case .wood: return [.wood]
        case .granite: return [.granite]
        case .mixedTextures: return RetroTexture.allCases
        }
    }
}

struct PipesSettings: Equatable {
    var jointStyle: JointStyle = .mixed
    var surface: Surface = .solid
    /// How many pipes grow at the same time.
    var pipeCount = 3
    /// Growth speed in grid cells per second.
    var speed = 10.0

    static let pipeCountRange = 1...6
    static let speedRange = 3.0...30.0

    /// Settings are stored per bundle identifier, which project.yml derives from BUNDLE_ID_PREFIX.
    private static let moduleName = Bundle(for: PipesSaverView.self).bundleIdentifier ?? "RetroPipes"

    private enum Key {
        static let jointStyle = "jointStyle"
        static let surface = "surface"
        static let pipeCount = "pipeCount"
        static let speed = "speed"
    }

    private static var defaults: UserDefaults? {
        ScreenSaverDefaults(forModuleWithName: moduleName)
    }

    static func load() -> PipesSettings {
        var settings = PipesSettings()
        guard let defaults else { return settings }
        if let raw = defaults.object(forKey: Key.jointStyle) as? Int, let style = JointStyle(rawValue: raw) {
            settings.jointStyle = style
        }
        if let raw = defaults.object(forKey: Key.surface) as? Int, let surface = Surface(rawValue: raw) {
            settings.surface = surface
        }
        if let count = defaults.object(forKey: Key.pipeCount) as? Int {
            settings.pipeCount = count.clamped(to: pipeCountRange)
        }
        if let speed = defaults.object(forKey: Key.speed) as? Double {
            settings.speed = speed.clamped(to: speedRange)
        }
        return settings
    }

    func save() {
        guard let defaults = Self.defaults else { return }
        defaults.set(jointStyle.rawValue, forKey: Key.jointStyle)
        defaults.set(surface.rawValue, forKey: Key.surface)
        defaults.set(pipeCount, forKey: Key.pipeCount)
        defaults.set(speed, forKey: Key.speed)
        defaults.synchronize()
    }
}
