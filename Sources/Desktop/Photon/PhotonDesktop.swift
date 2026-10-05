import AppKit

/// QNX 6.2.1's Photon desktop (Lastenheft 3.0, QNX-01 … QNX-09): the shelf down the right edge
/// and the taskbar along the bottom, two panels of their own. Measured off the QNX 6.2.1 (NC)
/// screenshots at 800 × 600, one reference pixel one point (docs/reference). The taskbar runs
/// the full width with the clock in its right corner; the shelf stands on the taskbar, so the
/// corner has one owner (QNX-04).
final class PhotonDesktopController {
    static let shared = PhotonDesktopController()
    private var shelf: NSPanel?
    private var taskbar: NSPanel?
    private var observers: [NSObjectProtocol] = []

    static var isActiveTheme: Bool { ThemeManager.shared.activeTheme?.config.chrome?.style == "photon" }

    func update() {
        guard AppSettings.shared.dockEnabled, Self.isActiveTheme, let theme = ThemeManager.shared.activeTheme else { hide(); return }
        show(theme: theme)
    }

    func hide() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        (shelf?.contentView as? PhotonShelfView)?.stop()
        (taskbar?.contentView as? PhotonTaskbarView)?.stop()
        shelf?.orderOut(nil); taskbar?.orderOut(nil)
        shelf = nil; taskbar = nil
    }

    private static func panel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: 5)   // over the windows, like the dock it stands in for
        p.isOpaque = true
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        return p
    }

    private func show(theme: ThemeBundle) {
        if shelf == nil {
            let s = Self.panel(), t = Self.panel()
            s.contentView = PhotonShelfView(theme: theme)
            t.contentView = PhotonTaskbarView(theme: theme)
            shelf = s; taskbar = t
            let nc = NotificationCenter.default
            observers = [
                nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.layout() },
                nc.addObserver(forName: .windowsChanged, object: nil, queue: .main) { [weak self] _ in
                    (self?.taskbar?.contentView as? PhotonTaskbarView)?.reload()
                },
            ]
        }
        layout()
        taskbar?.orderFrontRegardless(); shelf?.orderFrontRegardless()   // the shelf over the taskbar's edge
        (shelf?.contentView as? PhotonShelfView)?.start()
        (taskbar?.contentView as? PhotonTaskbarView)?.start()
    }

    /// The taskbar across the bottom of the main display, the shelf from the top of the visible
    /// area down to the clock, at the right edge.
    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        let barH = PhotonTaskbarView.height, shelfW = PhotonShelfView.width, clockH = barH - 6
        taskbar?.setFrame(NSRect(x: f.minX, y: f.minY, width: f.width, height: barH), display: true)
        // The shelf comes down to the clock, over the taskbar's 6 pt top edge, as on 6.2.1.
        shelf?.setFrame(NSRect(x: f.maxX - shelfW, y: f.minY + clockH, width: shelfW, height: f.height - clockH), display: true)
    }

    /// The area the two leave free, for maximised windows.
    var reserved: (right: CGFloat, bottom: CGFloat)? { shelf == nil ? nil : (PhotonShelfView.width, PhotonTaskbarView.height) }
}

/// Photon's greys, measured.
enum PhotonColors {
    static let white = NSColor.white
    static let face = NSColor.fromHex("#D9D9D9")
    static let headerFace = NSColor.fromHex("#DBDBDB")
    static let frameFace = NSColor.fromHex("#D8D8D8")
    static let well = NSColor.fromHex("#CCCCCC")
    static let shade = NSColor.fromHex("#A7A7A7")
    static let headerShade = NSColor.fromHex("#A9A9A9")
    static let frameShade = NSColor.fromHex("#A6A6A6")
    static let line = NSColor.fromHex("#4B4B4B")
    static let toggle = NSColor.fromHex("#C7C7C7")
    static let glyph = NSColor.fromHex("#606060")
    static let trough = NSColor.fromHex("#C0C0C0")
    static let troughShade = NSColor.fromHex("#8E8E8E")
    static let barShade = NSColor.fromHex("#8D8D8D")
    static let barEmpty = NSColor.fromHex("#BCBCBC")
    static let barFill = NSColor.fromHex("#B5C4B0")
    static let barFillLight = NSColor.fromHex("#DDECD8")
    static let barFillShade = NSColor.fromHex("#8D9C88")
    static let activeTask = NSColor.fromHex("#F9F4E4")

