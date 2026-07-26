import AppKit

/// NeXTSTEP "application icons": every running app shows up as a 64×64 icon tile that floats loose
/// on the workspace and can be DRAGGED anywhere (NeXT let you position each app icon freely). Each
/// icon is its own small panel — a single full-screen panel would swallow every click — so clicks
/// outside the tiles pass through to the desktop. Positions persist per bundle id; a click without
/// a drag activates the app. Fresh apps cascade in from the bottom-left.
final class NextRunningAppsController {

    static let shared = NextRunningAppsController()
    private var panels: [String: NextAppIconPanel] = [:]   // bundleID → panel
    private var obs: [NSObjectProtocol] = []
    private let posKey = "nextAppIconPositions"
    private init() {}

    func update() {
        guard let theme = ThemeManager.shared.activeTheme, theme.config.isNextStep else { hide(); return }
        if obs.isEmpty {
            let nc = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                obs.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.rebuild() })
            }
        }
        rebuild()
    }

    func hide() {
        obs.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        obs.removeAll()
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    private func rebuild() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && $0.bundleIdentifier != "com.apple.finder"
        }
        let want = Set(apps.compactMap { $0.bundleIdentifier })
        // Remove panels for apps that quit.
        for (bid, panel) in panels where !want.contains(bid) { panel.orderOut(nil); panels.removeValue(forKey: bid) }
        // Add panels for new apps.
        var index = panels.count
        for app in apps {
            guard let bid = app.bundleIdentifier, panels[bid] == nil, let sysIcon = app.icon else { continue }
            let overridePath = iconOverride(bid)
            let icon = overridePath.flatMap { NSImage(contentsOfFile: $0) } ?? sysIcon
            // Real app icons sit inset on the silver tile; a "Change Icon…" pick fills the whole
            // tile only when "Ganze Fläche füllen" was set (full-tile Fleet art).
            let fillWhole = overridePath != nil ? iconFill(bid) : false
            let origin = savedPosition(bid) ?? defaultPosition(index: index)
            index += 1
            let panel = NextAppIconPanel(app: app, icon: icon, fillWhole: fillWhole, origin: origin,
                                         onMoved: { [weak self] o in self?.savePosition(bid, o) },
                                         onIconChanged: { [weak self] path, fill in self?.setIconOverride(bid, path); self?.setIconFill(bid, fill); self?.reloadIcons() })
            panel.orderFront(nil)
            panels[bid] = panel
        }
    }

    /// Rebuild panels so a changed icon override takes effect immediately.
    private func reloadIcons() {
        panels.values.forEach { $0.orderOut(nil) }; panels.removeAll(); rebuild()
    }

    private func iconOverride(_ bid: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: "nextRunIconOverrides") as? [String: String])?[bid]
    }
    private func setIconOverride(_ bid: String, _ path: String) {
        var d = (UserDefaults.standard.dictionary(forKey: "nextRunIconOverrides") as? [String: String]) ?? [:]
        d[bid] = path
        UserDefaults.standard.set(d, forKey: "nextRunIconOverrides")
    }
    private func iconFill(_ bid: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: "nextRunIconFill") as? [String: Bool])?[bid] ?? true
    }
    private func setIconFill(_ bid: String, _ v: Bool) {
        var d = (UserDefaults.standard.dictionary(forKey: "nextRunIconFill") as? [String: Bool]) ?? [:]
        d[bid] = v
        UserDefaults.standard.set(d, forKey: "nextRunIconFill")
    }

    // Cascade fresh icons along the very bottom-left of the screen, on the drag grid.
    private func defaultPosition(index: Int) -> NSPoint {
        guard let f = NSScreen.main?.visibleFrame else { return NSPoint(x: 20, y: 20) }
        return NSPoint(x: f.minX + CGFloat(index) * NextAppIconPanel.gridPitch, y: f.minY)
    }

    private func savedPosition(_ bid: String) -> NSPoint? {
        guard let all = UserDefaults.standard.dictionary(forKey: posKey) as? [String: [Double]],
              let xy = all[bid], xy.count == 2 else { return nil }
        return NSPoint(x: xy[0], y: xy[1])
    }
    private func savePosition(_ bid: String, _ o: NSPoint) {
        var all = (UserDefaults.standard.dictionary(forKey: posKey) as? [String: [Double]]) ?? [:]
        all[bid] = [Double(o.x), Double(o.y)]
        UserDefaults.standard.set(all, forKey: posKey)
    }
}

