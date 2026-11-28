import AppKit

/// The menus of KDE 1.0's panel (K01, K07, K08): the K menu with kpanel's application groups as
/// they came in applnk (Applications, Games, Graphics, Internet, Multimedia, Settings, System,
/// Utilities), then the fixed entries; the window list; the window operations menu.
enum KDEMenus {
    static let groups = ["Applications", "Games", "Graphics", "Internet", "Multimedia", "Settings", "System", "Utilities"]
    static let groupIcons = ["Applications": "applications_package.png", "Games": "games_package.png", "Graphics": "graphics_package.png",
                             "Internet": "network_package.png", "Multimedia": "multimedia_package.png", "Settings": "settings_package.png",
                             "System": "system_package.png", "Utilities": "utilities_package.png"]

    /// The theme's mini picture: its own 16 pt drawing under icons/mini when there is one.
    static func mini(_ file: String) -> NSImage? {
        guard let theme = ThemeManager.shared.activeTheme else { return nil }
        let key = theme.stableID + "/" + file
        if let i = cache[key] { return i }
        let i = (theme.iconResource("mini/" + file) ?? theme.iconResource(file)).flatMap { NSImage(contentsOf: $0) }
        cache[key] = i
        return i
    }
    private static var cache: [String: NSImage] = [:]

    /// An app's menu picture: the mini drawing of its mapped icon, else its themed icon at 16.
    static func miniIcon(bundleID: String?, pid: pid_t? = nil, path: String? = nil) -> NSImage? {
        if let b = bundleID, !b.isEmpty {
            if let file = ThemeManager.shared.activeTheme?.config.iconMappings[b], let i = mini(file) { return i }
            return ThemeManager.shared.icon(for: b, size: 16)
        }
        if let pid { return NSRunningApplication(processIdentifier: pid)?.icon }
        return path.map { NSWorkspace.shared.icon(forFile: $0) }
    }

    static func appItem(_ a: KDEApps.App) -> CDEMenuItem {
        CDEMenuItem(title: a.title, icon: miniIcon(bundleID: a.bundleID, path: a.path), action: { KDEApps.open(a) })
    }

    /// One application group, alphabetically; an empty one says so (K01).
    static func category(_ name: String) -> [CDEMenuItem] {
        let list = KDEApps.apps().filter { $0.group == name }.map(appItem)
        return list.isEmpty ? [CDEMenuItem(title: "(No applications)", enabled: false)] : fit(list)
    }

    static func kMenu() -> [CDEMenuItem] {
        let apps = KDEApps.apps()
        var items = groups.map { g in CDEMenuItem(title: g, icon: mini(groupIcons[g] ?? "folder.png"), submenu: category(g)) }
        items += [.separator,
                  // The Mac adaptation (K07): every app, A to Z, and a line to type a name into.
                  CDEMenuItem(title: "All Applications", icon: mini("applications_package.png"), submenu: fit(apps.map(appItem))),
                  CDEMenuItem(title: "Run Command...", icon: mini("go.png"), action: { KDECommandPanel.show() }),
                  .separator,
                  CDEMenuItem(title: "Find Files", icon: mini("kfind.png"), action: findFiles),
                  CDEMenuItem(title: "Help", icon: mini("kdehelp.png"), action: { ThemeReadmeController.shared.showForActiveTheme() }),
                  CDEMenuItem(title: "Home Directory", icon: mini("kfm_home.png"), action: CDEActions.open(CDEActions.home)),
                  CDEMenuItem(title: "KDE Control Center", icon: mini("kcontrol.png"), action: CDEActions.app("com.apple.systempreferences")),
                  CDEMenuItem(title: "Panel", icon: mini("go.png"), submenu: [
                    CDEMenuItem(title: "Configure", action: { AppDelegate.shared?.launcherOpenSettings() }),
                    CDEMenuItem(title: "Hide", action: {
                        KPanelView.isHidden = true
                        KDEDesktopController.shared.layout()
                    })]),
                  .separator,
                  CDEMenuItem(title: "Lock Screen", icon: mini("key.png"), action: { ScreensaverController.shared.start() }),
                  CDEMenuItem(title: "Logout", icon: mini("exit.png"), action: logout)]
        return items
    }

    /// kfm's menu on the bare desktop (KDE 1.x root menu), with what the Mac can do: help, the
    /// command line, the display settings, a refresh, the icons arranged, lock and logout. Its
    /// window arranging (unclutter, cascade) is left out: macOS lets no app place others' windows.
    static func desktopMenu() -> [CDEMenuItem] {
        [CDEMenuItem(title: "Help on desktop", icon: mini("kdehelp.png"), action: { ThemeReadmeController.shared.showForActiveTheme() }),
         CDEMenuItem(title: "Execute command", icon: mini("go.png"), action: { KDECommandPanel.show() }),
         // kcmdisplay's Background page, in short: the theme's pictures, or one of your own.
         CDEMenuItem(title: "Display properties", submenu: backgroundMenu()),
         CDEMenuItem(title: "Refresh desktop", action: { DesktopIconsController.shared.update() }),
         CDEMenuItem(title: "Arrange icons", action: { DesktopIconsController.shared.snapToGrid() }),
         .separator,
         CDEMenuItem(title: "Lock screen", icon: mini("key.png"), action: { ScreensaverController.shared.start() }),
         CDEMenuItem(title: "Logout", icon: mini("exit.png"), action: logout)]
    }

