import AppKit

/// KDE 1.0 (July 1998) on the Mac (Lastenheft KDE 1.x, K01 … K09): the KPanel along the bottom and
/// the taskbar along the top, two panels of their own. The numbers are KDE's own, read in
/// kde1-kdebase at 78afecb4 (10 July 1998): kpanelrc puts the panel at the bottom with 45 × 45
/// boxes and two pager rows and the taskbar at the top; kpanel.C lays out the 12 pt hide button,
/// the buttons, the control group (exit and lock over the four desktop buttons) and the clock;
/// tools.C draws the buttons flat until the pointer is over them, as qDrawWinButton when raised.
///
/// The four desktops are the four backgrounds of kdisplayrc. A Mac window is not moved between
/// them: macOS has no way to hide one window of another app reversibly without minimising it, so
/// the windows stay where they are and "To desktop" in the window menu says so (Lastenheft §4).
final class KDEDesktopController {
    static let shared = KDEDesktopController()
    private var panel: NSPanel?
    private var taskbar: NSPanel?
    private var pager: NSPanel?
    private var pagerTimer: Timer?
    private var revealWatch: Timer?
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []
    /// The taskbar has stepped down under the Mac menu bar, which macOS slides in over it when the
    /// pointer comes up there; it goes back up once the pointer has left it below.
    private var lowered = false

    static var isActiveTheme: Bool { ThemeManager.shared.activeTheme?.config.chrome?.style == "kde" }

    /// The launcher shortcut on KDE: the K menu, from its button.
    func openKMenu() -> Bool {
        guard panel?.isVisible == true, let view = panel?.contentView as? KPanelView else { return false }
        view.showKMenu()
        return true
    }

    func update() {
        guard AppSettings.shared.dockEnabled, Self.isActiveTheme, let theme = ThemeManager.shared.activeTheme else { hide(); return }
        show(theme: theme)
    }

