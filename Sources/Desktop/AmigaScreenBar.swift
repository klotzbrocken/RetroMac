import AppKit

/// The Workbench screen's title bar along the top edge (Amiga Workbench 4.1): the ball, the
/// screen title and the screen-depth gadget, drawn by `AmigaChrome` after Screenbar.png. When the
/// theme comes on it reads AmigaOS's copyright line for five seconds, as the 2008 boot did, then
/// "Amiga Workbench" and the free memory, as the Workbench screen does.
///
/// The right mouse button is AmigaOS's menu button: held on the bar or on the empty desktop, the
/// bar shows the menu titles, and letting go over a row runs it. Let go over the titles, the
/// menus stay open for clicking, as a Mac user would expect.
final class AmigaScreenBarController {
    static let shared = AmigaScreenBarController()
    private init() {}

    private var window: NSPanel?
    private var view: AmigaScreenBarView?
    private var timer: Timer?
    private var copyrightUntil = Date.distantPast
    private var shownOnce = false
    private var dragMonitor: Any?

    /// The band the bar takes along the top of `screen` while the Amiga theme is on, nil
    /// otherwise: the desktop icons and the windows keep out of it.
    static func reservedFrame(on screen: NSScreen) -> NSRect? {
        guard AppSettings.shared.dockEnabled, !AppSettings.shared.dockOnly, ThemeManager.shared.activeTheme?.config.isAmiga == true,
              screen == NSScreen.screens.first else { return nil }
        // At the very top while the theme hides the Mac's menu bar (as it does by default): the
        // visible frame still keeps the hidden bar's height free, and the wallpaper showed there.
        let top = AppSettings.shared.hideMenuBar ? screen.frame.maxY : screen.visibleFrame.maxY
        return NSRect(x: screen.frame.minX, y: top - AmigaChrome.screenBarHeight, width: screen.frame.width,
                      height: AmigaChrome.screenBarHeight)
    }

