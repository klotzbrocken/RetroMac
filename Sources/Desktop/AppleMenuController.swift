import AppKit

/// Mac OS 9's Apple menu, opened from the Apple cover in the menu bar (`RainbowAppleController`
/// hands the click over when the theme declares `menuBar.appleMenu`). The items are the ones a
/// fresh Mac OS 9 had, each pointed at what macOS has today; Recent Applications, Recent
/// Documents and Favorites come from the same lists the Finder keeps.
final class AppleMenuController: NSObject, NSMenuDelegate {

    static let shared = AppleMenuController()
    private override init() { super.init() }

    private let menu = NSMenu()

    func popUp(below rect: NSRect, in window: NSWindow) {
        menu.delegate = self
        menuNeedsUpdate(menu)
        // Below the Apple item, left-aligned with it, the way the real menu drops.
        let origin = NSPoint(x: rect.minX, y: rect.minY)
        menu.popUp(positioning: nil, at: window.convertPoint(fromScreen: origin), in: window.contentView)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(open("About This Computer…", "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension"))
        menu.addItem(.separator())
        menu.addItem(submenu("Applications", Self.applications()))
        menu.addItem(app("Apple System Profiler", "/System/Applications/Utilities/System Information.app"))
        menu.addItem(app("Calculator", "/System/Applications/Calculator.app"))
        menu.addItem(open("Chooser", "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension"))
        menu.addItem(submenu("Control Panels", Self.controlPanels()))
        menu.addItem(submenu("Favorites", Self.sharedList("FavoriteItems")))
        menu.addItem(file("Network Browser", "/Network"))
        menu.addItem(submenu("Recent Applications", Self.sharedList("RecentApplications")))
        menu.addItem(submenu("Recent Documents", Self.sharedList("RecentDocuments")))
        menu.addItem(submenu("Recent Servers", Self.sharedList("RecentServers")))
        menu.addItem(app("Sherlock 2", "/System/Library/CoreServices/Spotlight.app"))
        menu.addItem(app("Stickies", "/System/Applications/Stickies.app"))
    }

    // MARK: Items

    private func open(_ title: String, _ url: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(openURL(_:)), keyEquivalent: "")
        i.target = self; i.representedObject = url
        return i
    }
    private func app(_ title: String, _ path: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(openPath(_:)), keyEquivalent: "")
        i.target = self; i.representedObject = path
        i.image = Self.smallIcon(forPath: path)
        i.isEnabled = FileManager.default.fileExists(atPath: path)
        return i
    }
    private func file(_ title: String, _ path: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(openPath(_:)), keyEquivalent: "")
        i.target = self; i.representedObject = path
        return i
    }
    private func submenu(_ title: String, _ entries: [(title: String, path: String)]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
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
        var img: NSImage?
        if path.hasSuffix(".app"), let bid = Bundle(path: path)?.bundleIdentifier,
           let u = ThemeManager.shared.activeTheme?.iconURL(for: bid), let themed = NSImage(contentsOf: u) {
            img = themed
        } else {
            img = NSWorkspace.shared.icon(forFile: path)
        }
        let out = img?.copy() as? NSImage
        out?.size = NSSize(width: 16, height: 16)
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