    static let label = NSFont(name: "LucidaGrande", size: 12) ?? .systemFont(ofSize: 12)
    static let header = NSFont(name: "LucidaGrande-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)
    static let clock = NSFont(name: "LucidaGrande", size: 11) ?? .systemFont(ofSize: 11)

    /// A 1 pt bevel in a flipped view: `tl` along the top and left, `br` along the bottom and right.
    static func bevel(_ r: NSRect, _ tl: NSColor, _ br: NSColor) {
        tl.setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill(); NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        br.setFill(); NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill(); NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }

    /// The 6 pt frame the shelf and the taskbar show on their open side: dark, white, two of
    /// face, grey, dark. `vertical` runs it down the left edge, otherwise along the top.
    static func panelFrame(_ r: NSRect, vertical: Bool) {
        for (i, c) in [line, white, frameFace, frameFace, frameShade, line].enumerated() {
            c.setFill()
            (vertical ? NSRect(x: r.minX + CGFloat(i), y: r.minY, width: 1, height: r.height)
                      : NSRect(x: r.minX, y: r.minY + CGFloat(i), width: r.width, height: 1)).fill()
        }
    }

    static func text(_ s: String, at p: NSPoint, font: NSFont, in width: CGFloat? = nil) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        if let width {
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
            attrs[.paragraphStyle] = para
            (s as NSString).draw(in: NSRect(x: p.x, y: p.y, width: width, height: font.boundingRectForFont.height + 2), withAttributes: attrs)
        } else {
            (s as NSString).draw(at: p, withAttributes: attrs)
        }
    }
}

// MARK: - Shelf (QNX-03, QNX-07, QNX-08, QNX-09)

final class PhotonShelfView: NSView {
    static let width: CGFloat = 135
    static let frameW: CGFloat = 6, headerH: CGFloat = 19, rowH: CGFloat = 25, monitorH: CGFloat = 62

    struct Item { let title: String; let icon: String; let action: () -> Void }
    enum Body { case items([Item]), monitor, image(String, action: () -> Void) }
    struct Group { let id: String; let title: String; let body: Body }

    private let theme: ThemeBundle
    private var groups: [Group] = []
    private var images: [String: NSImage] = [:]
    private var scroll: CGFloat = 0
    private var pressed: (group: String, row: Int)?
    private var timer: Timer?
    private let sampler = SystemSampler()
    private var cpu = 0.0, memory = 0.0, swap = 0.0, commit = 0.0

