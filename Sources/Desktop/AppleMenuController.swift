import AppKit

/// Mac OS 9's Apple menu, opened from the Apple cover in the menu bar (`RainbowAppleController`
/// hands the click over when the theme declares `menuBar.appleMenu`). The items are the ones a
/// fresh Mac OS 9 had, each pointed at what macOS has today; Recent Applications, Recent
/// Documents and Favorites come from the same lists the Finder keeps.
final class AppleMenuController {

    static let shared = AppleMenuController()
    private init() {}

    func popUp(below rect: NSRect, in window: NSWindow) {
        if PlatinumMenuController.shared.isOpen { PlatinumMenuController.shared.dismissAll(); return }
        PlatinumMenuController.shared.ignoreClickWindow = window
        PlatinumMenuController.shared.show(items(), below: rect)
    }

    /// The menu of the day, first level in the theme's own pictures (icons/…).
    func items() -> [PlatinumMenuItem] {
        [open("About This Computer…", "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension", icon: "computer.png"),
         .separator(),
         submenu("Applications", icon: themeIcon("folder.png")) { Self.entries(Self.applications()) },
         app("Apple System Profiler", "/System/Applications/Utilities/System Information.app", icon: "profiler.png"),
         app("Calculator", "/System/Applications/Calculator.app", icon: "calculator.png"),
         open("Chooser", "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension", icon: "chooser.png"),
         submenu("Control Panels", icon: themeIcon("settings.png")) { Self.entries(Self.controlPanels()) },
         submenu("Favorites", icon: themeIcon("favorites.png")) { Self.entries(Self.sharedList("FavoriteItems")) },
         file("Network Browser", "/Network", icon: "network.png"),
         submenu("Recent Applications", icon: themeIcon("recent-apps.png")) { Self.entries(Self.sharedList("RecentApplications")) },
         submenu("Recent Documents", icon: themeIcon("recent-docs.png")) { Self.entries(Self.sharedList("RecentDocuments")) },
         submenu("Recent Servers", icon: themeIcon("recent-servers.png")) { Self.entries(Self.sharedList("RecentServers")) },
         app("Sherlock 2", "/System/Library/CoreServices/Spotlight.app", icon: "sherlock.png"),
         app("Stickies", "/System/Applications/Stickies.app", icon: "stickies.png")]
    }

    // MARK: Items

    private func open(_ title: String, _ url: String, icon: String? = nil) -> PlatinumMenuItem {
        .action(title, icon: icon.flatMap { Self.themeIcon($0) }) { Self.openTarget(url) }
    }
    private func app(_ title: String, _ path: String, icon: String? = nil) -> PlatinumMenuItem {
        .action(title, icon: icon.flatMap { Self.themeIcon($0) } ?? Self.smallIcon(forPath: path),
                dimmed: !FileManager.default.fileExists(atPath: path)) { Self.openTarget(path) }
    }
    private func file(_ title: String, _ path: String, icon: String? = nil) -> PlatinumMenuItem {
        .action(title, icon: icon.flatMap { Self.themeIcon($0) }) { Self.openTarget(path) }
    }
    /// A submenu row built on the way in (`PlatinumMenuItem.submenu(_:icon:rows:)`).
    private func submenu(_ title: String, icon: NSImage?, _ rows: @escaping () -> [PlatinumMenuItem]) -> PlatinumMenuItem {
        .submenu(title, icon: icon, rows: rows)
    }
    private func themeIcon(_ name: String) -> NSImage? { Self.themeIcon(name) }

    /// A list of places as menu rows, each with the small icon of its file.
    static func entries(_ entries: [(title: String, path: String)]) -> [PlatinumMenuItem] {
        entries.map { e in
            .action(e.title, icon: e.path.hasPrefix("x-apple") ? nil : smallIcon(forPath: e.path)) { openTarget(e.path) }
        }
    }

    /// A Settings pane URL, an application, or a file or folder.
    static func openTarget(_ target: String) {
        if target.hasPrefix("x-apple"), let u = URL(string: target) { NSWorkspace.shared.open(u); return }
        let url = URL(fileURLWithPath: target)
        if target.hasSuffix(".app") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// The pictures the theme does not have yet, and what stands in for them meanwhile.
    static let standIns: [String: String] = [
        "profiler.png": "memory.png", "chooser.png": "printer.png", "favorites.png": "folder.png",
        "recent-apps.png": "folder.png", "recent-docs.png": "folder.png", "recent-servers.png": "network.png",
        "calculator.png": "generic.png", "stickies.png": "notes.png",
    ]

    /// A 16 pt picture from the theme's icons folder, for the first-level items; a picture
    /// the theme lacks falls back to its stand-in, then to the theme's generic icon.
    static func themeIcon(_ name: String) -> NSImage? {
        guard let theme = ThemeManager.shared.activeTheme else { return nil }
        let key = "\(theme.stableID)|theme|\(name)" as NSString
        if let hit = iconCache.object(forKey: key) { return hit }
        for candidate in [name, standIns[name], theme.config.fallbackIcon].compactMap({ $0 }) {
            guard let u = theme.iconResource(candidate), let i = NSImage(contentsOf: u) else { continue }
            let out = prepared(i, theme: theme)
            iconCache.setObject(out, forKey: key)
            return out
        }
        return nil
    }

    /// One 16 pt picture, in the theme's own palette: a four-grey theme snaps it once, here,
    /// rather than every time a menu is drawn.
    private static func prepared(_ image: NSImage, theme: ThemeBundle) -> NSImage {
        if theme.config.hasFourGreys { return FourGrays.quantize(image, points: 16, scale: 2) }
        let out = (image.copy() as? NSImage) ?? image
        out.size = NSSize(width: 16, height: 16)
        return out
    }

    /// Menu pictures, kept between openings: building them is a file read and, in a four-grey
    /// theme, a pass over the picture.
    private static let iconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.countLimit = 400; return c
    }()

