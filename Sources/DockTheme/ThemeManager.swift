import AppKit
import CoreImage
import CoreText

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

        let selector = selectTheme ?? AppSettings.shared.dockTheme
        if selector == "Mac OS 9.2" {
            // Former standalone Platinum theme — merged into Classic as a dock variant. Only the
            // side effect is applied here; the selector itself is remapped in `resolve`, and the
            // stored value is rewritten once by the id migration. reload() must stay WRITE-FREE
            // for dockTheme: its @Published sink calls reload() again, so writing here would make
            // every launch re-enter the whole theme switch (splash + window rebuild) twice.
            AppSettings.shared.macos9UseDock = true
        }
        activeTheme = Self.resolve(selector, in: themes)
            ?? Self.resolve("Maiks Favourite", in: themes)
            ?? Self.resolve("Mountain Lion", in: themes)
            ?? themes.first
        // reload() recreates every ThemeBundle from disk, which drops runtime config
        // overrides — re-apply them here (the dockTheme sink reloads on EVERY switch).
        applyDockVariants()
        registerThemeFonts()
        print("[Theme] Active: \(activeTheme?.name ?? "nil")")
    }

    /// Stored selectors from older releases that no longer match any theme's name. Kept in one
    /// place so both `resolve` and the id migration understand them identically.
    static let legacySelectorAliases: [String: String] = ["Mac OS 9.2": "Mac OS 9.2 Classic"]

    /// Resolve a stored selection to a theme. Manifest 2.0 stores a stable `id`; anything saved
    /// before that is a display name. Ids are matched FIRST so a theme cannot hijack another
    /// theme's selection by taking a name that happens to equal an id.
    static func resolve(_ selector: String, in themes: [ThemeBundle]) -> ThemeBundle? {
        let s = legacySelectorAliases[selector] ?? selector
        return themes.first(where: { $0.stableID == s })
            ?? themes.first(where: { $0.config.name == s })
    }

    /// Resolve against the currently loaded themes.
    func theme(for selector: String) -> ThemeBundle? { Self.resolve(selector, in: availableThemes) }

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

    /// Select a theme by display name (what the pickers hand us) or by stable id — both are
    /// resolved through `theme(for:)`. Whatever comes in, what gets STORED is the stable id, so a
    /// later rename of the theme cannot orphan the selection or its per-theme settings.
    func setActiveTheme(name: String, applyWallpaper applyWP: Bool = true) {
        let bundle = theme(for: name)
        let key = bundle?.stableID ?? name
        AppSettings.shared.dockTheme = key
        AppSettings.shared.loadIconScales(forTheme: key)   // each theme remembers its icon sizes
        activeTheme = bundle
        iconCache.removeAllObjects()
        registerThemeFonts()   // e.g. Chicago/Geneva for Mac OS 6 (process-scoped, idempotent)
        applyDockVariants()
        // "Dock only" mode skips the desktop wallpaper change (theme affects the dock only).
        if applyWP { applyWallpaper() } else { restoreWallpapers() }
        NotificationCenter.default.post(name: .dockThemeChanged, object: nil)
        print("[Theme] Active theme: \(name)")

        // Auto-apply system icons if enabled
        if AppSettings.shared.applySystemIcons {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.applyIconsToSystem()
            }
        }
    }

    /// Apple-OS family themes — shown as "Mac OS …".
    static func isMacOSTheme(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("mac os") || n == "mountain lion" || n == "snow leopard"
    }

    /// "Special" full-chrome themes that carry the crown marker — one consistent 👑
    /// across every OS family (Mac OS, Windows, BeOS Classic, Maiks Favourite).
    static func isCrowned(_ name: String) -> Bool {
        let n = name.lowercased()
        return isMacOSTheme(name)
            || n.contains("windows xp") || n.contains("windows 98") || n.contains("windows me")
            || (n.contains("beos") && n.contains("classic"))
            || n.contains("maiks favourite")
            || n.contains("nextstep")
    }

    /// User-facing theme name: crowned themes get a 👑 prefix; the Mac OS family also
    /// gets a full "Mac OS …" name. Internal names are unchanged (display only).
    static func displayName(for name: String) -> String {
        var s = name
        switch name {
        case "Mountain Lion":      s = "Mac OS Mountain Lion"
        case "Snow Leopard":       s = "Mac OS Snow Leopard"
        case "Mac OS 9.2 Classic": s = "Mac OS System 9"
        case "Mac OS 6 classic":   s = "Apple System 6"
        default: break
        }
        return isCrowned(name) ? "👑 " + s : s
    }

    /// Per-theme dock variants ("Dock instead of Control Strip" options).
    func applyDockVariants() {
        guard let t = activeTheme else { return }
        switch t.baseConfig.name {
        case "Mac OS 6 classic":      applyMacOS6DockVariant()
        case "Mac OS 9.2 Classic":    applyMacOS9DockVariant()
        case "BeOS":                  applyBeOSDockVariant()
        case "Windows 98":            applyWin98PlusVariant()
        default: break
        }
    }

    /// Windows 98 Plus! scheme: recolour the chrome + swap wallpaper/desktop icons via a runtime
    /// config override (cursors are handled by CursorThemeManager reading the same setting). The
    /// default scheme ("") clears the override → the built-in navy Windows 98 look.
    private func applyWin98PlusVariant() {
        guard let t = activeTheme, t.baseConfig.name == "Windows 98" else { return }
        guard let scheme = Win98Scheme.byID[AppSettings.shared.win98Scheme] else {
            t.setConfigOverride(nil); return
        }
        var c = t.baseConfig
        c.chromeColors = scheme.colors
        if let face = scheme.colors.face, !face.isEmpty { c.dock.backgroundColor = face }   // recolour the taskbar
        if let wp = scheme.wallpaper {
            c.wallpaper = wp
            c.wallpapers = [DockThemeConfig.WallpaperOption(name: scheme.display, file: wp)]
        }
        if var icons = c.desktopIcons {
            for i in icons.indices {
                switch icons[i].name {
                case "My Computer": if let x = scheme.iconComputer { icons[i].icon = x }
                case "Recycle Bin":
                    if let e = scheme.iconRecycleEmpty { icons[i].icon = e }
                    if let f = scheme.iconRecycleFull { icons[i].iconFull = f }
                default: break
                }
            }
            c.desktopIcons = icons
        }
        t.setConfigOverride(c)
    }

    /// BeOS option: use the regular RetroMac dock instead of the classic Deskbar panel
    /// (the merged-in former "BeOS Classic"). Off (default) keeps the Deskbar (base config).
    private func applyBeOSDockVariant() {
        guard let t = activeTheme, t.baseConfig.name == "BeOS" else { return }
        guard AppSettings.shared.beosUseDock else { t.setConfigOverride(nil); return }   // Deskbar (base)
        var c = t.baseConfig
        c.dock.dockStyle = nil               // regular bottom dock, not the Deskbar
        c.dock.height = 56
        c.dock.iconSize = 40
        c.dock.padding = 6
        c.dock.spacing = 6
        c.dock.cornerRadius = 0
        c.dock.orientation = "horizontal"
        c.dock.position = "bottom"
        c.dock.alignment = "left"
        c.dock.edgeOffset = 4
        c.dock.backgroundColor = "#D8D8D8FF"
        c.dock.backgroundGradientTop = nil
        c.dock.backgroundGradientBottom = nil
        c.dock.borderColor = "#404040FF"
        c.dock.borderWidth = 1
        c.dock.bevelTopColor = "#FFFFFFFF"
        c.dock.bevelBottomColor = "#808080FF"
        c.dock.bevelWidth = 1
        c.dock.shadowEnabled = false
        c.dock.magnification = false
        c.dock.showTrash = true
        c.dock.showGrip = true
        t.setConfigOverride(c)
    }

    /// Mac OS 9 Classic option: the Platinum dock of the former "Mac OS 9.2" theme
    /// (merged in) instead of the Control Strip.
    private func applyMacOS9DockVariant() {
        guard let t = activeTheme, t.baseConfig.name == "Mac OS 9.2 Classic" else { return }
        guard AppSettings.shared.macos9UseDock else { t.setConfigOverride(nil); return }
        var c = t.baseConfig
        c.dock.dockStyle = nil               // real dock, not the Control Strip
        c.dock.height = 52
        c.dock.iconSize = 32
        c.dock.padding = 10
        c.dock.spacing = 6
        c.dock.cornerRadius = 0
        c.dock.alignment = "left"
        c.dock.backgroundColor = "#CCCCCCFF"
        c.dock.backgroundGradientTop = nil
        c.dock.backgroundGradientBottom = nil
        c.dock.borderColor = "#000000FF"
        c.dock.borderWidth = 1
        c.dock.bevelTopColor = "#FFFFFFFF"
        c.dock.bevelBottomColor = "#888888FF"
        c.dock.bevelWidth = 2
        c.dock.shadowEnabled = false
        c.dock.shadowColor = "#00000000"
        c.dock.shadowRadius = 0
        c.dock.shelfStyle = nil
        c.dock.magnification = false
        c.icon.hoverScale = 1.08
        c.indicator.style = "square"
        c.indicator.color = "#000000"
        c.indicator.size = 4
        c.indicator.offset = 6
        t.setConfigOverride(c)
    }

    /// Mac OS 6 option: replace the Control Strip with a Mountain-Lion-style dock —
    /// same 3D glass shelf as Snow Leopard, but in desaturated grays; the theme's
    /// monochrome icon pipeline keeps every icon B/W.
    private func applyMacOS6DockVariant() {
        guard let t = activeTheme, t.baseConfig.name == "Mac OS 6 classic" else { return }
        guard AppSettings.shared.macos6UseDock else { t.setConfigOverride(nil); return }
        var c = t.baseConfig
        c.dock.dockStyle = nil               // normal dock, not the Control Strip
        // 2D Mountain-Lion dock layout, styled lo-fi System 6: solid light gray, hard
        // square corners, plain black border — no transparency, no gloss.
        c.dock.height = 68
        c.dock.iconSize = 52                 // unified base across all real-dock themes
        c.dock.padding = 14
        c.dock.spacing = 6
        c.dock.cornerRadius = 0
        c.dock.alignment = "center"
        c.dock.backgroundColor = "#DDDDDDFF"
        c.dock.backgroundGradientTop = nil
        c.dock.backgroundGradientBottom = nil
        c.dock.shelfLineColor = nil
        c.dock.borderColor = "#000000FF"
        c.dock.borderWidth = 1
        c.dock.shadowEnabled = false
        c.dock.shadowColor = "#00000000"
        c.dock.shadowRadius = 0
        c.dock.bevelTopColor = "#FFFFFFFF"
        c.dock.bevelBottomColor = "#888888FF"
        c.dock.bevelWidth = 1
        c.dock.shelfStyle = nil              // flat 2D panel
        c.dock.magnification = true
        c.dock.magnificationScale = 1.8
        c.dock.showTrash = true
        c.icon.renderStyle = "smooth"
        c.indicator.style = "dot"
        c.indicator.color = "#000000DD"      // black dot on the light panel
        c.indicator.size = 5
        c.indicator.offset = 4
        t.setConfigOverride(c)
    }

    /// Register any fonts bundled in the theme's `fonts/` folder (process scope, so the
    /// theme's widgets/labels can use e.g. "Chicago" without installing system-wide).
    private func registerThemeFonts() {
        guard let theme = activeTheme else { return }
        let dir = theme.url.appendingPathComponent("fonts")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where ["ttf", "otf"].contains(f.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)   // already-registered → harmless error
        }
    }

    /// Last-resort desktop picture when a screen has no recoverable original. Anything is better
    /// than leaving the user stuck on a retro theme wallpaper they cannot get rid of.
    static var systemDefaultWallpaper: URL {
        let candidates = [
            "/System/Library/CoreServices/DefaultDesktop.heic",
            "/System/Library/Desktop Pictures/Ventura Graphic.heic",
            "/System/Library/Desktop Pictures/Monterey Graphic.heic",
        ]
        for p in candidates where FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
    }

    /// Where `tiledWallpaperURL` caches its pre-rendered pattern tiles.
    private static var tiledWallpaperDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/TiledWallpapers", isDirectory: true)
    }

    /// Is this desktop picture one RetroMac put there (a theme's own file, or a rendered tile)?
    /// Such a URL must NEVER be snapshotted as the user's "original" — doing so is how a screen
    /// ends up permanently stuck on a theme wallpaper with nothing left to restore.
    private func isOwnWallpaper(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.hasPrefix(Self.tiledWallpaperDir.standardizedFileURL.path + "/") { return true }
        return availableThemes.contains { path.hasPrefix($0.url.standardizedFileURL.path + "/") }
    }

    /// A screen identifier that survives sleep, reconnects and reboots. `displayID` is handed out
    /// by the window server per session, so keying the wallpaper backup by it silently orphaned
    /// the entry whenever an external display was re-enumerated — the restore then found nothing
    /// for that screen and left the theme wallpaper in place.
    private func screenKey(for screen: NSScreen) -> String {
        let displayID = screen.displayID
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let str = CFUUIDCreateString(nil, uuid) as String? {
            return str
        }
        return "displayID:\(displayID)"   // last resort — better than nothing
    }

    func applyWallpaper() {
        guard let theme = activeTheme else {
            restoreWallpapers()
            return
        }
        // Highest priority: a custom wallpaper picked via "Browse…" (absolute path)
        let wpURL: URL
        if let customPath = AppSettings.shared.themeCustomWallpaper[theme.stableID],
           FileManager.default.fileExists(atPath: customPath) {
            wpURL = URL(fileURLWithPath: customPath)
        } else if let overrideFile = AppSettings.shared.themeWallpaperOverrides[theme.stableID] {
            if let overrideURL = theme.rootResource(overrideFile) {
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
            // Pattern-tile wallpapers (e.g. System 6 8×8): setDesktopImageURL has no tiling
            // mode, so pre-render the tile to this screen's exact pixel size. Only for
            // theme-bundled files — a custom "Browse…" wallpaper is never tiled.
            var finalURL = wpURL
            if theme.config.wallpaperTiled == true, wpURL.path.hasPrefix(theme.url.path),
               let tiled = tiledWallpaperURL(tile: wpURL, for: screen, themeName: theme.name) {
                finalURL = tiled
            }
            let screenKey = screenKey(for: screen)
            // Only capture the ORIGINAL once, and never capture one of OUR OWN wallpapers as the
            // "original" — not just the exact file we are about to set, but any theme file or
            // rendered tile. Capturing one of ours is how a screen got stranded: the backup then
            // pointed at a theme image, so "restore" put the theme wallpaper back for good.
            if savedWallpapers[screenKey] == nil {
                let current = ws.desktopImageURL(for: screen)
                if let current, !isOwnWallpaper(current) {
                    savedWallpapers[screenKey] = current
                    print("[Theme] Saved original wallpaper for screen \(screenKey) (\(screen.localizedName)): \(current.path)")
                } else {
                    // No recoverable original (screen already shows one of ours, or macOS reports
                    // nothing). Remember that explicitly so the restore can still get the screen
                    // OFF our wallpaper instead of leaving it there forever.
                    savedWallpapers[screenKey] = Self.systemDefaultWallpaper
                    print("[Theme] No original wallpaper for screen \(screenKey) (\(screen.localizedName)) — will fall back to the system default on restore (was \(current?.path ?? "nil"))")
                }
                persistWallpaperBackup()   // crash-safe: back up the original BEFORE overwriting it
            }
            try? ws.setDesktopImageURL(finalURL, for: screen, options: [:])
        }
        persistWallpaperBackup()
        print("[Theme] Wallpaper set on \(NSScreen.screens.count) screen(s): \(wpURL.lastPathComponent)")
        AppearanceAdapter.apply(for: theme.config)
        CursorThemeManager.shared.apply(for: theme.config)
        TerminalThemer.apply(forThemeNamed: theme.config.name)
        SystemTweaksAdapter.apply(for: theme.config, isBuiltIn: theme.isBuiltIn)   // "Classic Finder" defaults tweaks (opt-in, built-in themes only)
    }

    /// Renders a small pattern tile edge-to-edge at the screen's pixel size (1 tile pixel
    /// = 1 point, crisp nearest-neighbour) and caches the PNG in Application Support.
    private func tiledWallpaperURL(tile: URL, for screen: NSScreen, themeName: String) -> URL? {
        guard let tileImg = NSImage(contentsOf: tile) else { return nil }
        let scale = screen.backingScaleFactor
        let pxW = Int(screen.frame.width * scale), pxH = Int(screen.frame.height * scale)
        guard pxW > 0, pxH > 0 else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/TiledWallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = themeName.replacingOccurrences(of: " ", with: "-")
        let out = dir.appendingPathComponent("\(safe)-\(tile.deletingPathExtension().lastPathComponent)-\(pxW)x\(pxH).png")
        if FileManager.default.fileExists(atPath: out.path) { return out }

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        // Build one pattern cell at device scale (nearest-neighbour keeps the pixels square).
        let cellW = tileImg.size.width * scale, cellH = tileImg.size.height * scale
        let cell = NSImage(size: NSSize(width: cellW, height: cellH))
        cell.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        tileImg.draw(in: NSRect(x: 0, y: 0, width: cellW, height: cellH))
        cell.unlockFocus()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor(patternImage: cell).setFill()
        NSRect(x: 0, y: 0, width: pxW, height: pxH).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do { try png.write(to: out) } catch { return nil }
        return out
    }

    func restoreWallpapers() {
        AppearanceAdapter.restore()   // matched appearance/accent returns with the wallpaper
        CursorThemeManager.shared.restore()   // and so does the user's cursor
        TerminalThemer.restore()      // and so does the user's Terminal profile
        SystemTweaksAdapter.restore() // and the real Finder/system look reverts too
        guard !savedWallpapers.isEmpty || anyScreenShowsOwnWallpaper() else { return }
        applyOriginalWallpapers()
        savedWallpapers.removeAll()
        persistWallpaperBackup()
        print("[Theme] Wallpaper restore pass complete")
    }

    /// Launch recovery for the WALLPAPER ONLY. A previous session set a theme wallpaper but was
    /// killed (crash / Mac restart) before restoring it, so the OS still shows the theme wallpaper
    /// while RetroMac starts clean — every other themed change resets via its own restoreIfNeeded,
    /// but the wallpaper had none, so it stuck until the user toggled a theme on+off. `savedWallpapers`
    /// is loaded from the persisted backup in init, so this puts the user's original back at launch.
    func restoreWallpapersIfNeeded() {
        // An EMPTY backup used to mean "nothing to do" — which is exactly how a screen stayed
        // stuck on a theme wallpaper forever once its backup was lost. If any screen still shows
        // one of ours, run the pass anyway so `applyOriginalWallpapers` can rescue it.
        guard !savedWallpapers.isEmpty || anyScreenShowsOwnWallpaper() else { return }
        applyOriginalWallpapers()
        savedWallpapers.removeAll()
        persistWallpaperBackup()
        print("[Theme] Launch wallpaper recovery complete")
    }

    /// True if any connected screen currently displays a RetroMac theme wallpaper.
    private func anyScreenShowsOwnWallpaper() -> Bool {
        NSScreen.screens.contains { screen in
            guard let current = NSWorkspace.shared.desktopImageURL(for: screen) else { return false }
            return isOwnWallpaper(current)
        }
    }

    private func applyOriginalWallpapers() {
        let ws = NSWorkspace.shared
        for screen in NSScreen.screens {
            let key = screenKey(for: screen)
            // Prefer the captured original. If there is none (a screen connected only after the
            // theme was applied, or a backup lost with an older build), the screen must still not
            // be left showing OUR wallpaper — fall back to the system default in that case.
            var target = savedWallpapers[key]
            if target == nil, let current = ws.desktopImageURL(for: screen), isOwnWallpaper(current) {
                target = Self.systemDefaultWallpaper
                print("[Theme] No backup for screen \(key) (\(screen.localizedName)) but it still shows a theme wallpaper — falling back to the system default")
            }
            guard let original = target else {
                print("[Theme] No saved wallpaper for screen \(key) (\(screen.localizedName)) — leaving as-is")
                continue
            }
            let ok = FileManager.default.fileExists(atPath: original.path)
            do {
                try ws.setDesktopImageURL(original, for: screen, options: [:])
                print("[Theme] Restored screen \(key) (\(screen.localizedName)) → \(original.lastPathComponent)\(ok ? "" : " [WARNING: file missing]")")
            } catch {
                print("[Theme] FAILED to restore screen \(key) (\(screen.localizedName)) → \(original.path): \(error.localizedDescription)")
            }
        }
    }

    private func persistWallpaperBackup() {
        if savedWallpapers.isEmpty {
            defaults.removeObject(forKey: wallpaperBackupKey)
        } else {
            let dict = savedWallpapers.mapValues { $0.absoluteString }
            defaults.set(dict, forKey: wallpaperBackupKey)
        }
        defaults.synchronize()   // flush so a crash/restart can still restore the user's wallpaper
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
        if let themeName = activeTheme?.stableID,
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
            var icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: size, height: size)
            // Pixel themes: auto-pixelate un-mapped apps' real icons so the whole dock
            // reads as one consistent pixel-art set without needing per-app artwork.
            if activeTheme?.config.isPixelated == true {
                icon = pixelated(icon, to: size)
            }
            // B/W themes (e.g. Mac OS 6): desaturate un-mapped system icons so every
            // running app blends into the monochrome look.
            if activeTheme?.config.icon.monochrome == true {
                icon = grayscaled(icon, size: size)
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
        var img = image
        if activeTheme?.config.isPixelated == true { img = pixelated(img, to: size) }
        if activeTheme?.config.icon.monochrome == true { img = grayscaled(img, size: size) }
        return img
    }

    /// Desaturate an icon to grayscale (B/W themes like Mac OS 6). Pure AppKit draw at the
    /// TARGET size with a saturation blend — the earlier CoreImage version ran the filter
    /// over the icon's largest rep (often 1024px TIFF) per app and beachballed the
    /// Applications widget.
    private func grayscaled(_ image: NSImage, size: CGFloat) -> NSImage {
        let px = Int(size * 2)   // retina
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let r = NSRect(x: 0, y: 0, width: size, height: size)
        image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor(calibratedWhite: 0.5, alpha: 1).setFill()
        r.fill(using: .saturation)                                            // drop the chroma
        image.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1.0)   // restore alpha
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: size, height: size))
        out.addRepresentation(rep)
        return out
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
        // Inset slightly so the pixelated (edge-to-edge) system icons match the visual
        // size of the padded custom artwork instead of looking a touch larger.
        let inset = size * 0.08
        rep.draw(in: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
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
        if let themeName = activeTheme?.stableID,
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

    /// `theme` may be a stable id or a display name; both resolve to the id used for storage.
    func customIconPath(for bundleID: String, theme: String? = nil) -> String? {
        let name = theme.flatMap { self.theme(for: $0)?.stableID ?? $0 } ?? activeTheme?.stableID ?? ""
        return iconOverrides[name]?[bundleID]
    }

    func setCustomIcon(for bundleID: String, path: String?) {
        guard let themeName = activeTheme?.stableID else { return }
        if iconOverrides[themeName] == nil {
            iconOverrides[themeName] = [:]
        }
        iconOverrides[themeName]?[bundleID] = path
        defaults.set(iconOverrides, forKey: overridesKey)
        iconCache.removeAllObjects()
        NotificationCenter.default.post(name: .dockAppsChanged, object: nil)
    }

    func hasOverrides(for theme: String? = nil) -> Bool {
        let name = theme.flatMap { self.theme(for: $0)?.stableID ?? $0 } ?? activeTheme?.stableID ?? ""
        guard let overrides = iconOverrides[name] else { return false }
        return !overrides.isEmpty
    }

    func saveExistingTheme() throws {
        guard let theme = activeTheme, !theme.isBuiltIn else {
            print("[Theme] Cannot save: no active user theme")
            return
        }
        guard let overrides = iconOverrides[theme.stableID], !overrides.isEmpty else {
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
        iconOverrides.removeValue(forKey: theme.stableID)
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

        if let overrides = iconOverrides[base.stableID] {
            for (bundleID, sourcePath) in overrides {
                let ext = (sourcePath as NSString).pathExtension
                let iconName = bundleID.replacingOccurrences(of: ".", with: "_") + "." + (ext.isEmpty ? "png" : ext)
                let destPath = iconsDir.appendingPathComponent(iconName)
                try? fm.removeItem(at: destPath)
                try fm.copyItem(atPath: sourcePath, toPath: destPath.path)
                newConfig.iconMappings[bundleID] = iconName
            }
        }

        // "Save as new theme" produces a genuinely NEW theme, so it must not keep the source's
        // id — otherwise the copy and the original would share every per-theme setting, and
        // selecting one would select the other. Written before reload() so the bundle re-read
        // from disk picks the new identity up.
        let newID = "user.\(ThemeBundle.slugify(name)).\(UUID().uuidString.prefix(8).lowercased())"
        newConfig.id = newID
        newConfig.schemaVersion = max(newConfig.schemaVersion ?? 0, 2)

        let newBundle = try ThemeBundle(url: destURL, isBuiltIn: false)
        try newBundle.save(config: newConfig)

        iconOverrides.removeValue(forKey: base.stableID)
        defaults.set(iconOverrides, forKey: overridesKey)

        reload()
        AppSettings.shared.dockTheme = newID
        print("[Theme] Saved new theme: \(name) [\(newID)]")
    }

    func importTheme(from sourceURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: userThemesDir, withIntermediateDirectories: true)

        if sourceURL.pathExtension.lowercased() == "zip" {
            // Unzip to a temp dir, then install the .retromactheme bundle found inside.
            let tmp = fm.temporaryDirectory.appendingPathComponent("rmtheme-import-\(UUID().uuidString)")
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", sourceURL.path, tmp.path]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try unzip.run(); unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                throw NSError(domain: "RetroMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not unzip the theme archive."])
            }
            guard let bundle = Self.findThemeBundle(in: tmp) else {
                throw NSError(domain: "RetroMac", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .retromactheme bundle found inside the .zip."])
            }
            try installThemeBundle(bundle)
        } else {
            try installThemeBundle(sourceURL)
        }
        reload()
        print("[Theme] Imported theme from \(sourceURL.lastPathComponent)")
    }

    private func installThemeBundle(_ src: URL) throws {
        let fm = FileManager.default
        let destURL = userThemesDir.appendingPathComponent(src.lastPathComponent)
        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
        try fm.copyItem(at: src, to: destURL)
    }

    /// Locate a *.retromactheme bundle at the archive root or one level deep (skips __MACOSX).
    private static func findThemeBundle(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        if let direct = items.first(where: { $0.pathExtension == "retromactheme" }) { return direct }
        for sub in items where sub.lastPathComponent != "__MACOSX"
            && ((try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true) {
            if let nested = (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "retromactheme" }) { return nested }
        }
        return nil
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
            let hasThemeIcon = iconOverrides[theme.stableID]?[bid] != nil
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
