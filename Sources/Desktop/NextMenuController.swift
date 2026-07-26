import AppKit

/// The NeXTSTEP main menu: an always-on-screen VERTICAL menu window parked top-left, the single
/// most recognisable piece of the NeXT desktop. Items stack vertically under a black "Workspace"
/// title cell; a submenu item shows a right-pointing arrow and pops its submenu out to the RIGHT
/// (as on real NeXTSTEP); action items show their Command-key letter at the right.
///
/// Structurally this mirrors `BeOSDeskbarController`/`SGIDesktopController` — a borderless
/// desktop-level `NSPanel` — and is wired into the same theme update/hide call groups. Drawing
/// uses `NeXTChrome` so the menu matches the window chrome and dock pixel-for-pixel.
final class NextMenuController {

    static let shared = NextMenuController()
    private var window: NSPanel?
    private var view: NextMenuView?
    private init() {}

    /// Show for the NeXT theme, hide otherwise. Like the deskbar, the menu is part of the NeXT
    /// desktop identity, so it shows even in dock-only mode.
    func update() {
        guard let theme = ThemeManager.shared.activeTheme, theme.config.isNextStep else { hide(); return }
        show()
    }

    func hide() {
        NextSubmenuPanel.shared.dismiss()
        window?.orderOut(nil)
        window = nil
        view = nil
    }