    private func open(_ title: String, _ url: String, icon: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(openURL(_:)), keyEquivalent: "")
        i.target = self; i.representedObject = url
        i.image = icon.flatMap { Self.themeIcon($0) }
        return i
    }
    private func app(_ title: String, _ path: String, icon: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(openPath(_:)), keyEquivalent: "")
        i.target = self; i.representedObject = path
        i.image = icon.flatMap { Self.themeIcon($0) } ?? Self.smallIcon(forPath: path)
        i.isEnabled = FileManager.default.fileExists(atPath: path)
        return i
    }
    private func file(_ title: String, _ path: String, icon: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(openPath(_:)), keyEquivalent: "")
        i.target = self; i.representedObject = path
        i.image = icon.flatMap { Self.themeIcon($0) }
        return i
    }
    private func submenu(_ title: String, _ entries: [(title: String, path: String)], icon: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.image = icon.flatMap { Self.themeIcon($0) }
        let m = NSMenu(title: title)
        if entries.isEmpty {
            let none = m.addItem(withTitle: "None", action: nil, keyEquivalent: "")
            none.isEnabled = false
        }
        for e in entries {
            let item = m.addItem(withTitle: e.title, action: #selector(openPath(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = e.path
            if !e.path.hasPrefix("x-apple") { item.image = Self.smallIcon(forPath: e.path) }
        }
        i.submenu = m
        return i
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
    @objc private func openPath(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? String else { return }
        if p.hasPrefix("x-apple"), let u = URL(string: p) { NSWorkspace.shared.open(u); return }
        let url = URL(fileURLWithPath: p)
        if p.hasSuffix(".app") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// 16 pt icon: the theme's own for an app it knows (the Finder, TextEdit…), else the file's.
    static func smallIcon(forPath path: String) -> NSImage? {
        let themeID = ThemeManager.shared.activeTheme?.stableID ?? "-"
        let key = "\(themeID)|path|\(path)" as NSString
        if let hit = iconCache.object(forKey: key) { return hit }
        var img: NSImage?
        if path.hasSuffix(".app") {
            img = ThemeManager.shared.activeTheme?.classicAppIcon(for: Bundle(path: path)?.bundleIdentifier)
        } else if let theme = ThemeManager.shared.activeTheme {
            // Folders and documents in the theme's own drawing, as the Finder of the day.
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            img = theme.iconResource(isDir.boolValue ? "folder.png" : "document.png").flatMap { NSImage(contentsOf: $0) }
        }
        if img == nil { img = NSWorkspace.shared.icon(forFile: path) }
        guard let img else { return nil }
        let out = ThemeManager.shared.activeTheme.map { prepared(img, theme: $0) } ?? img
        iconCache.setObject(out, forKey: key)
        return out
    }

    // MARK: Sources

    /// The applications folder, top level, sorted by name.
    static func applications() -> [(title: String, path: String)] {
        let fm = FileManager.default
        var out: [(String, String)] = []
        for dir in ["/Applications", "/System/Applications"] {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".app") {
                out.append((String(name.dropLast(4)), dir + "/" + name))
            }
        }
        return out.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    /// The control panels of the day, pointed at their Settings panes.
    static func controlPanels() -> [(title: String, path: String)] {
        [("Appearance", "x-apple.systempreferences:com.apple.Appearance-Settings.extension"),
         ("Date & Time", "x-apple.systempreferences:com.apple.Date-Time-Settings.extension"),
         ("Desktop Pictures", "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"),
         ("Energy Saver", "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
         ("General Controls", "x-apple.systempreferences:com.apple.Desktop-Settings.extension"),
         ("Keyboard", "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
         ("Monitors", "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
         ("Mouse", "x-apple.systempreferences:com.apple.Mouse-Settings.extension"),
         ("Sound", "x-apple.systempreferences:com.apple.Sound-Settings.extension"),
         ("Startup Disk", "x-apple.systempreferences:com.apple.Startup-Disk-Settings.extension"),
         ("TCP/IP", "x-apple.systempreferences:com.apple.Network-Settings.extension"),
         ("Users & Groups", "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")]
    }

    /// One of the Finder's shared file lists (`~/Library/Application Support/com.apple.sharedfilelist/`),
    /// resolved to paths; items whose bookmark no longer resolves are left out.
    static func sharedList(_ name: String) -> [(title: String, path: String)] {
        let base = NSHomeDirectory() + "/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.\(name)"
        guard let url = ["sfl4", "sfl3", "sfl2"].map({ URL(fileURLWithPath: base + "." + $0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: url),
              let un = try? NSKeyedUnarchiver(forReadingFrom: data) else { return [] }
        un.requiresSecureCoding = false
        guard let root = un.decodeObject(forKey: "root") as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }
        var out: [(String, String)] = []
        for it in items {
            guard let bm = it["Bookmark"] as? Data else { continue }
            var stale = false
            guard let u = try? URL(resolvingBookmarkData: bm, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            var title = u.lastPathComponent
            if title.hasSuffix(".app") { title = String(title.dropLast(4)) }
            out.append((title, u.path))
        }
        return out
    }
}
