import AppKit

final class ThemeBundle {
    let url: URL
    let baseConfig: DockThemeConfig
    let isBuiltIn: Bool
    /// Optional runtime variant of the config (e.g. Mac OS 6's "real dock instead of
    /// Control Strip" option). Set by ThemeManager on activation; nil = as authored.
    private var configOverride: DockThemeConfig?

    var config: DockThemeConfig { configOverride ?? baseConfig }
    func setConfigOverride(_ cfg: DockThemeConfig?) { configOverride = cfg }

    init(url: URL, isBuiltIn: Bool = false) throws {
        self.url = url
        self.isBuiltIn = isBuiltIn

        let jsonURL = url.appendingPathComponent("theme.json")
        let data = try Data(contentsOf: jsonURL)
        self.baseConfig = try JSONDecoder().decode(DockThemeConfig.self, from: data)
    }

    var name: String { config.name }
    var iconsDirectory: URL { url.appendingPathComponent("icons") }

    /// URL to the theme's preview image (preview.png), if it exists.
    var previewImageURL: URL? {
        let previewURL = url.appendingPathComponent("preview.png")
        return FileManager.default.fileExists(atPath: previewURL.path) ? previewURL : nil
    }

    /// Icon for the app's Dock icon in Dock Mode. Only an explicit per-theme `dock.appIcon`
    /// overrides it; otherwise nil → keep the default RetroMac app icon (theming comes later).
    func dockIconURL() -> URL? {
        if let filename = config.dock.appIcon {
            let u = iconsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Small square icon representing the theme (for the launcher's theme strip). Prefers
    /// `dock.appIcon`, then a bundled `appIcon.png` / `icon.png`. Nil → caller shows a
    /// placeholder (per-theme icons are supplied later).
    func themeIconURL() -> URL? {
        if let filename = config.dock.appIcon {
            let u = iconsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        for name in ["appIcon.png", "icon.png"] {
            let u = url.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

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

    func startButtonImageURL() -> URL? {
        guard let filename = config.dock.startButtonImage else { return nil }
        let imgURL = iconsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: imgURL.path) { return imgURL }
        return nil
    }

    /// Returns all icon image files available in this theme's icons directory
    func availableIcons() -> [(name: String, url: URL)] {
        let fm = FileManager.default
        let dir = iconsDirectory
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "icns", "tiff", "tif"]
        return contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { (name: $0.deletingPathExtension().lastPathComponent, url: $0) }
    }

    func wallpaperURL() -> URL? {
        guard let filename = config.wallpaper else { return nil }
        let wpURL = url.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: wpURL.path) { return wpURL }
        return nil
    }

    /// Returns all available wallpaper options for this theme
    func wallpaperOptions() -> [(name: String, url: URL)] {
        var options: [(name: String, url: URL)] = []

        // Add wallpapers from the wallpapers array
        if let wallpapers = config.wallpapers {
            for wp in wallpapers {
                let wpURL = url.appendingPathComponent(wp.file)
                if FileManager.default.fileExists(atPath: wpURL.path) {
                    options.append((name: wp.name, url: wpURL))
                }
            }
        }

        // If no wallpapers array, use the single wallpaper field
        if options.isEmpty, let filename = config.wallpaper {
            let wpURL = url.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: wpURL.path) {
                let name = (filename as NSString).deletingPathExtension
                    .replacingOccurrences(of: "wallpaper-", with: "")
                    .replacingOccurrences(of: "wallpaper", with: "Default")
                    .capitalized
                options.append((name: name, url: wpURL))
            }
        }

        return options
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
