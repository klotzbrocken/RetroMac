import AppKit

/// Solaris 8's CDE Front Panel (Lastenheft 3.0, CDE-01 … CDE-07, CDE-11). It replaces the
/// dock under the "Solaris 8 — CDE" theme: one row of controls at the bottom centre of the
/// main display, each with an arrow above it that opens its subpanel.
///
/// The panel is the original, measured off Solaris 8 (SunOS 5.8, February 2000) screenshots at
/// 1024 × 768: one reference pixel is one point, drawn without smoothing. The picture carries
/// everything that does not move; the clock hands, the date on the calendar and the cpu/disk
/// bars are drawn over it live. Every control opens a real Mac app, folder or setting (TH-08);
/// its tooltip says which.
final class CDEFrontPanelController {

    static let shared = CDEFrontPanelController()
    private var panel: NSPanel?
    private var view: CDEFrontPanelView?
    private var screenObserver: NSObjectProtocol?

    static var isActiveTheme: Bool { ThemeManager.shared.activeTheme?.config.chrome?.style == "cde" }

    func update() {
        guard AppSettings.shared.dockEnabled, Self.isActiveTheme, let theme = ThemeManager.shared.activeTheme else { hide(); return }
        show(theme: theme)
    }

    func hide() {
        view?.stop()
        CDESubpanel.closeAll()
        CDEDesktop.shared.hide(.cde)
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        panel?.orderOut(nil)
        panel = nil
        view = nil
    }

    private func show(theme: ThemeBundle) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: CDEFrontPanelView.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: 5)   // over the windows, like the dock it stands in for
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.title = "Front Panel"   // what VoiceOver calls it; nothing shows it
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.hidesOnDeactivate = false
            panel = p
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reposition()
            }
        }
        let v = CDEFrontPanelView(theme: theme)
        panel?.contentView = v
        view?.stop()
        view = v
        reposition()
        panel?.orderFrontRegardless()
        v.start()
        CDEDesktop.shared.show(.cde)
    }

    /// "Minimize/Restore Front Panel" in the Workspace Menu's Windows cascade.
    func toggleMinimized() {
        guard let panel else { return }
        if panel.isVisible { CDESubpanel.closeAll(); panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// Bottom centre of the main display (CDE-01), at its natural width.
    private func reposition() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        let s = CDEFrontPanelView.size
        panel.setFrame(NSRect(x: (f.midX - s.width / 2).rounded(), y: f.minY, width: s.width, height: s.height), display: true)
    }

    /// The panel's frame on screen, for the subpanels to stand on.
    var frame: NSRect? { panel?.frame }
}

// MARK: - The controls

/// One control of the panel: where it sits (panel points, origin top-left), what it opens and
/// which subpanel its arrow shows.
struct CDEControl {
    let id: String
    let cell: NSRect          // the icon cell, below the arrow row
    let tooltip: String
    let action: () -> Void
    var subpanel: CDESubpanel.Kind? = nil
}

enum CDEActions {
    static func app(_ bundleID: String) -> () -> Void {
        { if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { NSSound.beep() } }
    }
    static func open(_ url: URL) -> () -> Void { { NSWorkspace.shared.open(url) } }
    static func settings(_ pane: String) -> () -> Void { open(URL(string: "x-apple.systempreferences:\(pane)")!) }
    static let home = URL(fileURLWithPath: NSHomeDirectory())
    static let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")
    static func defaultApp(for url: String) -> () -> Void {
        { if let u = URL(string: url), let app = NSWorkspace.shared.urlForApplication(toOpen: u) {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        } else { NSSound.beep() } }
    }
    static func missionControl() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }
}

// MARK: - View

final class CDEFrontPanelView: NSView {
    static let size = NSSize(width: 956, height: 86)

    /// Measured cells (x ranges of the icon cells, panel points). The arrow row is y 4…18,
    /// the icons y 20…80.
    private static let arrowRow: ClosedRange<CGFloat> = 4...18
    private static func cell(_ x0: CGFloat, _ x1: CGFloat) -> NSRect { NSRect(x: x0, y: 20, width: x1 - x0 + 1, height: 60) }

    private let theme: ThemeBundle
    private var controls: [CDEControl] = []
    private let background: NSImage?
    private let calendarPage: NSImage?
    private var timer: Timer?
    private var pressed: String?
    private var lastTicks: SystemSampler.Ticks?
    private var cpu: Double = 0
    private var disk: Double = 0

    // Workspace switch, lock and EXIT (panel points).
    private static let workspaces = NSRect(x: 350, y: 10, width: 254, height: 66)
    private static let lock = NSRect(x: 315, y: 6, width: 24, height: 26)
    private static let exit = NSRect(x: 606, y: 44, width: 32, height: 32)
    private static let fixed: [(label: String, rect: NSRect, action: () -> Void)] = [
        ("Workspaces", workspaces, CDEActions.missionControl),                          // TH-12: one way in to the workspace overview
        ("Lock screen", lock, { ScreensaverController.shared.start() }),
        ("Exit", exit, { AppDelegate.shared?.launcherDisableTheme() }),                // CDE-11: "Exit" ends the theme, never the session
    ]

