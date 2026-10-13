import Foundation
import ScreenSaver

enum FlowerBoxShape: Int, CaseIterable {
    case cube
    case tetrahedron
    case pyramid
    case cylinder
    case spring

    var title: String {
        switch self {
        case .cube: return "Cube"
        case .tetrahedron: return "Tetrahedron"
        case .pyramid: return "Pyramid"
        case .cylinder: return "Cylinder"
        case .spring: return "Spring"
        }
    }
}

struct FlowerBoxSettings: Equatable {
    var shape: FlowerBoxShape = .cube
    /// The object's size as a share of the screen height.
    var size = 0.55
    /// Multiplies how fast the object moves, spins, morphs and changes colour.
    var speed = 1.0
    var spins = true
    var blooms = true
    var cyclesColors = true

    static let sizeRange = 0.2...0.8
    static let speedRange = 0.25...2.5

    /// Settings are stored per bundle identifier, which project.yml derives from BUNDLE_ID_PREFIX.
    private static let moduleName = Bundle(for: FlowerBoxSaverView.self).bundleIdentifier ?? "RetroFlowerBox"

    private enum Key {
        static let shape = "shape"
        static let size = "size"
        static let speed = "speed"
        static let spins = "spins"
        static let blooms = "blooms"
        static let cyclesColors = "cyclesColors"
    }

    private static var defaults: UserDefaults? {
        ScreenSaverDefaults(forModuleWithName: moduleName)
    }

    static func load() -> FlowerBoxSettings {
        var settings = FlowerBoxSettings()
        guard let defaults else { return settings }
        if let raw = defaults.object(forKey: Key.shape) as? Int, let shape = FlowerBoxShape(rawValue: raw) {
            settings.shape = shape
        }
        if let size = defaults.object(forKey: Key.size) as? Double {
            settings.size = size.clamped(to: sizeRange)
        }
        if let speed = defaults.object(forKey: Key.speed) as? Double {
            settings.speed = speed.clamped(to: speedRange)
        }
        if let spins = defaults.object(forKey: Key.spins) as? Bool {
            settings.spins = spins
        }
        if let blooms = defaults.object(forKey: Key.blooms) as? Bool {
            settings.blooms = blooms
        }
        if let cyclesColors = defaults.object(forKey: Key.cyclesColors) as? Bool {
            settings.cyclesColors = cyclesColors
        }
        return settings
    }

    func save() {
        guard let defaults = Self.defaults else { return }
        defaults.set(shape.rawValue, forKey: Key.shape)
        defaults.set(size, forKey: Key.size)
        defaults.set(speed, forKey: Key.speed)
        defaults.set(spins, forKey: Key.spins)
        defaults.set(blooms, forKey: Key.blooms)
        defaults.set(cyclesColors, forKey: Key.cyclesColors)
        defaults.synchronize()
    }
}