    init(theme: ThemeBundle) {
        self.theme = theme
        super.init(frame: .zero)
        groups = Self.makeGroups()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func image(_ name: String) -> NSImage? {
        if let i = images[name] { return i }
        let i = theme.iconResource("\(name).png").flatMap { NSImage(contentsOf: $0) }
        images[name] = i
        return i
    }

    /// The shelf of QNX 6.2.1 in its order, each launcher on a real Mac target (QNX-07). The
    /// Dialer is left out: there is no modem to dial (QNX-07, nothing historic shown as working).
    static func makeGroups() -> [Group] {
        let app = CDEActions.app, settings = CDEActions.settings
        return [
            Group(id: "applications", title: "Applications", body: .items([
                Item(title: "Welcome", icon: "qnx_welcome", action: { ThemeReadmeController.shared.showForActiveTheme() }),
                Item(title: "Help", icon: "qnx_help", action: app("com.apple.tips")),
                Item(title: "Installer", icon: "qnx_installer", action: app("com.apple.AppStore")),
                Item(title: "File Manager", icon: "qnx_fileman", action: CDEActions.open(CDEActions.home)),
                Item(title: "Voyager", icon: "qnx_voyager", action: CDEActions.defaultApp(for: "https://")),
                Item(title: "Editor", icon: "qnx_editor", action: app("com.apple.TextEdit")),
                Item(title: "Terminal", icon: "qnx_terminal", action: app("com.apple.Terminal")),
                Item(title: "Media Player", icon: "qnx_mediaplayer", action: app("com.apple.QuickTimePlayerX")),
            ])),
            Group(id: "utilities", title: "Utilities", body: .items([
                Item(title: "Find...", icon: "qnx_find", action: CDEActions.open(CDEActions.home)),
                Item(title: "Report Bug", icon: "qnx_reportbug",
                     action: CDEActions.open(URL(string: "https://github.com/klotzbrocken/RetroMac/issues")!)),
                Item(title: "Connect...", icon: "qnx_connect", action: settings("com.apple.Network-Settings.extension")),
                Item(title: "Calculator", icon: "qnx_calculator", action: app("com.apple.calculator")),
            ])),
            Group(id: "configure", title: "Configure", body: .items([
                Item(title: "Network", icon: "qnx_network", action: settings("com.apple.Network-Settings.extension")),
                Item(title: "Mouse", icon: "qnx_mouse", action: settings("com.apple.Mouse-Settings.extension")),
                Item(title: "Graphics", icon: "qnx_graphics", action: settings("com.apple.Displays-Settings.extension")),
                Item(title: "Appearance", icon: "qnx_appearance", action: settings("com.apple.Appearance-Settings.extension")),
                Item(title: "Screen Saver", icon: "qnx_screensaver", action: settings("com.apple.ScreenSaver-Settings.extension")),
                Item(title: "Time & Date", icon: "qnx_timedate", action: settings("com.apple.Date-Time-Settings.extension")),
                Item(title: "Shelf", icon: "qnx_shelf", action: { AppDelegate.shared?.launcherOpenSettings() }),
                Item(title: "Localization", icon: "qnx_localization", action: settings("com.apple.Localization-Settings.extension")),
            ])),
            Group(id: "monitor", title: "System Monitor", body: .monitor),
            Group(id: "cdplayer", title: "CD Player", body: .image("qnx_cdplayer", action: app("com.apple.Music"))),
            Group(id: "worldview", title: "World View", body: .image("qnx_worldview", action: CDEActions.missionControl)),
        ]
    }

    // MARK: Collapsed groups, kept per theme (QNX-03)

    private static let collapsedKey = "photonShelfCollapsed"
    /// The groups closed the first time, as the 6.2.1 shelf came up.
    static let collapsedByDefault: Set<String> = ["utilities", "cdplayer", "worldview"]
    static var collapsed: Set<String> {
        get { (UserDefaults.standard.stringArray(forKey: collapsedKey)).map(Set.init) ?? collapsedByDefault }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: collapsedKey) }
    }

    private func bodyHeight(_ g: Group) -> CGFloat {
        switch g.body {
        case .items(let items): return CGFloat(items.count) * Self.rowH
        case .monitor: return Self.monitorH
        case .image(let name, _): return image(name)?.size.height ?? 0
        }
    }

    /// Every group's header and body rectangles, top to bottom, shifted by the scroll.
    private func layout() -> [(group: Group, header: NSRect, body: NSRect?)] {
        var y = -scroll
        let x = Self.frameW, w = bounds.width - Self.frameW
        let closed = Self.collapsed
        return groups.map { g in
            let header = NSRect(x: x, y: y, width: w, height: Self.headerH)
            y += Self.headerH
            var body: NSRect?
            if !closed.contains(g.id) {
                body = NSRect(x: x, y: y, width: w, height: bodyHeight(g))
                y += body!.height
            }
            return (g, header, body)
        }
    }

    private var contentHeight: CGFloat { groups.reduce(0) { $0 + Self.headerH + (Self.collapsed.contains($1.id) ? 0 : bodyHeight($1)) } }

    // MARK: Live values (QNX-08): once a second, only while shown

    func start() {
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.window?.occlusionState.contains(.visible) == true,
                  !Self.collapsed.contains("monitor") else { return }
            self.sample(); self.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func sample() {
        let s = sampler.next()
        cpu = s.cpu / 100
        memory = s.physTotalK > 0 ? 1 - Double(s.physAvailK) / Double(s.physTotalK) : 0
        commit = s.commitLimitK > 0 ? Double(s.commitK) / Double(s.commitLimitK) : 0
        let sw = SystemSampler.swapUsage()
        swap = sw.total > 0 ? Double(sw.used) / Double(sw.total) : 0
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.fromHex("#D9D9D9").setFill(); bounds.fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        for (g, header, body) in layout() {
            drawHeader(g, header)
            guard let body else { continue }
            switch g.body {
            case .items(let items):
                for (i, item) in items.enumerated() {
                    drawItem(item, NSRect(x: body.minX, y: body.minY + CGFloat(i) * Self.rowH, width: body.width, height: Self.rowH),
                             pressed: pressed?.group == g.id && pressed?.row == i)
                }
            case .monitor: drawMonitor(body)
            case .image(let name, _): image(name)?.draw(in: body, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        PhotonColors.panelFrame(NSRect(x: 0, y: 0, width: Self.frameW, height: bounds.height), vertical: true)
    }

    private func drawHeader(_ g: Group, _ r: NSRect) {
        PhotonColors.headerFace.setFill(); r.fill()
        PhotonColors.bevel(r, PhotonColors.white, PhotonColors.headerShade)
        let box = NSRect(x: r.minX + 1, y: r.minY + 1, width: 15, height: r.height - 2)
        PhotonColors.toggle.setFill(); box.fill()
        PhotonColors.glyph.setFill()
        NSRect(x: box.midX - 3, y: box.midY - 1, width: 6, height: 2).fill()
        if Self.collapsed.contains(g.id) { NSRect(x: box.midX - 1, y: box.midY - 3, width: 2, height: 6).fill() }
        PhotonColors.text(g.title, at: NSPoint(x: r.minX + 20, y: r.minY + 2), font: PhotonColors.header)
    }

    private func drawItem(_ item: Item, _ r: NSRect, pressed: Bool) {
        PhotonColors.face.setFill(); r.fill()
        let well = NSRect(x: r.minX + 1, y: r.minY + 1, width: 28, height: r.height - 2)
        PhotonColors.well.setFill(); well.fill()
        PhotonColors.bevel(r, pressed ? PhotonColors.shade : PhotonColors.white, pressed ? PhotonColors.white : PhotonColors.shade)
        image(item.icon)?.draw(in: NSRect(x: well.minX, y: well.minY, width: 28, height: 23), from: .zero, operation: .sourceOver,
                               fraction: 1, respectFlipped: true, hints: nil)
        PhotonColors.text(item.title, at: NSPoint(x: r.minX + 34, y: r.minY + 4), font: PhotonColors.label, in: r.width - 38)
    }

    /// CPU, memory, then swap and commit as two thin bars, each in a sunk box (x 29 … 130).
    private func drawMonitor(_ r: NSRect) {
        PhotonColors.face.setFill(); r.fill()
        PhotonColors.bevel(r, PhotonColors.white, PhotonColors.shade)
        let rows: [(String?, CGFloat, CGFloat, Double)] = [("qnx_mon_cpu", 4, 16, cpu), ("qnx_mon_mem", 23, 16, memory),
                                                          ("qnx_mon_proc", 42, 7, swap), (nil, 50, 7, commit)]
        for (icon, dy, h, value) in rows {
            if let icon { image(icon)?.draw(in: NSRect(x: r.minX + 1, y: r.minY + dy - 3, width: 20, height: 19), from: .zero,
                                            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            let box = NSRect(x: r.minX + 23, y: r.minY + dy, width: 102, height: h)
            PhotonColors.line.setFill(); box.frame()
            PhotonColors.barShade.setFill(); NSRect(x: box.minX + 1, y: box.minY + 1, width: box.width - 2, height: 1).fill()
            NSRect(x: box.minX + 1, y: box.minY + 1, width: 1, height: box.height - 2).fill()
            PhotonColors.barEmpty.setFill(); NSRect(x: box.minX + 2, y: box.minY + 2, width: box.width - 3, height: box.height - 3).fill()
            let w = ((box.width - 3) * CGFloat(min(1, max(0, value)))).rounded()
            guard w > 2 else { continue }
            let fill = NSRect(x: box.minX + 1, y: box.minY + 1, width: w, height: box.height - 2)
            PhotonColors.barFill.setFill(); fill.fill()
            PhotonColors.bevel(fill, PhotonColors.barFillLight, PhotonColors.barFillShade)
        }
    }

    // MARK: Mouse

    private func hit(_ p: NSPoint) -> (group: Group, row: Int?)? {
        for (g, header, body) in layout() {
            if header.contains(p) { return (g, nil) }
            if let body, body.contains(p) {
                if case .items = g.body { return (g, Int((p.y - body.minY) / Self.rowH)) }
                return (g, 0)
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let h = hit(convert(event.locationInWindow, from: nil)), let row = h.row else { return }
        if case .items = h.group.body { pressed = (h.group.id, row); needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        let was = pressed
        pressed = nil; needsDisplay = true
        guard let h = hit(convert(event.locationInWindow, from: nil)) else { return }
        switch (h.group.body, h.row) {
        case (_, nil):
            var c = Self.collapsed
            if c.contains(h.group.id) { c.remove(h.group.id) } else { c.insert(h.group.id) }
            Self.collapsed = c
            clampScroll()
        case (.items(let items), let row?) where was?.group == h.group.id && was?.row == row && row < items.count:
            items[row].action()
        case (.image(_, let action), _?): action()
        default: break
        }
    }

    /// When the open groups are taller than the screen, the wheel brings the rest into view
    /// (QNX-04: every entry stays reachable).
    override func scrollWheel(with event: NSEvent) {
        scroll -= event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        clampScroll()
    }
    private func clampScroll() {
        scroll = max(0, min(scroll, contentHeight - bounds.height))
        needsDisplay = true
    }
}

// MARK: - Taskbar (QNX-02, QNX-06)

final class PhotonTaskbarView: NSView {
    static let height: CGFloat = 31
    static let clockW: CGFloat = 105, launchW: CGFloat = 80, taskPitch: CGFloat = 126, taskW: CGFloat = 123

    private let theme: ThemeBundle
    private let launch: NSImage?
    private var tasks: [MinimizedWindowTracker.Entry] = []
    private var timer: Timer?

    init(theme: ThemeBundle) {
        self.theme = theme
        launch = theme.iconResource("qnx_launch.png").flatMap { NSImage(contentsOf: $0) }
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func start() {
        reload()
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.needsDisplay = true }   // the clock shows minutes
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }

    /// One entry per window, as Photon listed them ("Photon Dialer", "TCP/IP Config...").
    func reload() {
        tasks = MinimizedWindowTracker.shared.allWindows
        needsDisplay = true
    }

    private var launchRect: NSRect { NSRect(x: 0, y: 6, width: Self.launchW, height: 25) }
    private var clockRect: NSRect { NSRect(x: bounds.width - Self.clockW, y: 6, width: Self.clockW, height: 25) }
    private func taskRect(_ i: Int) -> NSRect { NSRect(x: 83 + CGFloat(i) * Self.taskPitch, y: 7, width: Self.taskW, height: 23) }
    private var visibleTasks: Int { max(0, Int((clockRect.minX - 83) / Self.taskPitch)) }

    static func clockText(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE-dd hh:mma"
        return f.string(from: d)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        PhotonColors.face.setFill(); bounds.fill()
        PhotonColors.panelFrame(NSRect(x: 0, y: 0, width: clockRect.minX, height: 6), vertical: false)
        // The well the task entries sit in, sunk.
        let well = NSRect(x: Self.launchW, y: 6, width: clockRect.minX - Self.launchW, height: 25)
        PhotonColors.trough.setFill(); well.fill()
        PhotonColors.line.setFill(); NSRect(x: well.minX, y: well.minY, width: well.width, height: 1).fill()
        NSRect(x: well.minX, y: well.minY, width: 1, height: well.height).fill()
        PhotonColors.troughShade.setFill(); NSRect(x: well.minX + 1, y: well.minY + 1, width: well.width - 1, height: 1).fill()
        launch?.draw(in: launchRect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        for (i, t) in tasks.prefix(visibleTasks).enumerated() {
            let r = taskRect(i)
            if t.isFocused && !t.isMinimized {
                PhotonColors.activeTask.setFill(); r.fill()
                NSColor.black.setFill(); r.frame()
            } else {
                PhotonColors.face.setFill(); r.fill()
                PhotonColors.bevel(r, PhotonColors.white, PhotonColors.shade)
            }
            if let icon = NSRunningApplication(processIdentifier: t.pid)?.icon {
                NSGraphicsContext.current?.imageInterpolation = .high
                icon.draw(in: NSRect(x: r.minX + 6, y: r.minY + 3, width: 16, height: 16), from: .zero, operation: .sourceOver,
                          fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.current?.imageInterpolation = .none
            }
            let name = t.title.isEmpty ? (NSRunningApplication(processIdentifier: t.pid)?.localizedName ?? "") : t.title
            PhotonColors.text(name, at: NSPoint(x: r.minX + 28, y: r.minY + 4), font: PhotonColors.label, in: r.width - 32)
        }

        let c = clockRect
        PhotonColors.face.setFill(); c.fill()
        PhotonColors.line.setFill(); NSRect(x: c.minX, y: c.minY - 6, width: 1, height: c.height + 6).fill()
        PhotonColors.bevel(NSRect(x: c.minX + 1, y: c.minY - 6, width: c.width - 1, height: c.height + 6), PhotonColors.white, PhotonColors.shade)
        let s = Self.clockText() as NSString
        let w = s.size(withAttributes: [.font: PhotonColors.clock]).width
        PhotonColors.text(s as String, at: NSPoint(x: (c.midX - w / 2).rounded(), y: c.minY + 5), font: PhotonColors.clock)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if launchRect.contains(p) {
            PhotonLaunchMenu.show(above: window?.convertToScreen(convert(launchRect, to: nil)) ?? .zero)
        } else if clockRect.contains(p) {
            CDEActions.settings("com.apple.Date-Time-Settings.extension")()
        } else if let i = (0..<min(tasks.count, visibleTasks)).first(where: { taskRect($0).contains(p) }) {
            MinimizedWindowTracker.shared.activate(tasks[i])   // QNX-06: brings the window back to the front
        }
    }
}

// MARK: - Launch menu (QNX-05)

/// The Launch menu of 6.2.1 in its sections: the app categories, then Software, Configure and
/// Help, then the way out. The categories hold the installed Mac apps, sorted by what they declare
/// (App Store category; apps that open web pages or mail count as Internet). Configure is the
/// shelf's own Configure group, so there is one list, not two. "End Photon session", the first
/// choice of Photon's shutdown dialog, turns the theme off.
enum PhotonLaunchMenu {
    static let categories = ["MultiMedia", "Editors", "Utilities", "Internet", "Development"]

    static func category(of path: String, category: String?, internet: Set<String>) -> String {
        if internet.contains(path) { return "Internet" }
        let c = (category ?? "").replacingOccurrences(of: "public.app-category.", with: "")
        if c.hasSuffix("games") { return "MultiMedia" }
        switch c {
        case "music", "video", "photography", "graphics-design", "entertainment": return "MultiMedia"
        case "productivity", "business", "education", "reference", "books", "finance": return "Editors"
        case "developer-tools": return "Development"
        default: return "Utilities"
        }
    }

    static func items() -> [CDEMenuItem] {
        let fm = FileManager.default
        var paths: [String] = []
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            paths += ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".app") }.map { dir + "/" + $0 }
        }
        let internet = Set(["https://example.com", "mailto:x@example.com"].flatMap { URL(string: $0).map { NSWorkspace.shared.urlsForApplications(toOpen: $0) } ?? [] }
            .map(\.path))
        var byCategory: [String: [CDEMenuItem]] = [:]
        var seen = Set<String>()
        for path in Set(paths).sorted() {
            let name = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            guard seen.insert(name).inserted else { continue }   // one entry per name, as a menu shows it
            let declared = Bundle(path: path)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            let icon = NSWorkspace.shared.icon(forFile: path)
            let item = CDEMenuItem(title: name, icon: icon,
                                   action: { NSWorkspace.shared.open(URL(fileURLWithPath: path)) })
            byCategory[category(of: path, category: declared, internet: internet), default: []].append(item)
        }
        func sorted(_ list: [CDEMenuItem]) -> [CDEMenuItem] {
            fit(list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
        let theme = ThemeManager.shared.activeTheme
        func icon(_ name: String) -> NSImage? { theme?.iconResource("\(name).png").flatMap { NSImage(contentsOf: $0) } }
        let configure: [CDEMenuItem] = PhotonShelfView.makeGroups().first { $0.id == "configure" }.flatMap {
            if case .items(let list) = $0.body { return list.map { i in CDEMenuItem(title: i.title, icon: icon(i.icon), action: i.action) } }
            return nil
        } ?? []
        return categories.map { CDEMenuItem(title: $0, submenu: sorted(byCategory[$0] ?? [])) }
            + [.separator,
               CDEMenuItem(title: "Software", submenu: [
                CDEMenuItem(title: "Installer", icon: icon("qnx_installer"), action: CDEActions.app("com.apple.AppStore")),
                CDEMenuItem(title: "Software Update", action: CDEActions.settings("com.apple.Software-Update-Settings.extension"))]),
               CDEMenuItem(title: "Configure", submenu: configure),
               CDEMenuItem(title: "Help", icon: icon("qnx_help"), action: CDEActions.app("com.apple.tips")),
               .separator,
               CDEMenuItem(title: "End Photon session", action: { AppDelegate.shared?.launcherDisableTheme() })]
    }

    /// A list taller than the screen ends in "More", which holds the rest, and so on down.
    static func fit(_ list: [CDEMenuItem], rows: Int = max(8, Int(((NSScreen.screens.first?.visibleFrame.height ?? 800) - 60) / CDEMenu.photonRow))) -> [CDEMenuItem] {
        guard list.count > rows else { return list }
        return Array(list.prefix(rows - 1)) + [CDEMenuItem(title: "More", submenu: fit(Array(list.dropFirst(rows - 1)), rows: rows))]
    }

    /// Opens upwards from the Launch button, standing on the taskbar.
    static func show(above button: NSRect) {
        let items = items()
        let h = CDEMenu.size(of: items, title: nil).height
        CDEMenu.show(items, at: NSPoint(x: button.minX, y: button.maxY + h - 1), look: .photon)
    }
}