    func hide() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        lowered = false
        revealWatch?.invalidate(); revealWatch = nil
        pagerTimer?.invalidate(); pagerTimer = nil
        (panel?.contentView as? KPanelView)?.stop()
        panel?.orderOut(nil); taskbar?.orderOut(nil); pager?.orderOut(nil)
        panel = nil; taskbar = nil; pager = nil
        if CDEMenu.look == .kde { CDEMenu.close() }
    }

    /// AppKit keeps windows out of the menu bar's place; the taskbar belongs there once it hides.
    private final class BarPanel: NSPanel {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private static func makePanel(_ title: String) -> NSPanel {
        let p = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: 5)   // over the windows, like the dock it stands in for
        p.isOpaque = true
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.title = title   // what VoiceOver calls it
        return p
    }

    private func show(theme: ThemeBundle) {
        if panel == nil {
            let p = Self.makePanel("Panel"), t = Self.makePanel("Taskbar"), g = Self.makePanel("Pager")
            p.contentView = KPanelView(theme: theme)
            t.contentView = KTaskbarView()
            g.contentView = KPagerView(theme: theme)
            g.level = .normal   // a window among windows, as kpager was: over a title bar it hid the buttons
            panel = p; taskbar = t; pager = g
            // The pager shows the windows live: they move without telling anyone.
            pagerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.pager?.contentView?.needsDisplay = true
            }
            let nc = NotificationCenter.default
            observers = [
                nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.layout() },
                nc.addObserver(forName: .windowsChanged, object: nil, queue: .main) { [weak self] _ in
                    (self?.taskbar?.contentView as? KTaskbarView)?.reload()
                    self?.pager?.contentView?.needsDisplay = true
                },
                // A background picked in Settings is a desktop picked: the pager follows it.
                nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.panel?.contentView?.needsDisplay = true
                    self?.pager?.contentView?.needsDisplay = true
                },
            ]
            let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            mouseMonitors = [
                NSEvent.addGlobalMonitorForEvents(matching: moved) { [weak self] _ in self?.followPointer() },
                NSEvent.addLocalMonitorForEvents(matching: moved) { [weak self] e in self?.followPointer(); return e },
            ].compactMap { $0 }
        }
        layout()
        panel?.orderFrontRegardless(); pager?.orderFrontRegardless(); taskbar?.orderFrontRegardless()
        (panel?.contentView as? KPanelView)?.start()
        (taskbar?.contentView as? KTaskbarView)?.reload()
        KDEApps.prepare()
    }

    /// The panel across the bottom of the main display, the taskbar across its top (kpanelrc:
    /// Position=bottom, TaskbarPosition=top). A hidden panel leaves its 12 pt button in the corner.
    func layout() {
        guard let screen = NSScreen.screens.first else { return }
        // The screen's own edges, as GEM's bar uses: the visible frame lags behind the hidden menu
        // bar and Dock (no screen-parameter change always follows), and with the menu bar hidden it
        // still stops below its place, so the taskbar sometimes sat 33 pt down. Only when the menu
        // bar stays (VoiceOver, see ThemeManager.syncMenuBarVisibility) does the taskbar go under it.
        let f = screen.frame
        let top = Self.menuBarStays ? screen.visibleFrame.maxY : f.maxY
        let h = Self.taskbarHeight(on: screen)
        let hidden = KPanelView.isHidden
        panel?.setFrame(NSRect(x: f.minX, y: f.minY, width: hidden ? KPanelView.hideW : f.width, height: KPanelView.height), display: true)
        let barY = top - h - (lowered ? h : 0)
        taskbar?.setFrame(NSRect(x: f.minX, y: barY, width: f.width, height: h), display: true)
        let ps = KPagerView.size(for: f)
        pager?.setFrame(NSRect(x: f.maxX - ps.width, y: barY - ps.height, width: ps.width, height: ps.height), display: true)
    }

    private static var menuBarStays: Bool {
        NSWorkspace.shared.isVoiceOverEnabled || ThemeManager.shared.activeTheme?.config.hideMenuBarDefault != true
    }

    /// As tall as the Mac menu bar (33 pt under a notch), so the bar macOS slides in over it
    /// covers it exactly instead of leaving a cut-off strip; never below kpanel's 24 pt.
    static func taskbarHeight(on screen: NSScreen) -> CGFloat {
        max(KTaskbarView.height, max(screen.safeAreaInsets.top, ThemeManager.shared.menuBarHeight(of: screen)).rounded())
    }

    /// The Mac menu bar slides in over the taskbar when the pointer comes up there, and the
    /// taskbar's buttons were out of reach: the taskbar steps down under it, and goes back once
    /// the pointer leaves it below. Whether the bar is in is read off the WindowServer's menu-bar
    /// window (hidden, it waits above the screen), checked ten times a second only while the
    /// pointer is up there, not guessed from the pointer: where macOS starts the slide is its own.
    private func followPointer() {
        guard !Self.menuBarStays, let t = taskbar, let screen = NSScreen.screens.first else { return }
        let p = NSEvent.mouseLocation, f = screen.frame
        guard p.x >= f.minX, p.x <= f.maxX else { return }
        if lowered, p.y < t.frame.minY {
            lowered = false; layout()
        } else if !lowered, p.y >= t.frame.minY, revealWatch == nil {
            revealWatch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self, let t = self.taskbar, !self.lowered else { timer.invalidate(); self?.revealWatch = nil; return }
                if ThemeManager.menuBarWindowHeight(on: screen) != nil {
                    self.lowered = true; self.layout()
                } else if NSEvent.mouseLocation.y < t.frame.minY {
                    timer.invalidate(); self.revealWatch = nil
                }
            }
        }
    }

    /// The taskbar button of a window, on screen: where kwm's iconify sends it.
    func taskButtonScreenRect(for window: AXUIElement) -> NSRect? {
        guard let t = taskbar, let view = t.contentView as? KTaskbarView, let r = view.buttonRect(for: window) else { return nil }
        return t.convertToScreen(view.convert(r, to: nil))
    }

    /// What the two hold, for maximised windows: the taskbar's resting lower edge and the panel's height.
    var reserved: (taskbarBottom: CGFloat, bottom: CGFloat)? {
        guard panel != nil, let t = taskbar else { return nil }
        return (t.frame.minY + (lowered ? t.frame.height : 0), KPanelView.height)
    }

    // MARK: The four desktops

    static let desktopNames = ["One", "Two", "Three", "Four"]

    /// The desktop is the background it shows: kdisplayrc's four, in the theme's wallpaper list.
    static var currentDesktop: Int {
        guard let theme = ThemeManager.shared.activeTheme, let list = theme.config.wallpapers else { return 0 }
        let file = AppSettings.shared.themeWallpaperOverrides[theme.stableID] ?? theme.config.wallpaper
        return list.firstIndex { $0.file == file } ?? 0
    }

    static func switchTo(desktop i: Int) {
        guard let theme = ThemeManager.shared.activeTheme, let list = theme.config.wallpapers, list.indices.contains(i) else { return }
        AppSettings.shared.themeWallpaperOverrides[theme.stableID] = list[i].file
        ThemeManager.shared.applyWallpaper()
        shared.panel?.contentView?.needsDisplay = true
        shared.taskbar?.contentView?.needsDisplay = true
    }
}

