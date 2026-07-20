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

    /// Resolve a theme-relative resource path, confined to `base` (inside the bundle). Returns nil
    /// if the resolved path escapes the bundle via `../` or a symlink, or does not exist. RetroMac
    /// is unsandboxed and imports untrusted themes, so a theme must never reference files outside
    /// its own directory (arbitrary-file-as-icon/wallpaper). `internal` so tests can exercise it.
    static func confinedResource(_ name: String?, under base: URL) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        let root = base.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = base.appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }
    /// Confined lookup in the theme's `icons/` directory.
    func iconResource(_ name: String?) -> URL? { Self.confinedResource(name, under: iconsDirectory) }
    /// Confined lookup at the theme bundle root.
    func rootResource(_ name: String?) -> URL? { Self.confinedResource(name, under: url) }

    /// URL to the theme's preview image — prefers the compact preview.jpg, falls back to preview.png.
    var previewImageURL: URL? {
        for name in ["preview.jpg", "preview.png"] {
            let u = url.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Icon for the app's Dock icon in Dock Mode. Only an explicit per-theme `dock.appIcon`
    /// overrides it; otherwise nil → keep the default RetroMac app icon (theming comes later).
    func dockIconURL() -> URL? {
        return iconResource(config.dock.appIcon)
    }

    /// Small square icon representing the theme (for the launcher's theme strip). Prefers
    /// `dock.appIcon`, then a bundled `appIcon.png` / `icon.png`. Nil → caller shows a
    /// placeholder (per-theme icons are supplied later).
    func themeIconURL() -> URL? {
        if let u = iconResource(config.dock.appIcon) { return u }
        for name in ["appIcon.png", "icon.png"] {
            if let u = rootResource(name) { return u }
        }
        return nil
    }

    func iconURL(for bundleID: String) -> URL? {
        return iconResource(config.iconMappings[bundleID])
    }

    func fallbackIconURL() -> URL? {
        return iconResource(config.fallbackIcon)
    }

    func startButtonIconURL() -> URL? {
        return iconResource(config.dock.startButtonIcon)
    }

    func startButtonImageURL() -> URL? {
        return iconResource(config.dock.startButtonImage)
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
        return rootResource(config.wallpaper)
    }

    /// Returns all available wallpaper options for this theme
    func wallpaperOptions() -> [(name: String, url: URL)] {
        var options: [(name: String, url: URL)] = []

        // Add wallpapers from the wallpapers array
        if let wallpapers = config.wallpapers {
            for wp in wallpapers {
                if let wpURL = rootResource(wp.file) {
                    options.append((name: wp.name, url: wpURL))
                }
            }
        }

        // If no wallpapers array, use the single wallpaper field
        if options.isEmpty, let filename = config.wallpaper {
            if let wpURL = rootResource(filename) {
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
        guard let previewURL = previewImageURL else { return nil }
        return NSImage(contentsOf: previewURL)
    }

    func backgroundImage() -> NSImage? {
        guard let bgURL = rootResource(config.dock.backgroundImage) else { return nil }
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
