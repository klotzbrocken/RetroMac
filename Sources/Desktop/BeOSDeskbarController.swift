import AppKit

/// BeOS "Deskbar" — the compact panel anchored in a screen corner for the "BeOS Classic"
/// theme. It shows the Be logo button and a clock; clicking the logo pops open the
/// BeOS-styled Be menu (custom-drawn, see BeOSMenu) with the classic entries plus an
/// Applications submenu listing the running apps.
final class BeOSDeskbarController {

    static let shared = BeOSDeskbarController()

    private var window: NSPanel?
    private var view: BeOSDeskbarView?
    private var settingsObserver: NSObjectProtocol?

    private init() {}

    func update() {
        // Note: for BeOS the Deskbar IS the dock (dockStyle "deskbar" → no DockView),
        // so it must show even in dock-only mode — do NOT gate it on dockOnly.
        guard let theme = ThemeManager.shared.activeTheme, theme.config.isDeskbar else {
            hide()
            return
        }
        show(theme: theme)
    }

    func hide() {
        BeOSMenuController.shared.dismissAll()
        // Leaving the BeOS theme: fully tear down its widgets (release WKWebView +
        // JS context), not just orderOut — otherwise they stay warm in the background.
        CPUMonitorController.shared.destroy()
        AppFolderController.shared.destroy()
        view?.tearDown()
        window?.orderOut(nil)
        window = nil
        view = nil
        if let o = settingsObserver { NotificationCenter.default.removeObserver(o); settingsObserver = nil }
    }

    private func show(theme: ThemeBundle) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: BeOSDeskbarView.barWidth, height: 80),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: 24)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            self.window = panel
        }
        if settingsObserver == nil {
            settingsObserver = NotificationCenter.default.addObserver(
                forName: .deskbarSettingsChanged, object: nil, queue: .main) { [weak self] _ in self?.reposition() }
        }

        let v = BeOSDeskbarView(theme: theme)
        window?.contentView = v
        self.view = v
        reposition()
        window?.orderFront(nil)
    }

    private func reposition() {
        guard let window = window, let view = view, let screen = NSScreen.main else { return }
        let h = view.preferredHeight()
        let w = BeOSDeskbarView.barWidth
        let f = screen.visibleFrame
        let corner = AppSettings.shared.deskbarCorner
        let x = corner.contains("Right") ? (f.maxX - w) : f.minX
        let y = corner.hasPrefix("top") ? (f.maxY - h) : f.minY
        window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        view.frame = NSRect(origin: .zero, size: NSSize(width: w, height: h))
        view.openMenuUp = corner.hasPrefix("bottom")
        view.openMenuLeft = corner.contains("Right")
        view.needsDisplay = true
    }
}

// MARK: - Deskbar view (Be button + clock)

final class BeOSDeskbarView: NSView {

    static let barWidth: CGFloat = 164

    /// Quick-launch apps that can appear above the status view (label, bundle id). Icons come
    /// from the theme (same source as the Applications submenu).
    static let availableShortcuts: [(label: String, bundleID: String)] = [
        ("Finder",   "com.apple.finder"),
        ("Safari",   "com.apple.Safari"),
        ("Mail",     "com.apple.mail"),
        ("Messages", "com.apple.MobileSMS"),
        ("Calendar", "com.apple.iCal"),
        ("Tasks",    "com.apple.reminders"),
        ("Notes",    "com.apple.Notes"),
    ]

    private let appRowH: CGFloat = 26          // matches the Be menu row height
    private let appListIcon: CGFloat = 18
    private var appRects: [(NSRect, String)] = []
    private var appHover = -1
    private var trackingArea: NSTrackingArea?
    private let hiColor = NSColor(calibratedRed: 0.27, green: 0.45, blue: 0.78, alpha: 1)
    private var iconCache: [String: NSImage] = [:]

    private var enabledShortcuts: [(label: String, bundleID: String)] {
        let on = Set(AppSettings.shared.deskbarShortcuts)
        return Self.availableShortcuts.filter { on.contains($0.bundleID) }
    }
    private var appsH: CGFloat {
        // +2 for the permanent "Applications" (App Folder) and "Music" (TV streams) entries.
        return CGFloat(enabledShortcuts.count + 2) * appRowH + 4
    }

