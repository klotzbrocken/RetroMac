import AppKit

/// Persists user customizations to Program Manager groups (added shortcuts, icon
/// overrides, free-drag positions, deletions) per theme+group in UserDefaults.
enum ProgramManagerStore {
    struct GroupCustom: Codable {
        var added: [DockThemeConfig.DesktopIconEntry] = []
        var iconOverrides: [String: String] = [:]   // item name → absolute icon path
        var positions: [String: [CGFloat]] = [:]     // item name → [x, y] in client coords
        var deleted: [String] = []                    // item names removed
    }

    private static func key(_ theme: String, _ group: String) -> String {
        "pmCustom.\(theme).\(group)"
    }

    static func load(theme: String, group: String) -> GroupCustom {
        guard let data = UserDefaults.standard.data(forKey: key(theme, group)),
              let c = try? JSONDecoder().decode(GroupCustom.self, from: data) else { return GroupCustom() }
        return c
    }

    static func save(_ c: GroupCustom, theme: String, group: String) {
        if let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: key(theme, group))
        }
    }
}