    static func backgroundMenu() -> [CDEMenuItem] {
        let d = DesktopIconsController.shared
        let options = ThemeManager.shared.activeTheme?.wallpaperOptions() ?? []
        return options.map { wp in
            let file = wp.url.lastPathComponent
            return CDEMenuItem(title: (d.currentWallpaperFile == file ? "\u{2713} " : "   ") + wp.name, action: { d.pickWallpaper(file: file) })
        } + [.separator, CDEMenuItem(title: "Browse...", action: { d.browseWallpaper() })]
    }

    /// kfind looked for files; the Mac's is Finder's search, from a Finder window at home.
    static func findFiles() { CDEActions.open(CDEActions.home)() }

    /// "Logout" ends the KDE session, which here is the theme; the Mac session stays.
    static func logout() {
        let a = NSAlert()
        a.messageText = "End the KDE session?"
        a.informativeText = "The KDE theme is switched off. Your Mac session, its apps and documents stay open."
        a.addButton(withTitle: "Logout"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { AppDelegate.shared?.launcherDisableTheme() }
    }

    /// The window list: every window under the desktop it is on, which for a Mac window is the
    /// current one (kpanel's list names each desktop above its windows).
    static func windowList() -> [CDEMenuItem] {
        let windows = MinimizedWindowTracker.shared.allWindows
        let current = KDEDesktopController.currentDesktop
        var items: [CDEMenuItem] = []
        for (d, name) in KDEDesktopController.desktopNames.enumerated() {
            if !items.isEmpty { items.append(.separator) }
            items.append(CDEMenuItem(title: name, enabled: false))
            guard d == current else { continue }
            for w in windows {
                let title = w.title.isEmpty ? (NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? "Window") : w.title
                items.append(CDEMenuItem(title: w.isMinimized ? "[\(title)]" : title, icon: miniIcon(bundleID: w.bundleID, pid: w.pid),
                                         action: { MinimizedWindowTracker.shared.activate(w) }))
            }
        }
        return items
    }

    /// kwm's operations menu for one window. "To desktop" is there and dimmed: a Mac window cannot
    /// be moved to another desktop without minimising it (Lastenheft §4).
    static func windowMenu(_ w: MinimizedWindowTracker.Entry) -> [CDEMenuItem] {
        func press(_ attr: String) -> (() -> Void)? {
            guard !w.isAppLevel else { return nil }
            var button: AnyObject?
            guard AXUIElementCopyAttributeValue(w.window, attr as CFString, &button) == .success, let b = button else { return nil }
            return { AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString) }
        }
        return [CDEMenuItem(title: "Maximize", enabled: press(kAXZoomButtonAttribute) != nil, action: press(kAXZoomButtonAttribute)),
                CDEMenuItem(title: w.isMinimized ? "Restore" : "Iconify", action: {
                    if w.isMinimized { MinimizedWindowTracker.shared.activate(w) } else { MinimizedWindowTracker.shared.minimize(w) }
                }),
                CDEMenuItem(title: "Sticky", enabled: false),
                CDEMenuItem(title: "To desktop (Mac windows stay put)", enabled: false),
                .separator,
                CDEMenuItem(title: "Close", enabled: press(kAXCloseButtonAttribute) != nil, action: press(kAXCloseButtonAttribute))]
    }

    /// A list taller than the screen ends in "More", which holds the rest.
    static func fit(_ list: [CDEMenuItem]) -> [CDEMenuItem] {
        let rows = max(8, Int(((NSScreen.screens.first?.visibleFrame.height ?? 800) - KPanelView.height - 40) / CDEMenu.kdeRow))
        guard list.count > rows else { return list }
        return Array(list.prefix(rows - 1)) + [CDEMenuItem(title: "More", submenu: fit(Array(list.dropFirst(rows - 1))))]
    }
}

/// The installed Mac apps as KDE's menu needs them (K07, K08): the system's, the shared and your
/// own, Utilities, and the vendor folders one level down; helpers inside a bundle are never
/// listed, because nothing descends into a `.app`. One entry per bundle ID (an alias and its
/// original are one app); two separate installs of the same name say where each one is.
enum KDEApps {
    struct App: Equatable { let title: String; let path: String; let bundleID: String?; let group: String }

