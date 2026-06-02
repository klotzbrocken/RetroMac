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
    private let wallpaperBackupKey = "savedWallpaperBackup"
    private var savedWallpapers: [String: URL] = [:]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        userThemesDir = appSupport.appendingPathComponent("RetroMac/DockThemes")
        try? FileManager.default.createDirectory(at: userThemesDir, withIntermediateDirectories: true)
        iconOverrides = defaults.dictionary(forKey: overridesKey) as? [String: [String: String]] ?? [:]

        // Restore wallpaper backup from UserDefaults (crash-safe)
        if let dict = defaults.dictionary(forKey: wallpaperBackupKey) as? [String: String] {
            savedWallpapers = dict.compactMapValues { URL(string: $0) }
            if !savedWallpapers.isEmpty {
                print("[Theme] Restored wallpaper backup: \(savedWallpapers.count) screens")
            }
        }

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

    func clearActiveTheme() {
        activeTheme = nil
        iconCache.removeAllObjects()
        NotificationCenter.default.post(name: .dockThemeChanged, object: nil)
        print("[Theme] Active theme: none (disabled)")
    }

    func setActiveTheme(name: String) {
        AppSettings.shared.dockTheme = name
        activeTheme = availableThemes.first(where: { $0.config.name == name })
        iconCache.removeAllObjects()
        applyWallpaper()
        NotificationCenter.default.post(name: .dockThemeChanged, object: nil)
        print("[Theme] Active theme: \(name)")

        // Auto-apply system icons if enabled
        if AppSettings.shared.applySystemIcons {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.applyIconsToSystem()
            }
        }
    }

    func applyWallpaper() {
        guard let theme = activeTheme else {
            restoreWallpapers()
            return
        }
        // Highest priority: a custom wallpaper picked via "Browse…" (absolute path)
        let wpURL: URL
        if let customPath = AppSettings.shared.themeCustomWallpaper[theme.name],
           FileManager.default.fileExists(atPath: customPath) {
            wpURL = URL(fileURLWithPath: customPath)
        } else if let overrideFile = AppSettings.shared.themeWallpaperOverrides[theme.name] {
            let overrideURL = theme.url.appendingPathComponent(overrideFile)
            if FileManager.default.fileExists(atPath: overrideURL.path) {
                wpURL = overrideURL
            } else if let fallback = theme.wallpaperURL() {
                wpURL = fallback
            } else {
                restoreWallpapers()
                return
            }
        } else if let defaultURL = theme.wallpaperURL() {
            wpURL = defaultURL
        } else {
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
        persistWallpaperBackup()
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
        persistWallpaperBackup()
        print("[Theme] Wallpapers restored")
    }

    private func persistWallpaperBackup() {
        if savedWallpapers.isEmpty {
            defaults.removeObject(forKey: wallpaperBackupKey)
        } else {
            let dict = savedWallpapers.mapValues { $0.absoluteString }
            defaults.set(dict, forKey: wallpaperBackupKey)
        }
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
                // Mapped/custom artwork is shown crisp (hi-res) — only un-mapped system
                // apps get auto-pixelated (below) so they blend into a pixel theme.
                return img
            }
        }

        // Only use fallback if the theme intended to have an icon for this app
        // (mapping exists but file is missing). If no mapping exists, fall through to system icon.
        if let theme = activeTheme,
           theme.config.iconMappings[bundleID] != nil,
           let fallbackURL = theme.fallbackIconURL() {
            if let img = NSImage(contentsOf: fallbackURL) {
                img.size = NSSize(width: size, height: size)
                return img
            }
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: size, height: size)
            // Pixel themes: auto-pixelate un-mapped apps' real icons so the whole dock
            // reads as one consistent pixel-art set without needing per-app artwork.
            if activeTheme?.config.isPixelated == true {
                return pixelated(icon, to: size)
            }
            return icon
        }

        let fallback = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: size, height: size))
        fallback.size = NSSize(width: size, height: size)
        return fallback
    }

    /// Pixelate `image` only when the active theme is pixelated. For icons loaded
    /// outside `loadIcon` (e.g. the trash icon) so they match the rest of the dock.
    func pixelatedIfNeeded(_ image: NSImage, size: CGFloat) -> NSImage {
        guard activeTheme?.config.isPixelated == true else { return image }
        return pixelated(image, to: size)
    }

    /// Downsample an icon to a small grid, then nearest-neighbour upscale → chunky
    /// pixel-art look. Used for un-mapped apps in pixelated themes.
    private func pixelated(_ image: NSImage, to size: CGFloat) -> NSImage {
        let blocks = 24
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: blocks, pixelsHigh: blocks,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            image.size = NSSize(width: size, height: size)
            return image
        }
        rep.size = NSSize(width: blocks, height: blocks)
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high   // smooth downscale into the grid
            image.draw(in: NSRect(x: 0, y: 0, width: blocks, height: blocks),
                       from: .zero, operation: .copy, fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: NSSize(width: size, height: size))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none   // nearest upscale → blocky
        rep.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                 from: NSRect(x: 0, y: 0, width: blocks, height: blocks),
                 operation: .copy, fraction: 1.0, respectFlipped: true,
                 hints: [.interpolation: NSImageInterpolation.none])
        out.unlockFocus()
        return out
    }

    /// Returns the real system icon for a bundle ID (no theme icons, no fallback).
    /// Only custom user overrides are applied.
    func systemIcon(for bundleID: String, size: CGFloat) -> NSImage {
        // Check custom override first (user explicitly set this)
        if let themeName = activeTheme?.name,
           let customPath = iconOverrides[themeName]?[bundleID] {
            if let img = NSImage(contentsOfFile: customPath) {
                img.size = NSSize(width: size, height: size)
                return img
            }
        }

        // Use the real app icon from the system
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

    // MARK: - Apply Theme Icons to System

    /// Apply the current theme's icons to actual apps on disk via NSWorkspace.setIcon
    func applyIconsToSystem() {
        guard let theme = activeTheme else { return }
        let apps = AppManager.shared.apps
        var applied = 0

        for app in apps {
            let bid = app.bundleID
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { continue }

            // Load the icon this theme would display
            let img = loadIcon(for: bid, size: 512)

            // Check if we have a themed icon (not just the system icon)
            let hasThemeIcon = iconOverrides[theme.name]?[bid] != nil
                || theme.iconURL(for: bid) != nil

            if hasThemeIcon {
                if NSWorkspace.shared.setIcon(img, forFile: appURL.path, options: []) {
                    applied += 1
                }
            }
        }
        print("[Theme] Applied \(applied) icons to system apps")
    }

    /// Revert all system app icons to their originals
    func revertSystemIcons() {
        let apps = AppManager.shared.apps
        var reverted = 0

        for app in apps {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { continue }
            if NSWorkspace.shared.setIcon(nil, forFile: appURL.path, options: []) {
                reverted += 1
            }
        }
        print("[Theme] Reverted \(reverted) system app icons")
    }
}