/// One draggable 64×64 NeXT app-icon tile.
final class NextAppIconPanel: NSPanel {
    static let gridPitch: CGFloat = 66   // tile (64) + gap; NeXT snapped icons to a fixed grid

    private let app: NSRunningApplication
    private let onMoved: (NSPoint) -> Void
    private let onIconChanged: (String, Bool) -> Void

    init(app: NSRunningApplication, icon: NSImage, fillWhole: Bool, origin: NSPoint,
         onMoved: @escaping (NSPoint) -> Void, onIconChanged: @escaping (String, Bool) -> Void) {
        self.app = app; self.onMoved = onMoved; self.onIconChanged = onIconChanged
        super.init(contentRect: NSRect(x: origin.x, y: origin.y, width: 64, height: 64),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: 5)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        contentView = NextAppIconView(icon: icon, fillWhole: fillWhole)
    }

    override var canBecomeKey: Bool { false }

    // Manual drag so a plain click (no movement) activates the app instead of moving it.
    private var dragStart: NSPoint = .zero
    private var winStart: NSPoint = .zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        winStart = frame.origin
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStart.x, dy = now.y - dragStart.y
        if abs(dx) > 3 || abs(dy) > 3 { didDrag = true }
        setFrameOrigin(snapped(NSPoint(x: winStart.x + dx, y: winStart.y + dy)))   // snap live to the grid
    }
    override func mouseUp(with event: NSEvent) {
        if didDrag { setFrameOrigin(snapped(frame.origin)); onMoved(frame.origin) }
        else { raiseApp() }
    }

    /// Bring the app fully to the front. `NSRunningApplication.activate` alone does NOT
    /// surface a background app's windows from an LSUIElement agent like RetroMac — the
    /// system Dock and the Win98/XP taskbar only work because they raise the front window
    /// via Accessibility first. Reuse that exact proven path (de-miniaturize, AX-raise,
    /// then activate) instead of a plain activate.
    private func raiseApp() {
        app.unhide()
        guard let bid = app.bundleIdentifier else {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows]); return
        }
        MinimizedWindowTracker.shared.restoreWindows(for: bid)
        AppLauncher.launchOrActivate(bundleID: bid)
    }

    // Right-click: Quit the app, or change its tile icon.
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let name = app.localizedName ?? "Program"
        let quit = NSMenuItem(title: "Quit \(name)", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)
        let change = NSMenuItem(title: "Change Icon\u{2026}", action: #selector(changeIcon), keyEquivalent: "")
        change.target = self; menu.addItem(change)
        NSMenu.popUpContextMenu(menu, with: event, for: contentView ?? NSView())
    }
    @objc private func quitApp() { app.terminate() }
    @objc private func changeIcon() { NextDockView.pickIcon { [weak self] path, fill in self?.onIconChanged(path, fill) } }

    /// Snap an origin to the NeXT icon grid, measured from the screen's bottom-left corner.
    private func snapped(_ o: NSPoint) -> NSPoint {
        guard let f = (screen ?? NSScreen.main)?.visibleFrame else { return o }
        let p = Self.gridPitch
        return NSPoint(x: max(f.minX, f.minX + (round((o.x - f.minX) / p) * p)),
                       y: max(f.minY, f.minY + (round((o.y - f.minY) / p) * p)))
    }
}

final class NextAppIconView: NSView {
    private let icon: NSImage
    private let fillWhole: Bool
    init(icon: NSImage, fillWhole: Bool) {
        self.icon = icon; self.fillWhole = fillWhole
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        wantsLayer = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Silver NeXT dock tile; a full-tile Fleet pick ("Ganze Fläche füllen") fills it edge-to-
        // edge, a real app icon or inset pick sits inset so the silver shows around it.
        NeXTChrome.dockTile(bounds, flipped: false, in: ctx)
        NextDockView.composite(icon, on: bounds, fillWhole: fillWhole, in: ctx)
    }
}
