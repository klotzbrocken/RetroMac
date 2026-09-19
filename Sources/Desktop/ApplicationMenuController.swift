import AppKit

/// Mac OS 9's Application menu: the front application's icon at the right end of the menu bar,
/// and under it Hide, Hide Others, Show All and every running application, the front one
/// ticked. macOS lets a menu-bar item sit only as far right as its own status items allow, so
/// this is a status item, as close to the corner as it gets. Shown by themes that declare
/// `menuBar.applicationMenu` (Mac OS 9 (authentic)).
final class ApplicationMenuController: NSObject, NSMenuDelegate {

    static let shared = ApplicationMenuController()

    private var item: NSStatusItem?
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
    }

    private func show() {
        if item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.imagePosition = .imageLeading   // Mac OS 8.5 onwards: the icon and the name
            i.button?.toolTip = "Application menu"
            let menu = NSMenu()
            menu.delegate = self
            i.menu = menu
            item = i
        }
        if observers.isEmpty {
            let nc = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                         NSWorkspace.didTerminateApplicationNotification] {
                observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshIcon() })
            }
        }
        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = item?.button else { return }
        let front = NSWorkspace.shared.frontmostApplication
        // RetroMac's own panels (settings, the readme) briefly make it the front app; the
        // menu keeps showing the app the user was in, as an accessory would.
        if front?.bundleIdentifier == Bundle.main.bundleIdentifier, button.image != nil { return }
        button.image = Self.classicIcon(for: front)
        button.title = front?.localizedName ?? ""
        button.font = NSFont(name: "Charcoal", size: 12) ?? NSFont(name: "ChicagoFLF", size: 12) ?? .menuBarFont(ofSize: 0)
    }

    /// The theme's own icon for an app it knows (the Finder's, TextEdit's…), the app's icon
    /// otherwise, at 16 pt.
    static func classicIcon(for app: NSRunningApplication?) -> NSImage? {
        var img: NSImage?
        if let bid = app?.bundleIdentifier, let u = ThemeManager.shared.activeTheme?.iconURL(for: bid) { img = NSImage(contentsOf: u) }
        if img == nil { img = app?.icon ?? NSImage(named: NSImage.applicationIconName) }
        let out = img?.copy() as? NSImage
        out?.size = NSSize(width: 16, height: 16)
        return out
    }

    // MARK: Menu

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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let front = NSWorkspace.shared.frontmostApplication
        let apps = Self.listedApps(NSWorkspace.shared.runningApplications)
        let hide = menu.addItem(withTitle: "Hide \(front?.localizedName ?? "Application")", action: #selector(hideFront), keyEquivalent: "")
        hide.target = self
        hide.isEnabled = front != nil && front?.bundleIdentifier != Bundle.main.bundleIdentifier
        let others = menu.addItem(withTitle: "Hide Others", action: #selector(hideOthers), keyEquivalent: "")
        others.target = self
        let all = menu.addItem(withTitle: "Show All", action: #selector(showAll), keyEquivalent: "")
        all.target = self
        menu.addItem(.separator())
        for app in apps {
            let i = menu.addItem(withTitle: app.localizedName ?? "?", action: #selector(activate(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = app
            i.image = Self.classicIcon(for: app)
            i.state = app == front ? .on : .off
            if app.isHidden { i.attributedTitle = NSAttributedString(string: app.localizedName ?? "?", attributes: [.foregroundColor: NSColor.tertiaryLabelColor]) }
        }
    }

    @objc private func activate(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        if app.isHidden { app.unhide() }
        app.activate(options: [])
    }

    @objc private func hideFront() { NSWorkspace.shared.frontmostApplication?.hide() }

    @objc private func hideOthers() {
        let front = NSWorkspace.shared.frontmostApplication
        for app in Self.listedApps(NSWorkspace.shared.runningApplications) where app != front { app.hide() }
    }

    @objc private func showAll() {
        for app in Self.listedApps(NSWorkspace.shared.runningApplications) where app.isHidden { app.unhide() }
    }
}
