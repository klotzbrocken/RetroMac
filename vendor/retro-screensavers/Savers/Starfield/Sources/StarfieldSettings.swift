import Foundation
import ScreenSaver

struct StarfieldSettings: Equatable {
    /// Multiplies how fast you fly through the stars.
    var warpSpeed = 1.0
    /// How many stars there are.
    var density = 1200

    static let warpSpeedRange = 0.2...4.0
    static let densityRange = 200...4000

    /// Settings are stored per bundle identifier, which project.yml derives from BUNDLE_ID_PREFIX.
    private static let moduleName = Bundle(for: StarfieldSaverView.self).bundleIdentifier ?? "RetroStarfield"

    private enum Key {
        static let warpSpeed = "warpSpeed"
        static let density = "density"
    }

    private static var defaults: UserDefaults? {
        ScreenSaverDefaults(forModuleWithName: moduleName)
    }

    static func load() -> StarfieldSettings {
        var settings = StarfieldSettings()
        guard let defaults else { return settings }
        if let warpSpeed = defaults.object(forKey: Key.warpSpeed) as? Double {
            settings.warpSpeed = warpSpeed.clamped(to: warpSpeedRange)
        }
        if let density = defaults.object(forKey: Key.density) as? Int {
            settings.density = density.clamped(to: densityRange)
        }
        return settings
    }

    func save() {
        guard let defaults = Self.defaults else { return }
        defaults.set(warpSpeed, forKey: Key.warpSpeed)
        defaults.set(density, forKey: Key.density)
        defaults.synchronize()
    }
}
