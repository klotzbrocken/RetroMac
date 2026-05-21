import AppKit

final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var availableThemes: [ThemeBundle] = []
    private(set) var activeTheme: ThemeBundle?
    private let iconCache = NSCache<NSString, NSImage>()
    private var iconOverrides: [String: [String: String]] = [:]

    private let userThemesDir: URL
    private let defaults = UserDefaults.standard
    private let overridesKey = "dockThemeIconOverrides"
    private var savedWallpapers: [String: URL] = [:]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        userThemesDir = appSupport.appendingPathComponent("RetroMac/DockThemes")
        try? FileManager.default.createDirectory(at: userThemesDir, withIntermediateDirectories: true)
        iconOverrides = defaults.dictionary(forKey: overridesKey) as? [String: [String: String]] ?? [:]
        reload()
    }

    var userThemesDirectory: URL { userThemesDir }

    func reload(selectTheme: String? = nil) {
        var themes: [ThemeBundle] = []

        if let builtinURL = Bundle.main.resourceURL?.appendingPathComponent("Themes") {
            themes += loadThemes(from: builtinURL, builtIn: true)
        }

        themes += loadThemes(from: userThemesDir, builtIn: false)

        availableThemes = themes
        print("[Theme] Found \(themes.count) themes: \(themes.map { $0.name }.joined(separator: ", "))")

        let activeID = selectTheme ?? AppSettings.shared.dockTheme
        activeTheme = themes.first(where: { $0.config.name == activeID })
            ?? themes.first(where: { $0.config.name == "Mountain Lion" })
            ?? themes.first
        print("[Theme] Active: \(activeTheme?.name ?? "nil")")
    }

    private func loadThemes(from directory: URL, builtIn: Bool) -> [ThemeBundle] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "retromactheme" }
            .compactMap { url in
                do {
                    return try ThemeBundle(url: url, isBuiltIn: builtIn)
                } catch {
                    print("[Theme] Failed to load \(url.lastPathComponent): \(error)")
                    return nil
                }
            }
    }

    func setActiveTheme(name: String) {
        AppSettings.shared.dockTheme = name
        activeTheme = availableThemes.first(where: { $0.config.name == name })
        iconCache.removeAllObjects()
        applyWallpaper()
        NotificationCenter.default.post(name: .dockThemeChanged, object: nil)
        print("[Theme] Active theme: \(name)")
    }

    private func applyWallpaper() {
        guard let theme = activeTheme, let wpURL = theme.wallpaperURL() else {
            restoreWallpapers()
            return
        }
        let ws = NSWorkspace.shared
        for screen in NSScreen.screens {
            let screenKey = "\(screen.displayID)"
            if savedWallpapers[screenKey] == nil {
                if let current = ws.desktopImageURL(for: screen) {
                    savedWallpapers[screenKey] = current
                }
            }
            try? ws.setDesktopImageURL(wpURL, for: screen, options: [:])
        }
        print("[Theme] Wallpaper set: \(wpURL.lastPathComponent)")
    }

    func restoreWallpapers() {
        guard !savedWallpapers.isEmpty else { return }
        let ws = NSWorkspace.shared
        for screen in NSScreen.screens {
            let screenKey = "\(screen.displayID)"
            if let original = savedWallpapers[screenKey] {
                try? ws.setDesktopImageURL(original, for: screen, options: [:])
            }
        }
        savedWallpapers.removeAll()
        print("[Theme] Wallpapers restored")
    }

    func icon(for bundleID: String, size: CGFloat) -> NSImage {
        let cacheKey = "\(activeTheme?.name ?? "default")_\(bundleID)_\(Int(size))" as NSString
        if let cached = iconCache.object(forKey: cacheKey) {
            return cached
        }

        let image = loadIcon(for: bundleID, size: size)
        iconCache.setObject(image, forKey: cacheKey)
        return image
    }

    private func loadIcon(for bundleID: String, size: CGFloat) -> NSImage {
        if let themeName = activeTheme?.name,
           let customPath = iconOverrides[themeName]?[bundleID] {
            if let img = NSImage(contentsOfFile: customPath) {
                img.size = NSSize(width: size, height: size)
                return img
            }
        }

        if let theme = activeTheme, let iconURL = theme.iconURL(for: bundleID) {
            if let img = NSImage(contentsOf: iconURL) {
                img.size = NSSize(width: size, height: size)
                return img
            }
        }

        if let theme = activeTheme, let fallbackURL = theme.fallbackIconURL() {
            if let img = NSImage(contentsOf: fallbackURL) {
                img.size = NSSize(width: size, height: size)
                return img
            }
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: size, height: size)
            return icon
        }

        let fallback = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: size, height: size))
        fallback.size = NSSize(width: size, height: size)
        return fallback
    }

    func clearCache() {
        iconCache.removeAllObjects()
    }

    // MARK: - Per-Theme Icon Overrides

    func customIconPath(for bundleID: String, theme: String? = nil) -> String? {
        let name = theme ?? activeTheme?.name ?? ""
        return iconOverrides[name]?[bundleID]
    }

    func setCustomIcon(for bundleID: String, path: String?) {
        guard let themeName = activeTheme?.name else { return }
        if iconOverrides[themeName] == nil {
            iconOverrides[themeName] = [:]
        }
        iconOverrides[themeName]?[bundleID] = path
        defaults.set(iconOverrides, forKey: overridesKey)
        iconCache.removeAllObjects()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }

    func hasOverrides(for theme: String? = nil) -> Bool {
        let name = theme ?? activeTheme?.name ?? ""
        guard let overrides = iconOverrides[name] else { return false }
        return !overrides.isEmpty
    }

    func saveExistingTheme() throws {
        guard let theme = activeTheme, !theme.isBuiltIn else {
            print("[Theme] Cannot save: no active user theme")
            return
        }
        guard let overrides = iconOverrides[theme.name], !overrides.isEmpty else {
            print("[Theme] No overrides to save for \(theme.name)")
            return
        }

        let fm = FileManager.default
        let iconsDir = theme.iconsDirectory
        try? fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)

        var updatedConfig = theme.config
        for (bundleID, sourcePath) in overrides {
            let ext = (sourcePath as NSString).pathExtension
            let iconName = bundleID.replacingOccurrences(of: ".", with: "_") + "." + (ext.isEmpty ? "png" : ext)
            let destPath = iconsDir.appendingPathComponent(iconName)
            try? fm.removeItem(at: destPath)
            try fm.copyItem(atPath: sourcePath, toPath: destPath.path)
            updatedConfig.iconMappings[bundleID] = iconName
        }

        try theme.save(config: updatedConfig)
        iconOverrides.removeValue(forKey: theme.name)
        defaults.set(iconOverrides, forKey: overridesKey)
        iconCache.removeAllObjects()
        reload()
        print("[Theme] Saved overrides to existing theme: \(theme.name)")
    }

    var canSaveExistingTheme: Bool {
        guard let theme = activeTheme, !theme.isBuiltIn else { return false }
        return hasOverrides(for: theme.name)
    }

    func saveAsNewTheme(name: String) throws {
        guard let base = activeTheme else { return }
        let safeName = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let bundleName = "\(safeName).retromactheme"
        let destURL = userThemesDir.appendingPathComponent(bundleName)
        let fm = FileManager.default

        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: base.url, to: destURL)

        var newConfig = base.config
        newConfig.name = name

        let iconsDir = destURL.appendingPathComponent("icons")
        try? fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)

        if let overrides = iconOverrides[base.name] {
            for (bundleID, sourcePath) in overrides {
                let ext = (sourcePath as NSString).pathExtension
                let iconName = bundleID.replacingOccurrences(of: ".", with: "_") + "." + (ext.isEmpty ? "png" : ext)
                let destPath = iconsDir.appendingPathComponent(iconName)
                try? fm.removeItem(at: destPath)
                try fm.copyItem(atPath: sourcePath, toPath: destPath.path)
                newConfig.iconMappings[bundleID] = iconName
            }
        }

        let newBundle = try ThemeBundle(url: destURL, isBuiltIn: false)
        try newBundle.save(config: newConfig)

        iconOverrides.removeValue(forKey: base.name)
        defaults.set(iconOverrides, forKey: overridesKey)

        reload()
        AppSettings.shared.dockTheme = name
        print("[Theme] Saved new theme: \(name)")
    }

    func importTheme(from sourceURL: URL) throws {
        let destURL = userThemesDir.appendingPathComponent(sourceURL.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: sourceURL, to: destURL)
        reload()
        print("[Theme] Imported theme from \(sourceURL.lastPathComponent)")
    }

    func deleteTheme(_ theme: ThemeBundle) throws {
        guard !theme.isBuiltIn else {
            print("[Theme] Cannot delete built-in theme")
            return
        }
        try FileManager.default.removeItem(at: theme.url)
        reload()
        if activeTheme?.url == theme.url {
            if let first = availableThemes.first {
                setActiveTheme(name: first.name)
            }
        }
    }

    func duplicateTheme(_ theme: ThemeBundle, newName: String) throws -> ThemeBundle {
        let copy = try ThemeBundle.create(name: newName, basedOn: theme, at: userThemesDir)
        reload()
        return copy
    }
}