    func update() {
        guard let screen = NSScreen.screens.first, let frame = Self.reservedFrame(on: screen) else { hide(); return }
        if window == nil {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: 24)
            panel.isOpaque = true
            panel.hasShadow = false
            panel.title = "Workbench Screen"   // what VoiceOver calls it
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            let v = AmigaScreenBarView(frame: NSRect(origin: .zero, size: frame.size))
            v.autoresizingMask = [.width, .height]
            panel.contentView = v
            window = panel; view = v
        }
        window?.setFrame(frame, display: true)
        if !shownOnce { shownOnce = true; copyrightUntil = Date().addingTimeInterval(5) }
        refreshTitle()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshTitle() }
        }
        window?.orderFrontRegardless()
    }

    func hide() {
        timer?.invalidate(); timer = nil
        endMenus()
        window?.orderOut(nil)
        window = nil; view = nil
        shownOnce = false
    }

    private func refreshTitle() {
        guard let view else { return }
        // The copyright line counts its five seconds from when the boot screen is gone.
        if SplashController.shared.isPresenting, copyrightUntil > .distantPast { copyrightUntil = Date().addingTimeInterval(5) }
        if Date() < copyrightUntil {
            view.title = "Copyright (C) 1985-2008 Hyperion Entertainment VOF and others. All Rights Reserved."
        } else {
            copyrightUntil = .distantPast   // once only: a later boot screen does not bring it back
            view.title = "Amiga Workbench   \(Self.bytesFree()) bytes free"
        }
    }

    /// The Mac's free memory the way the Workbench counts it: what is free now plus what macOS
    /// would hand out at once (inactive and speculative pages), in bytes with thousands commas.
    static func bytesFree() -> String {
        guard let vm = SystemSampler.vmStats() else { return "0" }
        let page = UInt64(vm_kernel_page_size)
        let bytes = (UInt64(vm.free_count) + UInt64(vm.inactive_count) + UInt64(vm.speculative_count)) * page
        return grouped(bytes)
    }
    static func grouped(_ n: UInt64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    // MARK: - Menus

    /// Starts the menus from a right-button press anywhere (the bar or the desktop): the bar
    /// switches to the menu titles and follows the pointer until the button comes up. False
    /// when the bar is not there (another theme).
    @discardableResult func beginMenus() -> Bool {
        guard let view, window?.isVisible == true else { return false }
        view.menuMode = true
        if dragMonitor == nil {
            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDragged, .rightMouseUp]) { [weak self] e in
                self?.follow(e)
                return e
            }
        }
        follow(nil)
        return true
    }

    private func follow(_ e: NSEvent?) {
        guard let view, let window else { return }
        let p = NSEvent.mouseLocation
        let local = view.convert(window.convertPoint(fromScreen: p), from: nil)
        let menus = PlatinumMenuController.shared
        if e?.type == .rightMouseUp {
            if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
            if view.bounds.contains(local) {
                // Let go over the titles: the open menu stays for clicking; none open, all close.
                if !menus.isOpen { endMenus() }
            } else if !menus.release(screenPoint: p) {
                menus.dismissAll(); endMenus()
            }
            return
        }
        if view.bounds.contains(local), let i = view.titleIndex(at: local) {
            open(i)
        } else {
            menus.track(screenPoint: p)
        }
    }

    /// Opens the menu under title `i`, unless it is open already.
    func open(_ i: Int) {
        guard let view, let window, view.openTitle != i else { return }
        let r = window.convertToScreen(view.convert(view.titleRect(i), to: nil))
        let menus = PlatinumMenuController.shared
        menus.ignoreClickWindow = window
        menus.show(AmigaWorkbenchMenus.items(AmigaWorkbenchMenus.titles[i]), below: r, look: .amiga)
        view.openTitle = i
        menus.onDismiss = { [weak self] in
            self?.view?.openTitle = nil
            if self?.dragMonitor == nil { self?.endMenus() }
        }
    }

    func endMenus() {
        if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
        view?.menuMode = false
        view?.openTitle = nil
        if PlatinumMenuController.shared.isOpen { PlatinumMenuController.shared.dismissAll() }
    }
}

final class AmigaScreenBarView: NSView {
    var title = "" { didSet { if title != oldValue { needsDisplay = true; setAccessibilityLabel(title) } } }
    var menuMode = false { didSet { needsDisplay = true } }
    var openTitle: Int? { didSet { needsDisplay = true } }
    private var depthPressed = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The menu titles from the left, 10 pt apart, as AmigaOS lays out a screen's menu strip.
    func titleRect(_ i: Int) -> NSRect {
        let font = AmigaChrome.titleFont()
        var x: CGFloat = 4
        for (k, t) in AmigaWorkbenchMenus.titles.enumerated() {
            let w = (t as NSString).size(withAttributes: [.font: font]).width + 12
            if k == i { return NSRect(x: x, y: 0, width: w, height: bounds.height - 1) }
            x += w + 4
        }
        return .zero
    }
    func titleIndex(at p: NSPoint) -> Int? { AmigaWorkbenchMenus.titles.indices.first { titleRect($0).contains(p) } }

