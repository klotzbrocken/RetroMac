import AppKit

/// Persists user customizations to a theme's desktop icons (free-drag positions, added
/// shortcuts, icon overrides, removals) per theme in UserDefaults.
enum DesktopStore {
    struct ThemeCustom: Codable {
        var added: [DockThemeConfig.DesktopIconEntry] = []
        var iconOverrides: [String: String] = [:]   // item name → absolute icon path
        var positions: [String: [CGFloat]] = [:]     // item name → [x, y] (panel coords)
        var removed: [String] = []                    // item names hidden
    }

    private static func key(_ theme: String) -> String { "desktopCustom.\(theme)" }

    static func load(theme: String) -> ThemeCustom {
        guard let data = UserDefaults.standard.data(forKey: key(theme)),
              let c = try? JSONDecoder().decode(ThemeCustom.self, from: data) else { return ThemeCustom() }
        return c
    }

    static func save(_ c: ThemeCustom, theme: String) {
        if let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: key(theme))
        }
    }
}
