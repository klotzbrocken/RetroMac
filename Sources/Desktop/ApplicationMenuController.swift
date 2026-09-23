import AppKit

/// Mac OS 9's Application menu: the front application's icon at the right end of the menu bar,
/// and under it Hide, Hide Others, Show All and every running application, the front one
/// ticked. macOS lets a menu-bar item sit only as far right as its own status items allow, so
/// this is a status item, as close to the corner as it gets. Shown by themes that declare
/// `menuBar.applicationMenu` (Mac OS 9 (authentic)).
final class ApplicationMenuController: NSObject {

    static let shared = ApplicationMenuController()

    private var item: NSStatusItem?
    /// System 7's Balloon Help: its own little item left of the Application menu, as the
    /// question-mark menu sat there.
    private var balloon: NSStatusItem?
    private var observers: [NSObjectProtocol] = []

    private override init() { super.init() }

    func update() {
        guard AppSettings.shared.dockEnabled, !AppSettings.shared.hideMenuBar,
              let theme = ThemeManager.shared.activeTheme, theme.config.hasApplicationMenu else { hide(); return }
        show()
    }

    func hide() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        if let balloon { NSStatusBar.system.removeStatusItem(balloon) }
        balloon = nil
    }

    private func show() {
        if item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.imagePosition = .imageLeading   // Mac OS 8.5 onwards: the icon and the name
            i.button?.toolTip = "Application menu"
            i.button?.target = self
            i.button?.action = #selector(open)
            item = i
        }
        if observers.isEmpty {
            let nc = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                         NSWorkspace.didTerminateApplicationNotification] {
                observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshIcon() })
            }
        }
        showBalloonHelpIfWanted()
        refreshIcon()
    }

    /// The Balloon Help item: the era's question mark in a speech balloon, and the menu it had
    /// (Show/Hide Balloons, and macOS's own help for the front app).
    private func showBalloonHelpIfWanted() {
        guard ThemeManager.shared.activeTheme?.config.hasBalloonHelp == true else {
            if let balloon { NSStatusBar.system.removeStatusItem(balloon) }
            balloon = nil
            return
        }
        guard balloon == nil else { return }
        let i = NSStatusBar.system.statusItem(withLength: 26)
        i.button?.image = Self.balloonImage()
        i.button?.toolTip = "Balloon Help"
        i.button?.target = self
        i.button?.action = #selector(openBalloonHelp)
        balloon = i
    }

    /// The balloon, drawn: a rounded speech balloon with a question mark, in black on nothing.
    static func balloonImage() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 16, height: 11), xRadius: 5, yRadius: 5)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 5, y: 5)); tail.line(to: NSPoint(x: 4, y: 0)); tail.line(to: NSPoint(x: 9, y: 4)); tail.close()
        NSColor.black.setStroke(); NSColor.white.setFill()
        body.fill(); tail.fill()
        body.lineWidth = 1.5; body.stroke(); tail.lineWidth = 1.5; tail.stroke()
        let mark = "?" as NSString
        let font = RetroFonts.chicago(12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let s = mark.size(withAttributes: attrs)
        mark.draw(at: NSPoint(x: (size.width - s.width) / 2, y: 4 + (11 - s.height) / 2), withAttributes: attrs)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    @objc private func openBalloonHelp() {
        guard let button = balloon?.button, let window = button.window else { return }
        let menu = PlatinumMenuController.shared
        if menu.isOpen { menu.dismissAll(); return }
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Application"
        let rows: [PlatinumMenuItem] = [
            .label("Balloon Help is macOS's own help now"),
            .separator(),
            .action("\(front) Help") { NSApp.activate(ignoringOtherApps: false); NSHelpManager.shared.openHelpAnchor("", inBook: nil) },
            .action("macOS Help") { if let u = URL(string: "help:openbook=com.apple.machelp") { NSWorkspace.shared.open(u) } },
        ]
        menu.ignoreClickWindow = window
        menu.show(rows, below: window.convertToScreen(button.convert(button.bounds, to: nil)))
    }

    private func refreshIcon() {
        guard let button = item?.button else { return }
        let front = NSWorkspace.shared.frontmostApplication
        // RetroMac's own panels (settings, the readme) briefly make it the front app; the
        // menu keeps showing the app the user was in, as an accessory would.
        if front?.bundleIdentifier == Bundle.main.bundleIdentifier, button.image != nil { return }
        button.image = Self.classicIcon(for: front)
        // System 7.1 showed the icon alone; 8.5 put the name beside it.
        let iconOnly = ThemeManager.shared.activeTheme?.config.applicationMenuIsIconOnly == true
        button.title = iconOnly ? "" : (front?.localizedName ?? "")
        button.font = RetroFonts.chicago(16)
    }

    /// The theme's own icon for an app it knows (the Finder's, TextEdit's…), the app's icon
    /// otherwise, at 16 pt.
    static func classicIcon(for app: NSRunningApplication?) -> NSImage? {
        let theme = ThemeManager.shared.activeTheme
        let key = "\(theme?.stableID ?? "-")|app|\(app?.bundleIdentifier ?? "-")" as NSString
        if let hit = iconCache.object(forKey: key) { return hit }
        var img = theme?.classicAppIcon(for: app?.bundleIdentifier)
        if img == nil { img = app?.icon ?? NSImage(named: NSImage.applicationIconName) }
        guard let img else { return nil }
        // A 256-colour theme snaps it once, here; the menu is redrawn far more often than the
        // front application changes.
        let out: NSImage
        if theme?.config.hasMac256Palette == true {
            out = Mac256.icon(img, points: 16, scale: 2)
        } else {
            out = (img.copy() as? NSImage) ?? img
            out.size = NSSize(width: 16, height: 16)
        }
        iconCache.setObject(out, forKey: key)
        return out
    }

    /// The menu's pictures, kept between openings (one per app, per theme).
    private static let iconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.countLimit = 200; return c
    }()

    // MARK: Menu

    /// As Mac OS 9 did on the pick: the application comes to the front with every one of its
    /// windows, not just the last one used. An app whose windows are all minimised (the Dock is
    /// out of sight under this theme, so they would stay lost) gets its first one back.
    static func bringForward(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        guard AXIsProcessTrusted() else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], !windows.isEmpty else { return }
        func minimised(_ w: AXUIElement) -> Bool {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &v) == .success && (v as? Bool) == true
        }
        let shown = windows.filter { !minimised($0) }
        let raise = shown.isEmpty ? [windows[0]] : shown
        for w in raise {
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        }
    }

    /// The running applications the menu lists: regular apps, RetroMac itself excluded,
    /// in the order the workspace reports them.
    static func listedApps(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        let own = Bundle.main.bundleIdentifier
        return apps.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != own && !$0.isTerminated }
    }

    /// The menu's rows: Hide <front>, Hide Others, Show All, a separator, then the apps with
    /// the front one ticked. Pure, so it can be tested with names alone.
    struct Row: Equatable { let title: String; let ticked: Bool; let dimmed: Bool; let separator: Bool }
    static func rows(apps: [(name: String, hidden: Bool)], front: String?) -> [Row] {
        var out = [Row(title: "Hide \(front ?? "Application")", ticked: false, dimmed: front == nil, separator: false),
                   Row(title: "Hide Others", ticked: false, dimmed: false, separator: false),
                   Row(title: "Show All", ticked: false, dimmed: false, separator: false),
                   Row(title: "", ticked: false, dimmed: false, separator: true)]
        for a in apps { out.append(Row(title: a.name, ticked: a.name == front, dimmed: a.hidden, separator: false)) }
        return out
    }

    /// The menu, Platinum-drawn, below the item; the item's own click closes it again.
    @objc private func open() {
        guard let button = item?.button, let window = button.window else { return }
        let menu = PlatinumMenuController.shared
        if menu.isOpen { menu.dismissAll(); return }
        let front = NSWorkspace.shared.frontmostApplication
        let apps = Self.listedApps(NSWorkspace.shared.runningApplications)
        var rows: [PlatinumMenuItem] = [
            .action("Hide \(front?.localizedName ?? "Application")", dimmed: front == nil || front?.bundleIdentifier == Bundle.main.bundleIdentifier) { front?.hide() },
            .action("Hide Others") { for app in apps where app != front { app.hide() } },
            .action("Show All") { for app in apps where app.isHidden { app.unhide() } },
            .separator(),
        ]
        for app in apps {
            rows.append(.action(app.localizedName ?? "?", icon: Self.classicIcon(for: app), ticked: app == front, dimmed: false) {
                Self.bringForward(app)
            })
        }
        menu.ignoreClickWindow = window
        menu.show(rows, below: window.convertToScreen(button.convert(button.bounds, to: nil)))
    }
}