    /// The deskbar rows: App-Folder launcher, Music (TV streams), then the app shortcuts.
    /// "Applications" and "Music" open their window on click and a BeOS submenu on hover.
    private func appRows() -> [(label: String, icon: NSImage?, id: String)] {
        var rows: [(String, NSImage?, String)] = [
            ("Applications", dimg("folder-app.png"), "__appfolder__"),
            ("Music", dimg("folder-app.png"), "__music__"),
        ]
        for sc in enabledShortcuts {
            rows.append((sc.label, ThemeManager.shared.icon(for: sc.bundleID, size: appListIcon), sc.bundleID))
        }
        return rows
    }
    private func cachedDimg(_ name: String) -> NSImage? {
        if let c = iconCache[name] { return c }
        if let img = dimg(name) { iconCache[name] = img; return img }
        return nil
    }

    private let theme: ThemeBundle
    private var beLogo: NSImage?
    private var statusCPU: NSImage?
    private var statusMail: NSImage?
    private var statusPac: NSImage?
    private var clockTimer: Timer?
    private var menuOpen = false            // logo bg darkens while the menu is open
    private var hoverMenuID: String?        // id of the deskbar row whose hover-submenu is open
    var openMenuUp = true
    var openMenuLeft = false

    private var cpuRect = NSRect.zero
    private var mailRect = NSRect.zero
    private var pacRect = NSRect.zero
    private var clockRect = NSRect.zero

    private let headerH: CGFloat = 40
    private let statusH: CGFloat = 40
    private let pad: CGFloat = 3
    /// The Be logo sits at the screen edge; the status row (clock + tray icons) sits toward
    /// the interior, ABOVE the logo for bottom corners (below it for top corners).
    private var logoAtTop: Bool { !openMenuUp }

    private let faceColor  = NSColor(calibratedWhite: 0.85, alpha: 1)
    private let openFace   = NSColor(calibratedWhite: 0.60, alpha: 1)   // darker grey while menu open
    private let lightBevel = NSColor(calibratedWhite: 1.0, alpha: 1)
    private let darkBevel  = NSColor(calibratedWhite: 0.50, alpha: 1)
    private let sunkenFace = NSColor(calibratedWhite: 0.74, alpha: 1)
    private let yellowTab   = NSColor(calibratedRed: 1.0, green: 0.81, blue: 0.30, alpha: 1)

    private func dimg(_ name: String) -> NSImage? {
        NSImage(contentsOf: theme.url.appendingPathComponent("deskbar/\(name)"))
    }

