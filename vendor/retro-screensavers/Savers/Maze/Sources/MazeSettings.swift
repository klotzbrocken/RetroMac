import Foundation
import ScreenSaver

enum MazeSize: Int, CaseIterable {
    case small
    case medium
    case large

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Cells along each side.
    var cells: Int {
        switch self {
        case .small: return 8
        case .medium: return 12
        case .large: return 16
        }
    }
}

struct MazeSettings: Equatable {
    var size: MazeSize = .medium
    /// Multiplies walking speed.
    var speed = 1.0
    var rats = 2
    /// Spinning grey shapes that flip the view upside down.
    var flippers = 4
    var showsMap = false

    static let speedRange = 0.5...2.5
    static let ratsRange = 0...6
    static let flippersRange = 0...10

    /// Settings are stored per bundle identifier, which project.yml derives from BUNDLE_ID_PREFIX.
    private static let moduleName = Bundle(for: MazeSaverView.self).bundleIdentifier ?? "RetroMaze"

    private enum Key {
        static let size = "size"
        static let speed = "speed"
        static let rats = "rats"
        static let flippers = "flippers"
        static let showsMap = "showsMap"
    }

    private static var defaults: UserDefaults? {
        ScreenSaverDefaults(forModuleWithName: moduleName)
    }

    static func load() -> MazeSettings {
        var settings = MazeSettings()
        guard let defaults else { return settings }
        if let raw = defaults.object(forKey: Key.size) as? Int, let size = MazeSize(rawValue: raw) {
            settings.size = size
        }
        if let speed = defaults.object(forKey: Key.speed) as? Double {
            settings.speed = speed.clamped(to: speedRange)
        }
        if let rats = defaults.object(forKey: Key.rats) as? Int {
            settings.rats = rats.clamped(to: ratsRange)
        }
        if let flippers = defaults.object(forKey: Key.flippers) as? Int {
            settings.flippers = flippers.clamped(to: flippersRange)
        }
        if let showsMap = defaults.object(forKey: Key.showsMap) as? Bool {
            settings.showsMap = showsMap
        }
        return settings
    }

    func save() {
        guard let defaults = Self.defaults else { return }
        defaults.set(size.rawValue, forKey: Key.size)
        defaults.set(speed, forKey: Key.speed)
        defaults.set(rats, forKey: Key.rats)
        defaults.set(flippers, forKey: Key.flippers)
        defaults.set(showsMap, forKey: Key.showsMap)
        defaults.synchronize()
    }
}