/// Qt 1's Windows style in KDE's default colours (kapp.cpp: background lightGray, select and
/// active title darkBlue; Qt's lightGray is #C0C0C0) and KDE's general font, Helvetica 12.
enum KDEColors {
    static let face = NSColor.fromHex("#C0C0C0")
    static let light = NSColor.white
    static let dark = NSColor.fromHex("#808080")
    static let shadow = NSColor.black
    static let select = NSColor.fromHex("#000080")
    static let font = NSFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12)
    static let small = NSFont(name: "Helvetica", size: 10) ?? .systemFont(ofSize: 10)

    private static func edge(_ r: NSRect, _ i: CGFloat, _ tl: NSColor, _ br: NSColor) {
        tl.setFill()
        NSRect(x: r.minX + i, y: r.minY + i, width: r.width - 2 * i, height: 1).fill()
        NSRect(x: r.minX + i, y: r.minY + i, width: 1, height: r.height - 2 * i).fill()
        br.setFill()
        NSRect(x: r.minX + i, y: r.maxY - 1 - i, width: r.width - 2 * i, height: 1).fill()
        NSRect(x: r.maxX - 1 - i, y: r.minY + i, width: 1, height: r.height - 2 * i).fill()
    }

    /// qDrawWinButton in a flipped view: white and black outside, face and #808080 inside, the
    /// other way round when sunk.
    static func winButton(_ r: NSRect, sunken: Bool) {
        if sunken { edge(r, 0, shadow, light); edge(r, 1, dark, face) } else { edge(r, 0, light, shadow); edge(r, 1, face, dark) }
    }
    /// qDrawWinPanel, the popup and window frame: as the button but lit with the face inside.
    static func winPanel(_ r: NSRect, sunken: Bool) {
        if sunken { edge(r, 0, dark, light); edge(r, 1, shadow, face) } else { edge(r, 0, face, shadow); edge(r, 1, light, dark) }
    }
    /// A QFrame Panel of line width 1.
    static func panel1(_ r: NSRect, sunken: Bool) { edge(r, 0, sunken ? dark : light, sunken ? light : dark) }

    /// Qt's Dense4Pattern in white over the face: the active task button.
    static func dense4(_ r: NSRect) {
        light.setFill()
        var y = r.minY
        while y < r.maxY {
            var x = r.minX + CGFloat(Int(y - r.minY) % 2)
            while x < r.maxX { NSRect(x: x, y: y, width: 1, height: 1).fill(); x += 2 }
            y += 1
        }
    }

    static func text(_ s: String, in r: NSRect, font: NSFont = font, color: NSColor = .black, centred: Bool = false) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        para.alignment = centred ? .center : .left
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let h = (s as NSString).size(withAttributes: attrs).height
        (s as NSString).draw(in: NSRect(x: r.minX, y: (r.midY - h / 2).rounded(), width: r.width, height: h), withAttributes: attrs)
    }
}

// MARK: - KPanel (K01, K02, K04, K09)

final class KPanelView: NSView {
    static let box: CGFloat = 45, height: CGFloat = 45, hideW: CGFloat = 12
    /// The control group: 22 pt exit and lock buttons over each other, then two rows of desktop
    /// buttons four halves wide (kpanel.C, dbrows 2, dbhs 4): 1 + 22 + (88 + 1) × 2 = 201.
    static let half: CGFloat = 22, deskW: CGFloat = 88