    init(theme: ThemeBundle) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: Self.barWidth, height: 70))
        beLogo = dimg("be-logo.png")
        statusCPU = dimg("status-cpu.png")
        statusMail = dimg("status-mail.png")
        statusPac = dimg("pac.icns")
        startClock()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func tearDown() { clockTimer?.invalidate(); clockTimer = nil }
    deinit { tearDown() }

    func preferredHeight() -> CGFloat { pad + headerH + statusH + appsH + pad }

    private func startClock() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        RunLoop.main.add(t, forMode: .common); clockTimer = t
    }

    // Sections from the screen-edge inward: Logo (at edge) · Status · App shortcuts (interior).
    private var headerRect: NSRect {
        NSRect(x: pad, y: logoAtTop ? pad : (pad + appsH + statusH), width: bounds.width - 2 * pad, height: headerH)
    }
    private var statusRect: NSRect {
        NSRect(x: pad, y: logoAtTop ? (pad + headerH) : (pad + appsH), width: bounds.width - 2 * pad, height: statusH)
    }
    private var appsRect: NSRect {
        NSRect(x: pad, y: logoAtTop ? (pad + headerH + statusH) : pad, width: bounds.width - 2 * pad, height: appsH)
    }

    override func draw(_ dirtyRect: NSRect) {
        faceColor.setFill(); bounds.fill()
        drawBevel(bounds, raised: true)

        // Be-menu button — yellow grip tab + raised (or sunken when pressed) face + logo.
        let r = headerRect
        yellowTab.setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 6).fill()
        darkBevel.setFill()
        var gx = r.minX + 5
        while gx < r.maxX - 4 { NSRect(x: gx, y: r.minY + 2, width: 1.5, height: 1.5).fill(); gx += 4 }
        // The button face darkens (full width) while the menu is open — no bevel/press
        // change, matching the original which had no click state.
        let btn = NSRect(x: r.minX, y: r.minY + 6, width: r.width, height: r.height - 6)
        (menuOpen ? openFace : faceColor).setFill(); btn.fill()
        drawBevel(btn, raised: true)
        if let logo = beLogo {
            let maxW = btn.width - 16, maxH = btn.height - 10
            let ar = logo.size.width / max(1, logo.size.height)
            var w = maxW, h = w / ar
            if h > maxH { h = maxH; w = h * ar }
            let dst = NSRect(x: btn.midX - w / 2, y: btn.midY - h / 2, width: w, height: h)
            logo.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        }

        // Status view — clock + CPU/Mail tray icons, all packed toward the screen centre
        // (the side the menu flies out to).
        let s = statusRect
        sunkenFace.setFill(); s.fill()
        drawBevel(s, raised: false)
        let fmt = DateFormatter(); fmt.dateFormat = AppSettings.applyClockFormat("h:mm a")
        let str = fmt.string(from: Date())
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Helvetica-Bold", size: 14) ?? .boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)]
        let cs = str.size(withAttributes: attrs)
        let iconSz: CGFloat = 30, gap: CGFloat = 6, edge: CGFloat = 6
        // Fixed tray order: Mailbox (far left) · Processor · Pac-Man · (gap) · Clock (far right).
        mailRect = NSRect(x: s.minX + edge, y: s.midY - iconSz / 2, width: iconSz, height: iconSz)
        cpuRect  = NSRect(x: mailRect.maxX + gap, y: s.midY - iconSz / 2, width: iconSz, height: iconSz)
        pacRect  = NSRect(x: cpuRect.maxX + gap, y: s.midY - iconSz / 2, width: iconSz, height: iconSz)
        let clockX = s.maxX - edge - cs.width
        clockRect = NSRect(x: clockX - 4, y: s.midY - cs.height / 2 - 3, width: cs.width + 8, height: cs.height + 6)
        str.draw(at: NSPoint(x: clockX, y: s.midY - cs.height / 2), withAttributes: attrs)
        statusCPU?.draw(in: cpuRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        statusMail?.draw(in: mailRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if let p = statusPac {
            p.draw(in: pacRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            drawPacManIcon(pacRect)
        }

        drawApps()
    }

    /// Quick-launch apps (configurable) shown as a list — icon + name, same row size as the
    /// Be menu's Applications submenu — toward the interior, above the status view.
    private func drawApps() {
        appRects = []
        let ar = appsRect
        let font = BeOSMenuController.menuFont
        for (i, row) in appRows().enumerated() {
            let r = NSRect(x: ar.minX, y: ar.minY + 2 + CGFloat(i) * appRowH, width: ar.width, height: appRowH)
            appRects.append((r, row.id))
            let selected = i == appHover
            if selected { hiColor.setFill(); r.insetBy(dx: 1, dy: 0).fill() }
            row.icon?.draw(in: NSRect(x: r.minX + 5, y: r.midY - appListIcon / 2, width: appListIcon, height: appListIcon),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: selected ? NSColor.white : NSColor(calibratedWhite: 0.08, alpha: 1)]
            let ts = row.label.size(withAttributes: attrs)
            row.label.draw(at: NSPoint(x: r.minX + 28, y: r.midY - ts.height / 2), withAttributes: attrs)
            // Submenu indicator (small right-pointing triangle) for the hover-menu rows.
            if row.id == "__appfolder__" || row.id == "__music__" {
                let tx = r.maxX - 11, ty = r.midY
                let tri = NSBezierPath()
                tri.move(to: NSPoint(x: tx, y: ty - 4))
                tri.line(to: NSPoint(x: tx + 5, y: ty))
                tri.line(to: NSPoint(x: tx, y: ty + 4))
                tri.close()
                (selected ? NSColor.white : NSColor(calibratedWhite: 0.08, alpha: 1)).setFill()
                tri.fill()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let old = appHover
        appHover = -1
        for (i, pair) in appRects.enumerated() where pair.0.contains(p) { appHover = i }
        if old != appHover { needsDisplay = true }
        // Hover over "Applications" / "Music" pops a BeOS submenu beside the row.
        let hoveredID = (appHover >= 0 && appHover < appRects.count) ? appRects[appHover].1 : nil
        if hoveredID == "__appfolder__" || hoveredID == "__music__" {
            if hoverMenuID != hoveredID { openHoverSubmenu(id: hoveredID!, rowRect: appRects[appHover].0) }
        } else if hoverMenuID != nil {
            BeOSMenuController.shared.dismissAll(); hoverMenuID = nil
        }
    }

    private func openHoverSubmenu(id: String, rowRect: NSRect) {
        let items = (id == "__music__") ? tvMenuItems() : applicationsMenuItems()
        guard !items.isEmpty else { return }
        let anchor = window?.convertToScreen(convert(rowRect, to: nil)) ?? rowRect
        let ctrl = BeOSMenuController.shared
        ctrl.ignoreClickWindow = window
        ctrl.onDismiss = { [weak self] in self?.hoverMenuID = nil }
        ctrl.show(items, anchor: anchor, openUp: false, openLeft: openMenuLeft)
        hoverMenuID = id
    }

    /// TV streams as a BeOS submenu (BeOS-style folder icon, opens the stream on click).
    private func tvMenuItems() -> [BeOSMenuItem] {
        let icon = cachedDimg("folder-app.png")
        let items = AppSettings.shared.tvBookmarks.map { bm in
            BeOSMenuItem.action(bm.name, icon: icon) {
                NotificationCenter.default.post(name: .init("openTVBookmarkTube"), object: bm.id.uuidString)
            }
        }
        return items.isEmpty ? [.action("No streams") {}] : items
    }
    override func mouseExited(with event: NSEvent) { if appHover != -1 { appHover = -1; needsDisplay = true } }

    private func drawPacManIcon(_ r: NSRect) {
        let d = r.insetBy(dx: 2, dy: 2)
        NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.0, alpha: 1).setFill()
        NSBezierPath(ovalIn: d).fill()
        // mouth wedge (cut in the status-bar colour), opening to the right
        let p = NSBezierPath()
        p.move(to: NSPoint(x: d.midX, y: d.midY))
        p.line(to: NSPoint(x: d.maxX + 1, y: d.midY - d.height * 0.32))
        p.line(to: NSPoint(x: d.maxX + 1, y: d.midY + d.height * 0.32))
        p.close()
        sunkenFace.setFill(); p.fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: d.midX - 1.5, y: d.minY + d.height * 0.22, width: 3, height: 3)).fill()
    }

    private func drawBevel(_ r: NSRect, raised: Bool) {
        let top = raised ? lightBevel : darkBevel
        let bot = raised ? darkBevel : lightBevel
        top.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        bot.setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (r, bid) in appRects where r.contains(p) {
            if bid == "__appfolder__" { AppFolderController.shared.toggle() }
            else if bid == "__music__" { AppFolderController.tv.show() }
            else { AppLauncher.launchOrActivate(bundleID: bid) }
            return
        }
        if clockRect.contains(p) { ClockWidgetController.shared.toggle(); return }
        if cpuRect.contains(p) { CPUMonitorController.shared.toggle(); return }
        if pacRect.contains(p) { PacmanGame.launch(); return }
        if mailRect.contains(p) { AppLauncher.launchOrActivate(bundleID: "com.apple.mail"); return }
        guard headerRect.contains(p) else { return }
        if BeOSMenuController.shared.isOpen { BeOSMenuController.shared.dismissAll(); return }
        menuOpen = true; needsDisplay = true
        // Anchor the menu to the Be logo so it flies out BESIDE the logo.
        let anchor = window?.convertToScreen(convert(headerRect, to: nil)) ?? headerRect
        let ctrl = BeOSMenuController.shared
        ctrl.ignoreClickWindow = window
        ctrl.onDismiss = { [weak self] in self?.menuOpen = false; self?.needsDisplay = true }
        ctrl.show(buildBeMenu(), anchor: anchor, openUp: openMenuUp, openLeft: openMenuLeft)
    }

    // MARK: Be menu contents

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func appIcon(_ app: NSRunningApplication) -> NSImage {
        if let bid = app.bundleIdentifier { return ThemeManager.shared.icon(for: bid, size: 18) }
        return app.icon ?? NSImage(named: NSImage.applicationIconName)!
    }

    /// Persistent apps from the REAL macOS Dock (com.apple.dock → persistent-apps).
    private func macOSDockApps() -> [(bundleID: String?, name: String, url: URL)] {
        guard let arr = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] else { return [] }
        var out: [(String?, String, URL)] = []
        for entry in arr {
            guard let tile = entry["tile-data"] as? [String: Any],
                  let fileData = tile["file-data"] as? [String: Any],
                  let urlStr = fileData["_CFURLString"] as? String,
                  let url = URL(string: urlStr) else { continue }
            let bid = Bundle(url: url)?.bundleIdentifier
            let name = (tile["file-label"] as? String) ?? url.deletingPathExtension().lastPathComponent
            out.append((bid, name, url))
        }
        return out
    }

    /// Applications submenu = the real macOS Dock's apps + currently-running apps (deduped).
    private func applicationsMenuItems() -> [BeOSMenuItem] {
        var seen = Set<String>()
        var result: [BeOSMenuItem] = []
        for (bid, name, url) in macOSDockApps() {
            let key = bid ?? url.path
            guard !seen.contains(key) else { continue }; seen.insert(key)
            let icon = bid.map { ThemeManager.shared.icon(for: $0, size: 18) } ?? NSWorkspace.shared.icon(forFile: url.path)
            result.append(.action(name, icon: icon, bundleID: bid) {
                if let bid = bid { AppLauncher.launchOrActivate(bundleID: bid) } else { NSWorkspace.shared.open(url) }
            })
        }
        for app in runningApps() {
            let key = app.bundleIdentifier ?? (app.localizedName ?? UUID().uuidString)
            guard !seen.contains(key) else { continue }; seen.insert(key)
            result.append(.action(app.localizedName ?? "App", icon: appIcon(app)) { app.activate(options: [.activateAllWindows]) })
        }
        return result.isEmpty ? [.action("None") {}] : result
    }

    private func buildBeMenu() -> [BeOSMenuItem] {
        var items: [BeOSMenuItem] = []
        items.append(.action("About BeOS…", icon: beLogo) { [weak self] in self?.beAbout() })
        items.append(.action("Find…") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) })
        items.append(.action("Show Replicants") {})
        items.append(.action("Configure Be Menu…") { [weak self] in self?.beConfigure() })
        items.append(.separator())
        items.append(.action("Restart") { [weak self] in self?.beRestart() })
        items.append(.action("Shut Down") { [weak self] in self?.beShutDown() })
        items.append(.separator())

        // Running apps (used for both the Applications submenu and Recent Applications).
        let apps = runningApps()
        let appItems: [BeOSMenuItem] = apps.isEmpty
            ? [.action("None") {}]
            : apps.map { app in .action(app.localizedName ?? "App", icon: appIcon(app)) { app.activate(options: [.activateAllWindows]) } }

        // Recent Documents ▸ / Recent Applications ▸ — between Shut Down and Applications.
        let recents = Array(NSDocumentController.shared.recentDocumentURLs.prefix(12))
        let recentItems: [BeOSMenuItem] = recents.isEmpty
            ? [.action("None") {}]
            : recents.map { url in
                let ic = NSWorkspace.shared.icon(forFile: url.path); ic.size = NSSize(width: 18, height: 18)
                return .action(url.lastPathComponent, icon: ic) { NSWorkspace.shared.open(url) }
            }
        items.append(.submenu("Recent Documents", recentItems))
        items.append(.submenu("Recent Applications", appItems))
        items.append(.separator())

        // Applications ▸ — real macOS Dock apps + currently-running apps.
        items.append(.submenu("Applications", icon: dimg("folder-app.png"), applicationsMenuItems()))
        items.append(.separator())

        for (label, url, iconName) in favoriteFolders() {
            let ic = dimg(iconName) ?? NSWorkspace.shared.icon(forFile: url.path)
            items.append(.action(label, icon: ic) { NSWorkspace.shared.open(url) })
        }
        return items
    }

    private func favoriteFolders() -> [(String, URL, String)] {
        let fm = FileManager.default
        var out: [(String, URL, String)] = [("Home", fm.homeDirectoryForCurrentUser, "folder-home.png")]
        if let d = fm.urls(for: .documentDirectory, in: .userDomainMask).first { out.append(("Documents", d, "folder-docs.png")) }
        if let d = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first { out.append(("Downloads", d, "folder-downloads.png")) }
        return out
    }

    private func beAbout() {
        let a = NSAlert(); a.messageText = "About BeOS"
        a.informativeText = "BeOS theme for RetroMac.\n\nThe Media OS — Be Incorporated, 1991–2001.\nRunning on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)."
        if let logo = beLogo { a.icon = logo }
        a.addButton(withTitle: "OK"); a.runModal()
    }
    private func beConfigure() {
        let a = NSAlert(); a.messageText = "Configure Be Menu"
        a.informativeText = "The Be menu's favorites are Applications, Home, Documents and Downloads. Drag-to-configure isn't available in this theme yet."
        a.addButton(withTitle: "OK"); a.runModal()
    }
    private func beRestart() { if confirm("Restart your computer?") { osa("tell application \"System Events\" to restart") } }
    private func beShutDown() { if confirm("Shut down your computer?") { osa("tell application \"System Events\" to shut down") } }
    private func confirm(_ msg: String) -> Bool {
        let a = NSAlert(); a.messageText = msg; a.informativeText = "All applications will be asked to quit."; a.alertStyle = .warning
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel"); return a.runModal() == .alertFirstButtonReturn
    }
    private func osa(_ s: String) { var e: NSDictionary?; NSAppleScript(source: s)?.executeAndReturnError(&e) }
}