    static let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]

    /// KDE's group for an app, from the category it declares; web and mail apps are Internet.
    static func group(path: String, category: String?, internet: Set<String>) -> String {
        if internet.contains(path) { return "Internet" }
        if path.hasSuffix("/System Settings.app") { return "Settings" }
        let c = (category ?? "").replacingOccurrences(of: "public.app-category.", with: "")
        if c.hasSuffix("games") { return "Games" }
        switch c {
        case "graphics-design", "photography": return "Graphics"
        case "music", "video", "entertainment": return "Multimedia"
        case "social-networking", "news": return "Internet"
        case "developer-tools": return "System"
        case "utilities": return "Utilities"
        default: return path.contains("/Utilities/") ? "System" : "Applications"
        }
    }

    static func scan() -> [App] {
        let fm = FileManager.default
        var paths: [String] = []
        for dir in dirs {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                let full = dir + "/" + name
                if name.hasSuffix(".app") { paths.append(full); continue }
                var isDir: ObjCBool = false
                // A vendor folder ("Microsoft Office", "Adobe …"): its apps, one level down.
                guard name != "Utilities", fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
                paths += ((try? fm.contentsOfDirectory(atPath: full)) ?? []).filter { $0.hasSuffix(".app") }.map { full + "/" + $0 }
            }
        }
        let internet = Set(["https://example.com", "mailto:x@example.com"].compactMap(URL.init(string:))
            .flatMap { NSWorkspace.shared.urlsForApplications(toOpen: $0) }.map(\.path))
        var byID: [String: App] = [:], loose: [App] = []
        for path in paths.map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) {
            let bundle = Bundle(path: path)
            let title = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            let app = App(title: title, path: path, bundleID: bundle?.bundleIdentifier,
                          group: group(path: path, category: bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String, internet: internet))
            if let id = app.bundleID { if byID[id] == nil { byID[id] = app } } else { loose.append(app) }
        }
        return disambiguate(Array(byID.values) + loose)
    }

    /// Two apps of the same name get their folder after it, so the right one can be chosen.
    static func disambiguate(_ apps: [App]) -> [App] {
        let counts = Dictionary(grouping: apps, by: \.title).mapValues(\.count)
        return apps.map { a in
            guard (counts[a.title] ?? 0) > 1 else { return a }
            let folder = URL(fileURLWithPath: a.path).deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            return App(title: "\(a.title) (\(folder))", path: a.path, bundleID: a.bundleID, group: a.group)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static var scanned: [App]?

    /// File reading, so never on the main thread while a menu opens.
    static func prepare() {
        DispatchQueue.global(qos: .utility).async {
            let apps = scan()
            DispatchQueue.main.async { scanned = apps }
        }
    }

    /// What the last read found; installs and removals show the next time.
    static func apps() -> [App] {
        let list = scanned ?? scan()
        prepare()
        return list
    }

    /// A running app comes to the front, one that is not running starts, from the chosen copy.
    static func open(_ a: App) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: a.path), configuration: .init()) { _, error in
            if error != nil { DispatchQueue.main.async { NSSound.beep() } }
        }
    }
}

/// "Run Command...": kwm's minicli (Alt-F2) on the Mac. Type a name and Return starts the best
/// match among the installed apps; a web address or a path opens as the Finder would open it.
enum KDECommandPanel {
    private static var panel: NSPanel?

    static func show() {
        if let p = panel { p.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 64), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = "Run Command"
        p.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Command:")
        label.font = KDEColors.font
        label.frame = NSRect(x: 12, y: 22, width: 70, height: 20)
        let box = NSComboBox(frame: NSRect(x: 84, y: 18, width: 282, height: 26))
        box.completes = true
        box.addItems(withObjectValues: KDEApps.apps().map(\.title))
        box.target = Runner.shared
        box.action = #selector(Runner.run(_:))
        p.contentView?.addSubview(label)
        p.contentView?.addSubview(box)
        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(box)
    }

    /// The app a command names: its exact name first, then one starting with it, then one holding it.
    static func match(_ text: String, in apps: [KDEApps.App]) -> KDEApps.App? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        return apps.first { $0.title.lowercased() == t } ?? apps.first { $0.title.lowercased().hasPrefix(t) }
            ?? apps.first { $0.title.lowercased().contains(t) }
    }

    private final class Runner: NSObject {
        static let shared = Runner()
        @objc func run(_ sender: NSComboBox) {
            let text = sender.stringValue.trimmingCharacters(in: .whitespaces)
            if let app = KDECommandPanel.match(text, in: KDEApps.apps()) {
                KDEApps.open(app)
            } else if let url = URL(string: text), url.scheme != nil {
                NSWorkspace.shared.open(url)
            } else if FileManager.default.fileExists(atPath: (text as NSString).expandingTildeInPath) {
                NSWorkspace.shared.open(URL(fileURLWithPath: (text as NSString).expandingTildeInPath))
            } else { NSSound.beep(); return }
            sender.stringValue = ""
            KDECommandPanel.panel?.orderOut(nil)
        }
    }
}
