import AppKit

/// Mac OS 9's Application menu: the front application's icon at the right end of the menu bar,
/// and under it Hide, Hide Others, Show All and every running application, the front one
/// ticked. macOS lets a menu-bar item sit only as far right as its own status items allow, so
/// this is a status item, as close to the corner as it gets. Shown by themes that declare
/// `menuBar.applicationMenu` (Mac OS 9 (authentic)).
final class ApplicationMenuController: NSObject {

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
        var img = ThemeManager.shared.activeTheme?.classicAppIcon(for: app?.bundleIdentifier)
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
                if app.isHidden { app.unhide() }
                app.activate(options: [])
            })
        }
        menu.ignoreClickWindow = window
        menu.show(rows, below: window.convertToScreen(button.convert(button.bounds, to: nil)))
    }
}