    struct Button { let id: String; let title: String; let icon: String; let action: (KPanelView, NSRect) -> Void }

    private let theme: ThemeBundle
    private var images: [String: NSImage] = [:]
    private var hover: String?
    private var pressed: String?
    private var timer: Timer?

    private static let hiddenKey = "kdePanelHidden"
    static var isHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hiddenKey) }
        set { UserDefaults.standard.set(newValue, forKey: hiddenKey) }
    }

    init(theme: ThemeBundle) {
        self.theme = theme
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func start() {
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.needsDisplay = true }   // the clock shows minutes
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }

    func image(_ name: String) -> NSImage? {
        if let i = images[name] { return i }
        let i = theme.iconResource(name).flatMap { NSImage(contentsOf: $0) }
        images[name] = i
        return i
    }

    /// kpanelrc's Buttons, in order; the control group stands after the fifth (control=5).
    static let left: [Button] = [
        Button(id: "k", title: "K Menu", icon: "go.png") { v, r in v.showKMenu(from: r) },
        Button(id: "windowlist", title: "Window List", icon: "window_list.png") { v, r in v.post(KDEMenus.windowList(), from: r) },
        Button(id: "home", title: "Home Directory", icon: "kfm_home.png") { _, _ in CDEActions.open(CDEActions.home)() },
        Button(id: "kcontrol", title: "KDE Control Center", icon: "kcontrol.png") { _, _ in CDEActions.app("com.apple.systempreferences")() },
        Button(id: "kfind", title: "Find Files", icon: "kfind.png") { _, _ in KDEMenus.findFiles() },
    ]
    static let right: [Button] = [
        Button(id: "utilities", title: "Utilities", icon: "utilities_package.png") { v, r in v.post(KDEMenus.category("Utilities"), from: r) },
        Button(id: "help", title: "KDE Help", icon: "kdehelp.png") { _, _ in ThemeReadmeController.shared.showForActiveTheme() },
        Button(id: "kcalc", title: "KCalc", icon: "kcalc.png") { _, _ in CDEActions.app("com.apple.calculator")() },
        Button(id: "knotes", title: "KNotes", icon: "knotes.png") { _, _ in CDEActions.app("com.apple.Stickies")() },
        Button(id: "kvt", title: "Terminal", icon: "kvt.png") { _, _ in CDEActions.app("com.apple.Terminal")() },
        Button(id: "kedit", title: "KEdit", icon: "kedit.png") { _, _ in CDEActions.app("com.apple.TextEdit")() },
        Button(id: "kmail", title: "KMail", icon: "kmail.png") { _, _ in CDEActions.defaultApp(for: "mailto:x@example.com")() },
        Button(id: "kscd", title: "CD Player", icon: "kscd.png") { _, _ in CDEActions.app("com.apple.Music")() },
        Button(id: "kmix", title: "Sound Mixer", icon: "kmix.png") { _, _ in CDEActions.settings("com.apple.Sound-Settings.extension")() },
    ]

    /// Every hit area: id, rectangle, and what it is called.
    struct Part { let id: String; let rect: NSRect; let label: String }

    var parts: [Part] {
        if Self.isHidden { return [Part(id: "show", rect: bounds, label: "Show the panel")] }
        var out = [Part(id: "hide", rect: NSRect(x: 0, y: 0, width: Self.hideW, height: Self.height), label: "Hide the panel")]
        var x = Self.hideW
        for (i, b) in Self.left.enumerated() {
            // The K button is two points smaller and one point in (kpanel.C, margin 0).
            out.append(Part(id: b.id, rect: i == 0 ? NSRect(x: x + 1, y: 1, width: Self.box - 2, height: Self.box - 2)
                                                   : NSRect(x: x, y: 0, width: Self.box, height: Self.box), label: b.title))
            x += Self.box
        }
        // controldelta 61.5764: the group stands that many ten-thousandths of the free width on.
        let group: CGFloat = 1 + Self.half + (Self.deskW + 1) * 2
        let free = bounds.width - group - Self.hideW
        x += (0.00615764 * free).rounded()
        out.append(Part(id: "exit", rect: NSRect(x: x, y: 0, width: Self.half, height: Self.half), label: "Logout"))
        out.append(Part(id: "lock", rect: NSRect(x: x, y: Self.box - Self.half, width: Self.half, height: Self.half), label: "Lock Screen"))
        for d in 0..<4 {
            let col = CGFloat(d / 2), row = CGFloat(d % 2)
            out.append(Part(id: "desk\(d)", rect: NSRect(x: x + Self.half + 1 + col * (Self.deskW + 1), y: row * (Self.box - Self.half),
                                                         width: Self.deskW, height: Self.half),
                            label: "Desktop \(KDEDesktopController.desktopNames[d])"))
        }
        x += group
        let clock = clockRect
        for b in Self.right where x + Self.box <= clock.minX {
            out.append(Part(id: b.id, rect: NSRect(x: x, y: 0, width: Self.box, height: Self.box), label: b.title))
            x += Self.box
        }
        out.append(Part(id: "clock", rect: clock, label: "Clock, " + Self.clockLines().joined(separator: " ")))
        return out
    }

    /// The date label at the right edge, 5 pt in, 3 pt from top and bottom (kpanel.C).
    private var clockRect: NSRect {
        let w = ceil(["Wed", "00:00", "Sep 00"].map { ($0 as NSString).size(withAttributes: [.font: KDEColors.font]).width }.max() ?? 40)
        return NSRect(x: bounds.width - 5 - w, y: 3, width: w, height: Self.height - 6)
    }

    /// tools.C: the day, the time and the date, three lines when they fit, as KDE wrote them.
    static func clockLines(_ d: Date = Date()) -> [String] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        return ["EEE", "HH:mm", "MMM dd"].map { f.dateFormat = $0; return f.string(from: d) }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        KDEColors.face.setFill(); bounds.fill()
        KDEColors.panel1(bounds, sunken: false)
        let current = KDEDesktopController.currentDesktop
        for p in parts {
            switch p.id {
            case "hide", "show":
                KDEColors.winButton(p.rect, sunken: pressed == p.id)
                arrow(in: p.rect, left: p.id == "hide")
            case "exit", "lock":
                KDEColors.winButton(p.rect, sunken: pressed == p.id)
                drawIcon(p.id == "exit" ? "exit.png" : "key.png", in: p.rect, down: pressed == p.id)
            case let id where id.hasPrefix("desk"):
                let d = Int(id.dropFirst(4)) ?? 0
                let down = d == current || pressed == id
                KDEColors.winButton(p.rect, sunken: down)
                // set_button_text: the name at 3 pt in, on the font's baseline.
                KDEColors.text(KDEDesktopController.desktopNames[d], in: p.rect.insetBy(dx: 3, dy: 0).offsetBy(dx: down ? 1 : 0, dy: down ? 1 : 0))
            case "clock":
                let lines = Self.clockLines()
                let lh = KDEColors.font.boundingRectForFont.height
                let shown = lh * 3 <= p.rect.height ? lines : Array(lines.dropFirst())
                var y = p.rect.midY - lh * CGFloat(shown.count) / 2
                for l in shown {
                    let w = (l as NSString).size(withAttributes: [.font: KDEColors.font]).width
                    (l as NSString).draw(at: NSPoint(x: p.rect.maxX - w, y: y), withAttributes: [.font: KDEColors.font, .foregroundColor: NSColor.black])
                    y += lh
                }
            default:
                guard let b = (Self.left + Self.right).first(where: { $0.id == p.id }) else { continue }
                // Flat until the pointer is over it; raised then, sunk while pressed.
                if pressed == p.id { KDEColors.winButton(p.rect, sunken: true) } else if hover == p.id { KDEColors.winButton(p.rect, sunken: false) }
                drawIcon(b.icon, in: p.rect, down: pressed == p.id)
                if p.id == "k" { kArrow(in: p.rect) }
            }
        }
    }

    private func drawIcon(_ name: String, in r: NSRect, down: Bool) {
        guard let i = image(name) else { return }
        let o = down ? 1 : 0
        NSGraphicsContext.current?.imageInterpolation = .none
        i.draw(in: NSRect(x: (r.midX - i.size.width / 2).rounded() + CGFloat(o), y: (r.midY - i.size.height / 2).rounded() + CGFloat(o),
                          width: i.size.width, height: i.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// The small arrow the panel adds to the K button: the menu opens from it.
    private func kArrow(in r: NSRect) {
        let p = NSBezierPath(), x = r.maxX - 9, y = r.minY + 5
        p.move(to: NSPoint(x: x, y: y + 4)); p.line(to: NSPoint(x: x + 3, y: y)); p.line(to: NSPoint(x: x + 6, y: y + 4)); p.close()
        NSColor.black.setFill(); p.fill()
    }

    private func arrow(in r: NSRect, left: Bool) {
        let p = NSBezierPath(), cx = r.midX, cy = r.midY
        if left { p.move(to: NSPoint(x: cx + 2, y: cy - 4)); p.line(to: NSPoint(x: cx - 2, y: cy)); p.line(to: NSPoint(x: cx + 2, y: cy + 4)) }
        else { p.move(to: NSPoint(x: cx - 2, y: cy - 4)); p.line(to: NSPoint(x: cx + 2, y: cy)); p.line(to: NSPoint(x: cx - 2, y: cy + 4)) }
        p.close(); NSColor.black.setFill(); p.fill()
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    private func part(at p: NSPoint) -> Part? { parts.first { $0.rect.contains(p) } }

    override func mouseMoved(with event: NSEvent) {
        let id = part(at: convert(event.locationInWindow, from: nil))?.id
        if id != hover { hover = id; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard let p = part(at: convert(event.locationInWindow, from: nil)), p.id != "clock" else { return }
        pressed = p.id; needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let was = pressed
        pressed = nil; needsDisplay = true
        guard let p = part(at: convert(event.locationInWindow, from: nil)) else { return }
        if p.id == "clock" { CDEActions.settings("com.apple.Date-Time-Settings.extension")(); return }
        // Menus post on release too: posted on press, the release landed in the panel, not the menu.
        guard p.id == was else { return }
        press(p)
    }

    func press(_ p: Part) {
        switch p.id {
        case "hide", "show":
            Self.isHidden = p.id == "hide"
            KDEDesktopController.shared.layout()
            needsDisplay = true
        case "exit": KDEMenus.logout()
        case "lock": ScreensaverController.shared.start()
        case let id where id.hasPrefix("desk"): KDEDesktopController.switchTo(desktop: Int(id.dropFirst(4)) ?? 0)
        default: (Self.left + Self.right).first { $0.id == p.id }?.action(self, p.rect)
        }
    }

    func showKMenu() {
        guard let r = parts.first(where: { $0.id == "k" })?.rect else { return }
        showKMenu(from: r)
    }
    private func showKMenu(from r: NSRect) { post(KDEMenus.kMenu(), from: r) }

    /// A menu opening upwards from a panel button, its left edge on the button's.
    func post(_ items: [CDEMenuItem], from r: NSRect) {
        CDEMenu.look = .kde
        let h = CDEMenu.size(of: items, title: nil).height
        guard let screenRect = window?.convertToScreen(convert(r, to: nil)) else { return }
        CDEMenu.show(items, at: NSPoint(x: screenRect.minX, y: screenRect.maxY + h), look: .kde)
    }

    // MARK: VoiceOver

    /// Held until the next question: the accessibility server keeps no reference of its own.
    private var axParts: [AccessibleHotspot] = []
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        let current = KDEDesktopController.currentDesktop
        axParts = parts.map { p in
            let label = p.id == "desk\(current)" ? p.label + ", current" : p.label
            return AccessibleHotspot.make(in: self, label: label, rect: p.rect) { [weak self] in self?.press(p) }
        }
        return axParts
    }
}

// MARK: - Taskbar (K03)

final class KTaskbarView: NSView {
    /// tools.C: the font's height and 10 (Helvetica 12 is 14 high in Qt 1).
    static let height: CGFloat = 24

    private var tasks: [MinimizedWindowTracker.Entry] = []
    private var pressed: Int?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func reload() {
        tasks = MinimizedWindowTracker.shared.allWindows
        needsDisplay = true
    }

    /// layout.C: every window one button, as wide as the row allows up to four heights and a
    /// half (tbhs 4 × height × 3/2), one point apart; the four desktops' groups 4 pt apart.
    /// The Mac's windows all count as the current desktop's.
    private func taskRect(_ i: Int) -> NSRect {
        let inner = bounds.insetBy(dx: 1, dy: 1)
        let w = min(4 * Self.height * 3 / 2, ((inner.width - 3 * 4) / CGFloat(tasks.count + 1)).rounded(.down) - 1)
        return NSRect(x: inner.minX + CGFloat(i) * (w + 1), y: inner.minY, width: w, height: inner.height)
    }

    private func name(_ t: MinimizedWindowTracker.Entry) -> String {
        t.title.isEmpty ? (NSRunningApplication(processIdentifier: t.pid)?.localizedName ?? "") : t.title
    }

    override func draw(_ dirtyRect: NSRect) {
        KDEColors.face.setFill(); bounds.fill()
        KDEColors.panel1(bounds, sunken: false)
        for (i, t) in tasks.enumerated() {
            let r = taskRect(i)
            let active = t.isFocused && !t.isMinimized
            if active { KDEColors.dense4(r.insetBy(dx: 2, dy: 2)) }
            KDEColors.winButton(r, sunken: active || pressed == i)
            let o: CGFloat = active || pressed == i ? 1 : 0
            if let icon = KDEMenus.miniIcon(bundleID: t.bundleID, pid: t.pid) {
                icon.draw(in: NSRect(x: r.minX + 8 + o, y: r.midY - 8 + o, width: 16, height: 16), from: .zero, operation: .sourceOver,
                          fraction: t.isMinimized ? 0.5 : 1, respectFlipped: true, hints: nil)
            }
            // A minimised window's name in brackets, as kwm listed iconified windows.
            let label = t.isMinimized ? "[\(name(t))]" : name(t)
            KDEColors.text(label, in: NSRect(x: r.minX + 32 + o, y: r.minY + o, width: r.width - 34, height: r.height))
        }
    }

    private func index(at p: NSPoint) -> Int? { tasks.indices.first { taskRect($0).contains(p) } }

    func buttonRect(for window: AXUIElement) -> NSRect? {
        tasks.firstIndex { !$0.isAppLevel && CFEqual($0.window, window) }.map(taskRect)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = index(at: convert(event.locationInWindow, from: nil)); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let was = pressed
        pressed = nil; needsDisplay = true
        guard let i = index(at: convert(event.locationInWindow, from: nil)), i == was else { return }
        MinimizedWindowTracker.shared.activate(tasks[i])
    }
    /// The middle button iconifies, or brings an iconified window back (kpanel.C).
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let i = index(at: convert(event.locationInWindow, from: nil)) else { return }
        let t = tasks[i]
        if t.isMinimized { MinimizedWindowTracker.shared.activate(t) } else { MinimizedWindowTracker.shared.minimize(t) }
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let i = index(at: convert(event.locationInWindow, from: nil)), let r = window?.convertToScreen(convert(taskRect(i), to: nil)) else { return }
        CDEMenu.show(KDEMenus.windowMenu(tasks[i]), at: NSPoint(x: r.minX, y: r.minY), look: .kde)
    }

    // MARK: VoiceOver

    private var axParts: [AccessibleHotspot] = []
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        axParts = tasks.indices.map { i in
            let t = tasks[i]
            return AccessibleHotspot.make(in: self, label: t.isMinimized ? name(t) + ", minimised" : name(t), rect: taskRect(i)) {
                MinimizedWindowTracker.shared.activate(t)
            }
        }
        return axParts
    }
}


// MARK: - Pager

/// The four desktops in the top right corner, as KDE 1.1's pager showed them: each one's
/// background, the windows on the current one as they stand, the current desktop framed in
/// yellow. A click switches. The Mac's windows all live on the current desktop (see above).
final class KPagerView: NSView {
    private let theme: ThemeBundle
    private var thumbs: [Int: NSImage] = [:]
    init(theme: ThemeBundle) { self.theme = theme; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static let cellW: CGFloat = 72, gap: CGFloat = 3, rim: CGFloat = 7
    static func cellH(for screen: NSRect) -> CGFloat { (cellW * screen.height / max(screen.width, 1)).rounded() }
    static func size(for screen: NSRect) -> NSSize {
        NSSize(width: 2 * rim + 2 * cellW + gap, height: 2 * rim + 2 * cellH(for: screen) + gap)
    }
    private var screen: NSRect { NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900) }
    private func cell(_ i: Int) -> NSRect {
        let h = Self.cellH(for: screen)
        return NSRect(x: Self.rim + CGFloat(i % 2) * (Self.cellW + Self.gap), y: Self.rim + CGFloat(i / 2) * (h + Self.gap),
                      width: Self.cellW, height: h)
    }

    /// The desktop's background, shrunk once: a pattern stays a pattern at the cell's scale.
    private func thumb(_ i: Int, size: NSSize) -> NSImage? {
        if let t = thumbs[i] { return t }
        guard let list = theme.config.wallpapers, list.indices.contains(i),
              let src = NSImage(contentsOf: theme.url.appendingPathComponent(list[i].file)) else { return nil }
        let img = NSImage(size: size, flipped: false) { r in
            if list[i].tiled == true {
                let k = size.width / self.screen.width
                let tile = NSImage(size: NSSize(width: max(1, src.size.width * k), height: max(1, src.size.height * k)), flipped: false) { tr in
                    src.draw(in: tr); return true
                }
                NSColor(patternImage: tile).setFill(); r.fill()
            } else {
                src.draw(in: r)
            }
            return true
        }
        thumbs[i] = img
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        KDEColors.face.setFill(); bounds.fill()
        KDEColors.winPanel(bounds, sunken: false)
        let well = bounds.insetBy(dx: 4, dy: 4)
        KDEColors.winButton(well, sunken: true)
        NSColor.fromHex("#637A80").setFill(); well.insetBy(dx: 2, dy: 2).fill()
        let current = KDEDesktopController.currentDesktop
        for i in 0..<4 {
            let c = cell(i)
            thumb(i, size: c.size)?.draw(in: c, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            if i == current { drawWindows(in: c) }
            (i == current ? NSColor.fromHex("#F0F08C") : .black).setStroke()
            NSBezierPath(rect: c.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    /// The real windows of the primary display, back to front, white with a grey bar; the one in
    /// front pale yellow, as the pager drew the active window.
    private func drawWindows(in c: NSRect) {
        let f = screen
        let own = ProcessInfo.processInfo.processIdentifier
        let list = WindowInventory.onScreen(maxAge: 0.5).filter {
            ($0[kCGWindowLayer as String] as? Int) == 0 && (($0[kCGWindowAlpha as String] as? Double) ?? 1) > 0
                && ($0[kCGWindowOwnerPID as String] as? pid_t) != own
        }
        let rects: [CGRect] = list.compactMap { w in
            var b = CGRect.zero
            guard let d = w[kCGWindowBounds as String] as? NSDictionary, CGRectMakeWithDictionaryRepresentation(d, &b),
                  b.width > 40, b.height > 40, b.intersects(CGRect(x: 0, y: 0, width: f.width, height: f.height)) else { return nil }
            return b
        }
        let kx = c.width / f.width, ky = c.height / f.height
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: c).addClip()
        for (n, b) in rects.enumerated().reversed() {
            let r = NSRect(x: c.minX + b.minX * kx, y: c.minY + b.minY * ky, width: max(3, b.width * kx), height: max(3, b.height * ky)).integral
            (n == 0 ? NSColor.fromHex("#FFFFD0") : .white).setFill(); r.fill()
            KDEColors.face.setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: min(2, r.height)).fill()
            NSColor.black.setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = (0..<4).first(where: { cell($0).contains(p) }) else { return }
        KDEDesktopController.switchTo(desktop: i)
        needsDisplay = true
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Pager, desktop \(KDEDesktopController.desktopNames[KDEDesktopController.currentDesktop])" }
}