    init(theme: ThemeBundle) {
        self.theme = theme
        background = theme.iconResource("cde_frontpanel.png").flatMap { NSImage(contentsOf: $0) }
        calendarPage = theme.iconResource("cde_calendar_blank.png").flatMap { NSImage(contentsOf: $0) }
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        controls = Self.makeControls()
        registerForDraggedTypes([.fileURL])
        for c in controls { addToolTip(c.cell, owner: c.tooltip as NSString, userData: nil) }
        addToolTip(Self.workspaces, owner: "Workspaces: opens Mission Control (macOS Spaces)" as NSString, userData: nil)
        addToolTip(Self.lock, owner: "Lock: starts the screen saver" as NSString, userData: nil)
        addToolTip(Self.exit, owner: "Exit: turns the Solaris theme off" as NSString, userData: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// The Clock app, or RetroMac's clock widget where there is none.
    static func openClock() {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") != nil {
            CDEActions.app("com.apple.clock")()
        } else { ClockWidgetController.shared.userShow() }
    }

    private static func makeControls() -> [CDEControl] {
        [
            CDEControl(id: "clock", cell: cell(26, 84), tooltip: "Clock", action: openClock, subpanel: .links),
            CDEControl(id: "calendar", cell: cell(86, 142), tooltip: "Calendar",
                       action: CDEActions.app("com.apple.iCal"), subpanel: .cards),
            CDEControl(id: "files", cell: cell(144, 200), tooltip: "File Manager: your home folder in the Finder",
                       action: CDEActions.open(CDEActions.home), subpanel: .files),
            CDEControl(id: "texteditor", cell: cell(202, 258), tooltip: "Text Editor: TextEdit",
                       action: CDEActions.app("com.apple.TextEdit"), subpanel: .applications),
            CDEControl(id: "mail", cell: cell(260, 313), tooltip: "Mail: your mail app",
                       action: CDEActions.defaultApp(for: "mailto:"), subpanel: .mail),
            CDEControl(id: "printer", cell: cell(642, 697), tooltip: "Printer: Printers & Scanners",
                       action: CDEActions.settings("com.apple.Print-Scan-Settings.extension"), subpanel: .printers),
            CDEControl(id: "style", cell: cell(699, 753), tooltip: "Style Manager: Appearance settings",
                       action: CDEActions.settings("com.apple.Appearance-Settings.extension"), subpanel: .tools),
            CDEControl(id: "perf", cell: cell(755, 813), tooltip: "Performance Meter: Activity Monitor",
                       action: CDEActions.app("com.apple.ActivityMonitor"), subpanel: .hosts),
            CDEControl(id: "help", cell: cell(815, 871), tooltip: "Help: about this theme",
                       action: { ThemeReadmeController.shared.showForActiveTheme() }, subpanel: .help),
            CDEControl(id: "trash", cell: cell(873, 929), tooltip: "Trash: drop files here to move them to the Trash",
                       action: CDEActions.open(CDEActions.trash), subpanel: .trash),
        ]
    }

    // MARK: Live parts

    func start() {
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        sample()
        setNeedsDisplay(controls.first(where: { $0.id == "clock" })!.cell)
        setNeedsDisplay(controls.first(where: { $0.id == "perf" })!.cell)
        setNeedsDisplay(controls.first(where: { $0.id == "calendar" })!.cell)
    }

    /// cpu: busy share since the last second; disk: how full the startup disk is.
    private func sample() {
        if let now = SystemSampler.totalTicks() {
            if let last = lastTicks, let l = SystemSampler.load(from: last, to: now) { cpu = l.busy / 100 }
            lastTicks = now
        }
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacity, total > 0 {
            disk = 1 - Double(free) / Double(total)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        background?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        drawDate()
        drawClockHands()
        drawMeters()
        if let id = pressed, let c = controls.first(where: { $0.id == id }) { drawSunken(c.cell) }
    }

    /// The calendar page shows today's month and day, as the Solaris one did ("Sep" / "8").
    private func drawDate() {
        calendarPage?.draw(in: NSRect(x: 95, y: 27, width: 36, height: 45), from: .zero, operation: .sourceOver,
                           fraction: 1, respectFlipped: true, hints: nil)
        let now = Date()
        let month = DateFormatter(); month.dateFormat = "MMM"; month.locale = Locale(identifier: "en_US")
        let font = NSFont(name: "LucidaGrande", size: 15) ?? .systemFont(ofSize: 15)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        for (text, y) in [(month.string(from: now), CGFloat(31)), ("\(Calendar.current.component(.day, from: now))", 50)] {
            let s = text as NSString
            let w = s.size(withAttributes: attrs).width
            s.draw(at: NSPoint(x: (113 - w / 2).rounded(), y: y), withAttributes: attrs)
        }
    }

    /// Red hands with a white spine, from the hub of the globe (measured at 55, 50).
    private func drawClockHands() {
        let c = NSPoint(x: 55, y: 50)
        let cal = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = Double(cal.minute ?? 0)
        let hour = Double((cal.hour ?? 0) % 12) + minute / 60
        func hand(_ fraction: Double, _ length: CGFloat) {
            let a = fraction * 2 * .pi
            let end = NSPoint(x: c.x + CGFloat(sin(a)) * length, y: c.y - CGFloat(cos(a)) * length)
            let p = NSBezierPath(); p.move(to: c); p.line(to: end)
            p.lineCapStyle = .square
            NSColor(srgbRed: 1, green: 0x10 / 255, blue: 0x42 / 255, alpha: 1).setStroke(); p.lineWidth = 4; p.stroke()
            NSColor.white.setStroke(); p.lineWidth = 1; p.stroke()
        }
        hand(hour / 12, 13)
        hand(minute / 60, 20)
    }

    /// The cpu and disk bars above their labels (cpu x 760…776, disk x 785…807, y 60…62).
    private func drawMeters() {
        NSColor(srgbRed: 0x52 / 255, green: 0x52 / 255, blue: 1, alpha: 1).setFill()
        NSRect(x: 760, y: 60, width: (17 * min(1, cpu)).rounded(), height: 3).fill()
        NSRect(x: 785, y: 60, width: (23 * min(1, disk)).rounded(), height: 3).fill()
    }

    /// A pressed control: the cell's bevel turned inwards.
    private func drawSunken(_ r: NSRect) {
        NSColor(srgbRed: 0x5A / 255, green: 0x63 / 255, blue: 0x6B / 255, alpha: 1).setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        NSColor(srgbRed: 0xDE / 255, green: 0xDE / 255, blue: 0xE7 / 255, alpha: 1).setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func control(at p: NSPoint) -> CDEControl? {
        controls.first { $0.cell.contains(p) }
    }
    private func arrow(at p: NSPoint) -> CDEControl? {
        guard Self.arrowRow.contains(p.y) else { return nil }
        return controls.first { p.x >= $0.cell.minX && p.x <= $0.cell.maxX }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let c = control(at: p) { pressed = c.id; setNeedsDisplay(c.cell) }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let was = pressed; pressed = nil; needsDisplay = true
        if let c = arrow(at: p), let kind = c.subpanel {
            CDESubpanel.toggle(kind, above: c.cell, in: self)
        } else if let c = control(at: p), c.id == was {
            Self.run(c)
        } else if let f = Self.fixed.first(where: { $0.rect.contains(p) }) {
            f.action()
        }
    }

    private static func run(_ c: CDEControl) {
        CDESubpanel.closeAll()
        c.action()
    }

    // MARK: VoiceOver

    /// The panel is one picture, so VoiceOver gets each control, the arrow above it that opens
    /// its subpanel, and the workspace switch, lock and Exit, pressed as a click would.
    /// Kept here because the accessibility server keeps no reference to them.
    private var axParts: [AccessibleHotspot] = []
    /// A group, so VoiceOver asks it for the controls it paints: a view with no subviews that
    /// is no element of its own was skipped, and the window read "content is empty".
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityChildren() -> [Any]? {
        var parts: [AccessibleHotspot] = []
        for c in controls {
            let name = c.tooltip.components(separatedBy: ":")[0]   // "File Manager: your home folder…" → "File Manager"
            parts.append(AccessibleHotspot(in: self, label: name, rect: c.cell) { Self.run(c) })
            if let kind = c.subpanel {
                let arrow = NSRect(x: c.cell.minX, y: Self.arrowRow.lowerBound, width: c.cell.width,
                                   height: Self.arrowRow.upperBound - Self.arrowRow.lowerBound + 1)
                parts.append(AccessibleHotspot(in: self, label: "\(name) subpanel", rect: arrow) { [weak self] in
                    guard let self else { return }
                    CDESubpanel.toggle(kind, above: c.cell, in: self)
                })
            }
        }
        for f in Self.fixed { parts.append(AccessibleHotspot(in: self, label: f.label, rect: f.rect, press: f.action)) }
        axParts = parts
        return parts
    }

    // MARK: Drop on the Trash (CDE-06: the one drop zone with a plain, safe meaning)

    private var trashCell: NSRect { controls.first { $0.id == "trash" }!.cell }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dragOperation(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dragOperation(sender) }
    private func dragOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        trashCell.contains(convert(sender.draggingLocation, from: nil)) ? .delete : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard trashCell.contains(convert(sender.draggingLocation, from: nil)),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        NSWorkspace.shared.recycle(urls)
        return true
    }
}
