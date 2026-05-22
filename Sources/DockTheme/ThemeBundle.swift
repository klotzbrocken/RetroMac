import AppKit

final class ThemeBundle {
    let url: URL
    let config: DockThemeConfig
    let isBuiltIn: Bool

    init(url: URL, isBuiltIn: Bool = false) throws {
        self.url = url
        self.isBuiltIn = isBuiltIn

        let jsonURL = url.appendingPathComponent("theme.json")
        let data = try Data(contentsOf: jsonURL)
        self.config = try JSONDecoder().decode(DockThemeConfig.self, from: data)
    }

    var name: String { config.name }
    var iconsDirectory: URL { url.appendingPathComponent("icons") }

    func iconURL(for bundleID: String) -> URL? {
        guard let filename = config.iconMappings[bundleID] else { return nil }
        let iconURL = iconsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: iconURL.path) { return iconURL }
        return nil
    }

    func fallbackIconURL() -> URL? {
        guard let filename = config.fallbackIcon else { return nil }
        let iconURL = iconsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: iconURL.path) { return iconURL }
        return nil
    }

    func startButtonIconURL() -> URL? {
        guard let filename = config.dock.startButtonIcon else { return nil }
        let iconURL = iconsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: iconURL.path) { return iconURL }
        return nil
    }

    func wallpaperURL() -> URL? {
        guard let filename = config.wallpaper else { return nil }
        let wpURL = url.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: wpURL.path) { return wpURL }
        return nil
    }

    func previewImage() -> NSImage? {
        let previewURL = url.appendingPathComponent("preview.png")
        return NSImage(contentsOf: previewURL)
    }

    func backgroundImage() -> NSImage? {
        guard let bgName = config.dock.backgroundImage else { return nil }
        let bgURL = url.appendingPathComponent(bgName)
        return NSImage(contentsOf: bgURL)
    }

    func save(config: DockThemeConfig) throws {
        guard !isBuiltIn else {
            print("[Theme] Cannot save to built-in theme")
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let jsonURL = url.appendingPathComponent("theme.json")
        try data.write(to: jsonURL, options: .atomic)
    }

    static func create(name: String, basedOn source: ThemeBundle, at directory: URL) throws -> ThemeBundle {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let bundleName = "\(safeName).retromactheme"
        let destURL = directory.appendingPathComponent(bundleName)
        let fm = FileManager.default

        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: source.url, to: destURL)

        var newConfig = source.config
        newConfig.name = name
        let bundle = try ThemeBundle(url: destURL, isBuiltIn: false)
        try bundle.save(config: newConfig)
        return bundle
    }
}