    private func show() {
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: NextMenuView.width, height: 220),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: 4)   // NeXT main menu = window-tier 4 (above windows)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            window = panel
        }
        let v = NextMenuView(items: Self.menu())
        window?.contentView = v
        view = v
        reposition()
        window?.orderFront(nil)
    }

    private func reposition() {
        guard let window = window, let view = view, let screen = NSScreen.main else { return }
        let h = view.preferredHeight()
        let f = screen.visibleFrame
        // Parked top-left, snug under the menu bar area.
        window.setFrame(NSRect(x: f.minX, y: f.maxY - h, width: NextMenuView.width, height: h), display: true)
        view.frame = NSRect(x: 0, y: 0, width: NextMenuView.width, height: h)
        view.needsDisplay = true
    }

    // MARK: - Menu model + content

    struct Item {
        let title: String
        var shortcut: String? = nil
        var submenu: [Item]? = nil
        var action: (() -> Void)? = nil
        var enabled: Bool = true
    }

    /// The canonical NeXT Workspace menu (OpenStep command order). Real actions are wired where
    /// RetroMac has an equivalent; the rest are period-authentic entries kept for the look.
    static func menu() -> [Item] {
        func act(_ sel: String) { NSApp.sendAction(Selector((sel)), to: nil, from: nil) }
        return [
            Item(title: "Info", submenu: [
                Item(title: "Info Panel\u{2026}", action: { act("openSettings") }),
                Item(title: "Preferences\u{2026}", action: { act("openSettings") }),
                Item(title: "Help", shortcut: "?", enabled: false),
            ]),
            Item(title: "File", submenu: [
                Item(title: "Applications\u{2026}", action: { NextAppsWindowController.shared.show() }),
                Item(title: "Open\u{2026}", shortcut: "o", enabled: false),
                Item(title: "New Folder", shortcut: "n", enabled: false),
                Item(title: "Empty Recycler", action: { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")) }),
            ]),
            Item(title: "Edit", submenu: [
                Item(title: "Cut", shortcut: "x", action: { act("cut:") }),
                Item(title: "Copy", shortcut: "c", action: { act("copy:") }),
                Item(title: "Paste", shortcut: "v", action: { act("paste:") }),
                Item(title: "Select All", shortcut: "a", action: { act("selectAll:") }),
            ]),
            Item(title: "Disk", submenu: [
                Item(title: "Eject", shortcut: "e", enabled: false),
                Item(title: "Check for Disks", enabled: false),
            ]),
            Item(title: "View", submenu: [
                Item(title: "Icon", enabled: false),
                Item(title: "List", enabled: false),
            ]),
            Item(title: "Tools", submenu: [
                Item(title: "Processor Monitor", action: { CPUMonitorController.shared.show() }),
                Item(title: "Clock", action: { ClockWidgetController.shared.show() }),
                Item(title: "Applications\u{2026}", action: { NextAppsWindowController.shared.show() }),
                Item(title: "Preferences\u{2026}", action: { act("openSettings") }),
            ]),
            Item(title: "Windows", submenu: [
                Item(title: "Arrange in Front", action: { NSApp.arrangeInFront(nil) }),
                Item(title: "Miniaturize All", action: { NSApp.windows.forEach { $0.miniaturize(nil) } }),
            ]),
            Item(title: "Services", submenu: [ Item(title: "No Services", enabled: false) ]),
            Item(title: "Hide", shortcut: "h", action: { NSApp.hide(nil) }),
            Item(title: "Log Out", shortcut: "q", action: { NSApp.sendAction(Selector(("disableTheme")), to: nil, from: nil) }),
        ]
    }
}

// MARK: - The vertical menu view

final class NextMenuView: NSView {
    static let width: CGFloat = 96
    static let titleH: CGFloat = 22
    static let cellH: CGFloat = 21

    private let items: [NextMenuController.Item]
    private var hoverIndex: Int? = nil

    init(items: [NextMenuController.Item]) {
        self.items = items
        super.init(frame: NSRect(x: 0, y: 0, width: NextMenuView.width, height: 220))
        wantsLayer = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }   // y=0 at the top, cells stack downward

    func preferredHeight() -> CGFloat { Self.titleH + CGFloat(items.count) * Self.cellH }

    private func cellRect(_ i: Int) -> NSRect {
        NSRect(x: 0, y: Self.titleH + CGFloat(i) * Self.cellH, width: bounds.width, height: Self.cellH)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        // Outer window: grey face + chiseled frame (flipped view).
        NeXTChrome.face.setFill(); ctx.fill(b)
        NeXTChrome.bevel(b, raised: true, width: 2, flipped: true, in: ctx)

        // Black title cell "Workspace".
        let titleBar = NSRect(x: 2, y: 2, width: b.width - 4, height: Self.titleH - 2)
        NeXTChrome.black.setFill(); ctx.fill(titleBar)
        drawText("Workspace", in: titleBar, font: NeXTChrome.titleFont(12), color: .white, align: .left, xInset: 6)

        // Item cells.
        for (i, item) in items.enumerated() {
            let r = cellRect(i).insetBy(dx: 2, dy: 0)
            let hovered = (hoverIndex == i)
            NeXTChrome.tile(r, raised: !hovered, flipped: true, in: ctx)   // sink on hover (press feel)
            let color: NSColor = item.enabled ? .black : NeXTChrome.darkGray
            drawText(item.title, in: r, font: NeXTChrome.labelFont(13), color: color, align: .left, xInset: 8)
            // Right side: submenu arrow or shortcut letter.
            if item.submenu != nil {
                drawSubmenuArrow(in: r, ctx: ctx)
            } else if let sc = item.shortcut {
                drawText(sc, in: r, font: NeXTChrome.labelFont(13), color: color, align: .right, xInset: 10)
            }
        }
    }

    private func drawText(_ s: String, in r: NSRect, font: NSFont, color: NSColor, align: NSTextAlignment, xInset: CGFloat) {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        let h = (s as NSString).size(withAttributes: attrs).height
        let rect = NSRect(x: r.minX + xInset, y: r.midY - h/2, width: r.width - xInset * 2, height: h)
        (s as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func drawSubmenuArrow(in r: NSRect, ctx: CGContext) {
        let s: CGFloat = 7
        let cx = r.maxX - 12, cy = r.midY
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx - s/2, y: cy - s/2))
        p.line(to: NSPoint(x: cx + s/2, y: cy))
        p.line(to: NSPoint(x: cx - s/2, y: cy + s/2))
        p.close()
        NeXTChrome.darkGray.setStroke(); p.lineWidth = 1.2; p.stroke()
    }

    private func indexAt(_ p: NSPoint) -> Int? {
        for i in items.indices where cellRect(i).contains(p) { return i }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = indexAt(p) else { return }
        hoverIndex = i; needsDisplay = true
        let item = items[i]
        if let sub = item.submenu {
            // Pop the submenu out to the RIGHT, aligned with this cell's top.
            let cellTopInWindow = convert(NSPoint(x: bounds.maxX, y: cellRect(i).minY), to: nil)
            let onScreen = window!.convertPoint(toScreen: cellTopInWindow)
            NextSubmenuPanel.shared.present(items: sub, at: onScreen)
        } else {
            NextSubmenuPanel.shared.dismiss()
            if item.enabled { item.action?() }
        }
    }

    override func mouseUp(with event: NSEvent) {
        hoverIndex = nil; needsDisplay = true
    }
}

// MARK: - Submenu (pops out to the right)

/// A NeXT-styled submenu panel presented to the right of a main-menu cell. Reused (one instance)
/// and dismissed on selection or when it loses the click.
final class NextSubmenuPanel {
    static let shared = NextSubmenuPanel()
    private var panel: NSPanel?
    private var monitor: Any?
    private init() {}

    func present(items: [NextMenuController.Item], at topLeft: NSPoint) {
        dismiss()
        let view = NextSubmenuView(items: items) { [weak self] item in
            self?.dismiss()
            if item.enabled { item.action?() }
        }
        let h = view.preferredHeight()
        let p = NSPanel(contentRect: NSRect(x: topLeft.x, y: topLeft.y - h, width: NextSubmenuView.width, height: h),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: 5)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.contentView = view
        p.orderFront(nil)
        panel = p
        // Dismiss when the user clicks anywhere outside the submenu.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        panel?.orderOut(nil); panel = nil
    }
}

final class NextSubmenuView: NSView {
    static let width: CGFloat = 150
    static let cellH: CGFloat = 21
    private let items: [NextMenuController.Item]
    private let onPick: (NextMenuController.Item) -> Void
    private var hoverIndex: Int? = nil

    init(items: [NextMenuController.Item], onPick: @escaping (NextMenuController.Item) -> Void) {
        self.items = items; self.onPick = onPick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: CGFloat(items.count) * Self.cellH))
        wantsLayer = true
        let track = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(track)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    func preferredHeight() -> CGFloat { CGFloat(items.count) * Self.cellH }

    private func cellRect(_ i: Int) -> NSRect { NSRect(x: 0, y: CGFloat(i) * Self.cellH, width: bounds.width, height: Self.cellH) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NeXTChrome.face.setFill(); ctx.fill(bounds)
        NeXTChrome.bevel(bounds, raised: true, width: 2, flipped: true, in: ctx)
        for (i, item) in items.enumerated() {
            let r = cellRect(i).insetBy(dx: 2, dy: 0)
            NeXTChrome.tile(r, raised: hoverIndex != i, flipped: true, in: ctx)
            let color: NSColor = item.enabled ? .black : NeXTChrome.darkGray
            let p = NSMutableParagraphStyle(); p.alignment = .left
            let attrs: [NSAttributedString.Key: Any] = [.font: NeXTChrome.labelFont(13), .foregroundColor: color, .paragraphStyle: p]
            let th = (item.title as NSString).size(withAttributes: attrs).height
            (item.title as NSString).draw(in: NSRect(x: r.minX + 8, y: r.midY - th/2, width: r.width - 30, height: th), withAttributes: attrs)
            if let sc = item.shortcut {
                let rp = NSMutableParagraphStyle(); rp.alignment = .right
                let ra: [NSAttributedString.Key: Any] = [.font: NeXTChrome.labelFont(13), .foregroundColor: color, .paragraphStyle: rp]
                (sc as NSString).draw(in: NSRect(x: r.minX, y: r.midY - th/2, width: r.width - 10, height: th), withAttributes: ra)
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let idx = items.indices.first { cellRect($0).contains(p) }
        if idx != hoverIndex { hoverIndex = idx; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hoverIndex = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = items.indices.first(where: { cellRect($0).contains(p) }) { onPick(items[i]) }
    }
}