    override func draw(_ dirtyRect: NSRect) {
        guard menuMode else {
            AmigaChrome.drawScreenBar(in: bounds, title: title, depthPressed: depthPressed)
            return
        }
        AmigaChrome.drawBands(AmigaChrome.screenRows, in: bounds)
        let font = AmigaChrome.titleFont()
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        for (i, t) in AmigaWorkbenchMenus.titles.enumerated() {
            let r = titleRect(i)
            if openTitle == i { AmigaChrome.drawBands(Array(AmigaChrome.activeRows.dropFirst().dropLast()), in: r) }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let h = (t as NSString).size(withAttributes: attrs).height
            (t as NSString).draw(at: NSPoint(x: r.minX + 6, y: ((bounds.height - 1 - h) / 2).rounded()), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if menuMode, let i = titleIndex(at: p) { AmigaScreenBarController.shared.open(i); return }
        if AmigaChrome.screenDepthRect(in: bounds).insetBy(dx: -3, dy: -3).contains(p) {
            // One screen only: the gadget goes down and comes up, and the view stays as it is.
            depthPressed = true; needsDisplay = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        if depthPressed { depthPressed = false; needsDisplay = true }
    }
    override func rightMouseDown(with event: NSEvent) {
        AmigaScreenBarController.shared.beginMenus()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .menuBar }
    override func accessibilityPerformShowMenu() -> Bool {
        AmigaScreenBarController.shared.beginMenus()
        AmigaScreenBarController.shared.open(0)
        return true
    }
}

/// The Workbench's four menus. A row whose job has a counterpart on the Mac does it; the rest
/// show ghosted, as AmigaOS ghosts what does not apply.
enum AmigaWorkbenchMenus {
    static let titles = ["Workbench", "Window", "Icons", "Tools"]

    static func items(_ title: String) -> [PlatinumMenuItem] {
        let desk = DesktopIconsController.shared
        // The Window and Icons menus work on the drawer last used, else on the backdrop.
        let drawer = AmigaDrawer.active
        let selected = drawer?.hasSelection ?? (desk.selectedEntry != nil)
        func off(_ t: String) -> PlatinumMenuItem { .action(t, dimmed: true) {} }
        switch title {
        case "Workbench":
            return [
                .action("Backdrop", ticked: true, dimmed: true) {},
                .action("Execute command...") { AmigaRequester.executeCommand() },
                .action("Redraw all") { desk.update() },
                .action("Update all") { desk.update(); drawer?.reload() },
                off("Last message"),
                .action("About...") { ThemeReadmeController.shared.showForActiveTheme() },
                off("Quit..."),
            ]
        case "Window":
            guard let drawer else {
                return [off("New drawer"), off("Open parent"), off("Close"),
                        .action("Update") { desk.update() }, off("Select contents"),
                        .action("Clean up") { desk.snapToGrid() }, .separator(),
                        .submenu("Snapshot", [off("Window"), off("All")]),
                        .submenu("Show", [.action("Only icons", ticked: true, dimmed: true) {}, off("All files")]),
                        .submenu("View by", [.action("Icon", ticked: true, dimmed: true) {}, off("Name"), off("Date"), off("Size"), off("Type")])]
            }
            return [
                .action("New drawer", dimmed: !drawer.canChange) { drawer.newDrawer() },
                .action("Open parent", dimmed: drawer.url == nil || drawer.url?.path == "/") { drawer.openParent() },
                .action("Close") { drawer.close() },
                .action("Update") { drawer.reload() },
                .action("Select contents") { drawer.selectContents() },
                .action("Clean up") { drawer.cleanUp() },
                .separator(),
                .submenu("Snapshot", [.action("Window") { drawer.snapshot(all: false) }, .action("All") { drawer.snapshot(all: true) }]),
                .submenu("Show", [.action("Only icons", ticked: !drawer.showsAllFiles, dimmed: drawer.isSystem) { drawer.setAllFiles(false) },
                                  .action("All files", ticked: drawer.showsAllFiles, dimmed: drawer.isSystem) { drawer.setAllFiles(true) }]),
                .submenu("View by", [.action("Icon", ticked: true, dimmed: true) {}, off("Name"), off("Date"), off("Size"), off("Type")]),
            ]
        case "Icons":
            return [
                .action("Open", dimmed: !selected) { if let drawer { drawer.openSelected() } else { desk.openSelected() } },
                off("Copy"), off("Rename..."), off("Information..."),
                .action("Snapshot", dimmed: !selected) { if let drawer { drawer.snapshotSelected() } else { desk.snapshotSelected() } },
                .action("Unsnapshot", dimmed: !selected) { if let drawer { drawer.unsnapshotSelected() } else { desk.unsnapshotSelected() } },
                off("Leave out"), off("Put away"),
                .separator(),
                .action("Delete...", dimmed: drawer == nil || !selected || drawer?.canChange != true) { drawer?.deleteSelected() },
                off("Format disk..."), off("Empty trash"),
            ]
        default:
            return [.action("ResetWB") { desk.update(); AmigaScreenBarController.shared.update() }]
        }
    }
}

/// An AmigaOS requester in RetroMac's own window chrome: "Execute a file" from the Workbench
/// menu (PostInstall.png shows it), its command run in Terminal, the Mac's Shell.
final class AmigaRequester: NSObject, NSTextFieldDelegate {
    private static var open: AmigaRequester?
    private var panel: NSPanel?
    private var field: NSTextField?

    static func executeCommand() {
        if let r = open { r.panel?.makeKeyAndOrderFront(nil); return }
        let r = AmigaRequester(); open = r; r.show()
    }

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func show() {
        let size = NSSize(width: 330, height: 136)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let p = KeyPanel(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY, width: size.width, height: size.height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.title = "Execute a file"
        let chrome = WebAppChromeView(frame: NSRect(origin: .zero, size: size), title: "Execute a file")
        chrome.onClose = { [weak self] in self?.close() }
        let body = NSView(frame: .zero)
        let font = AmigaChrome.titleFont()
        let prompt = NSTextField(labelWithString: "Enter command and its arguments:")
        prompt.font = font; prompt.alignment = .center
        prompt.frame = NSRect(x: 0, y: 52, width: size.width - 10, height: 18)
        let label = NSTextField(labelWithString: "Command:")
        label.font = font
        label.frame = NSRect(x: 6, y: 28, width: 76, height: 18)
        let f = NSTextField(frame: NSRect(x: 82, y: 26, width: size.width - 98, height: 22))
        f.font = font; f.delegate = self; f.target = self; f.action = #selector(execute)
        f.bezelStyle = .squareBezel
        let ok = AmigaButton(title: "Execute") { [weak self] in self?.execute() }
        ok.frame = NSRect(x: 6, y: 2, width: 76, height: 21)
        let cancel = AmigaButton(title: "Cancel") { [weak self] in self?.close() }
        cancel.frame = NSRect(x: size.width - 10 - 82, y: 2, width: 76, height: 21)
        [prompt, label, f, ok, cancel].forEach(body.addSubview)
        chrome.embed(body)
        p.contentView = chrome
        panel = p; field = f
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(f)
    }

    @objc private func execute() {
        let cmd = field?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        close()
        guard !cmd.isEmpty else { return }
        // The user's own command, typed here, run where a Shell runs it on the Mac.
        let quoted = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(quoted)\"\nend tell"
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            if let err { print("[Amiga] Execute command failed: \(err)") }
        }
    }

    private func close() {
        panel?.orderOut(nil); panel = nil
        Self.open = nil
    }
}

/// A ReAction button as the 2008 requesters draw it: grey face, darker towards the bottom,
/// a dark line round it, lit inside along the top and left.
final class AmigaButton: NSView {
    private let title: String
    private let run: () -> Void
    private var pressed = false
    init(title: String, run: @escaping () -> Void) {
        self.title = title; self.run = run
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(title)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func accessibilityPerformPress() -> Bool { run(); return true }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        AmigaChrome.drawBands(pressed ? AmigaChrome.inactiveRows.reversed() : AmigaChrome.inactiveRows, in: b)
        AmigaChrome.rgb(0x424242).setFill()
        NSRect(x: 0, y: 0, width: b.width, height: 1).fill(); NSRect(x: 0, y: b.maxY - 1, width: b.width, height: 1).fill()
        NSRect(x: 0, y: 0, width: 1, height: b.height).fill(); NSRect(x: b.maxX - 1, y: 0, width: 1, height: b.height).fill()
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        let attrs: [NSAttributedString.Key: Any] = [.font: AmigaChrome.titleFont(), .foregroundColor: NSColor.black]
        let s = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: ((b.width - s.width) / 2).rounded(), y: ((b.height - s.height) / 2).rounded()), withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false; needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { run() }
    }
}
