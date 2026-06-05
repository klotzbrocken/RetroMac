import AppKit

/// A custom, BeOS-styled pop-up menu (light-gray face, chiselled bevels, icon rows,
/// fly-out submenus) — deliberately NOT an NSMenu so it matches the original Deskbar look.
struct BeOSMenuItem {
    enum Kind {
        case action(() -> Void)
        case submenu([BeOSMenuItem])
        case separator
    }
    var title: String
    var icon: NSImage?
    var kind: Kind
    /// App bundle id — enables the right-click "Set Custom Icon…" context menu.
    var bundleID: String? = nil

    static func separator() -> BeOSMenuItem { BeOSMenuItem(title: "", icon: nil, kind: .separator) }
    static func action(_ title: String, icon: NSImage? = nil, bundleID: String? = nil, _ run: @escaping () -> Void) -> BeOSMenuItem {
        BeOSMenuItem(title: title, icon: icon, kind: .action(run), bundleID: bundleID)
    }
    static func submenu(_ title: String, icon: NSImage? = nil, _ items: [BeOSMenuItem]) -> BeOSMenuItem {
        BeOSMenuItem(title: title, icon: icon, kind: .submenu(items))
    }
}

final class BeOSMenuController {
    static let shared = BeOSMenuController()
    private var panels: [BeOSMenuPanel] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onDismiss: (() -> Void)?
    private init() {}

    /// Display sizing scaled up a touch from the macOS default (the user wants larger entries).
    static var rowHeight: CGFloat = 26
    static var fontSize: CGFloat = 14.5
    static var menuWidth: CGFloat = 220
    /// BeOS used Swiss 721 BT (a Helvetica clone). Helvetica is the closest match shipping
    /// on macOS; fall back to the system font if unavailable.
    static var menuFont: NSFont { NSFont(name: "Helvetica", size: fontSize) ?? .systemFont(ofSize: fontSize) }
    /// A window whose clicks the dismiss-monitor should IGNORE (the Be button), so clicking
    /// the button while the menu is open closes it via the button's own toggle instead of
    /// being dismissed here and immediately reopened.
    weak var ignoreClickWindow: NSWindow?

    var isOpen: Bool { !panels.isEmpty }

    /// Show the root menu. `openUp` opens above the anchor (deskbar at the bottom),
    /// `openLeft` makes the root left-aligned to the anchor's right edge (right-side corners).
    private var openUpState = false

    func show(_ items: [BeOSMenuItem], anchor: NSRect, openUp: Bool, openLeft: Bool) {
        dismissAll()
        openUpState = openUp
        // Growing upward (bottom corners) → reverse so the first entry sits nearest the logo.
        let display = openUp ? Array(items.reversed()) : items
        let panel = makePanel(items: display, level: 0, openLeft: openLeft)
        let size = panel.contentSize
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main!
        let vf = screen.visibleFrame
        // Open BESIDE the Be logo (flyout), not over it: left corners → to the right,
        // right corners → to the left, flipping if it would run off-screen.
        var x = openLeft ? (anchor.minX - size.width) : anchor.maxX
        if x + size.width > vf.maxX - 2 { x = anchor.minX - size.width }
        if x < vf.minX + 2 { x = anchor.maxX }
        x = min(max(x, vf.minX + 2), vf.maxX - size.width - 2)
        // Grow upward from the logo for bottom corners, downward for top corners.
        var y = openUp ? anchor.minY : (anchor.maxY - size.height)
        y = max(vf.minY + 2, min(y, vf.maxY - size.height - 2))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        panels = [panel]
        installMonitors()
    }

    fileprivate func openSubmenu(_ items: [BeOSMenuItem], from parent: BeOSMenuPanel, rowRectInScreen: NSRect, level: Int, openLeft: Bool) {
        // Close any deeper panels first.
        while panels.count > level { panels.removeLast().orderOut(nil) }
        let display = openUpState ? Array(items.reversed()) : items
        let panel = makePanel(items: display, level: level, openLeft: openLeft)
        let size = panel.contentSize
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rowRectInScreen) }) ?? NSScreen.main!
        let vf = screen.visibleFrame
        var x = openLeft ? (parent.frame.minX - size.width + 2) : (parent.frame.maxX - 2)
        if x + size.width > vf.maxX - 2 { x = parent.frame.minX - size.width + 2 }   // flip
        if x < vf.minX + 2 { x = parent.frame.maxX - 2 }
        // Grow upward (reversed) → bottom-align the submenu with the parent row; else top-align.
        var y = openUpState ? rowRectInScreen.minY : (rowRectInScreen.maxY - size.height)
        y = max(vf.minY + 2, min(y, vf.maxY - size.height - 2))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    fileprivate func closeDeeperThan(_ level: Int) {
        while panels.count > level + 1 { panels.removeLast().orderOut(nil) }
    }

    func dismissAll() {
        let wasOpen = !panels.isEmpty
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if wasOpen { let cb = onDismiss; onDismiss = nil; cb?() }
    }

    private func makePanel(items: [BeOSMenuItem], level: Int, openLeft: Bool) -> BeOSMenuPanel {
        let view = BeOSMenuView(items: items, level: level, openLeft: openLeft, controller: self)
        let panel = BeOSMenuPanel(contentRect: NSRect(origin: .zero, size: view.intrinsicSize),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: 26)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        view.frame = NSRect(origin: .zero, size: view.intrinsicSize)
        panel.contentView = view
        panel.contentSize = view.intrinsicSize
        view.ownerPanel = panel
        return panel
    }

    fileprivate func panel(at level: Int) -> BeOSMenuPanel? { level < panels.count ? panels[level] : nil }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissAll()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if let w = event.window as? BeOSMenuPanel, self.panels.contains(w) { return event }  // click inside menu
            if let ignore = self.ignoreClickWindow, event.window === ignore { return event }      // Be button toggles itself
            self.dismissAll()
            return event
        }
    }
}

final class BeOSMenuPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    var contentSize: NSSize = .zero
}

private final class BeOSMenuView: NSView {
    private let items: [BeOSMenuItem]
    private let level: Int
    private let openLeft: Bool
    private weak var controller: BeOSMenuController?
    weak var ownerPanel: BeOSMenuPanel?
    private var hovered = -1
    private var trackingArea: NSTrackingArea?

    private let rowH = BeOSMenuController.rowHeight
    private let pad: CGFloat = 2
    private let face = NSColor(calibratedWhite: 0.855, alpha: 1)
    private let hi   = NSColor(calibratedRed: 0.27, green: 0.45, blue: 0.78, alpha: 1)   // BeOS-blue selection
    private let light = NSColor(calibratedWhite: 1.0, alpha: 1)
    private let dark  = NSColor(calibratedWhite: 0.45, alpha: 1)

    var intrinsicSize: NSSize {
        let font = BeOSMenuController.menuFont
        var maxW: CGFloat = 120
        for it in items where it.title.isEmpty == false {
            let w = it.title.size(withAttributes: [.font: font]).width
            maxW = max(maxW, w + 64)
        }
        let h = pad * 2 + items.reduce(0) { $0 + (isSeparator($1) ? 6 : rowH) }
        return NSSize(width: min(max(maxW, 180), 320), height: h)
    }

    init(items: [BeOSMenuItem], level: Int, openLeft: Bool, controller: BeOSMenuController) {
        self.items = items; self.level = level; self.openLeft = openLeft; self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 200)))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func isSeparator(_ it: BeOSMenuItem) -> Bool { if case .separator = it.kind { return true }; return false }

    private func rowRect(_ i: Int) -> NSRect {
        var y = pad
        for j in 0..<i { y += isSeparator(items[j]) ? 6 : rowH }
        let h = isSeparator(items[i]) ? 6 : rowH
        return NSRect(x: pad, y: y, width: bounds.width - pad * 2, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        face.setFill(); bounds.fill()
        // Outer chiselled border.
        light.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        dark.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()

        let font = BeOSMenuController.menuFont
        for (i, it) in items.enumerated() {
            let r = rowRect(i)
            if isSeparator(it) {
                dark.setFill(); NSRect(x: r.minX + 3, y: r.midY - 1, width: r.width - 6, height: 1).fill()
                light.setFill(); NSRect(x: r.minX + 3, y: r.midY, width: r.width - 6, height: 1).fill()
                continue
            }
            let selected = i == hovered
            if selected { hi.setFill(); r.insetBy(dx: 1, dy: 0).fill() }
            let textColor = selected ? NSColor.white : NSColor(calibratedWhite: 0.08, alpha: 1)
            if let icon = it.icon {
                icon.draw(in: NSRect(x: r.minX + 5, y: r.midY - 9, width: 18, height: 18),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let ts = it.title.size(withAttributes: attrs)
            it.title.draw(at: NSPoint(x: r.minX + 28, y: r.midY - ts.height / 2), withAttributes: attrs)
            if case .submenu = it.kind {   // right-pointing triangle
                let ax = r.maxX - 12, ay = r.midY
                let p = NSBezierPath()
                p.move(to: NSPoint(x: ax, y: ay - 4)); p.line(to: NSPoint(x: ax + 6, y: ay)); p.line(to: NSPoint(x: ax, y: ay + 4)); p.close()
                (selected ? NSColor.white : NSColor.black).setFill(); p.fill()
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
        let old = hovered
        hovered = -1
        for i in items.indices where !isSeparator(items[i]) && rowRect(i).contains(p) { hovered = i }
        if old != hovered {
            needsDisplay = true
            controller?.closeDeeperThan(level)
            if hovered >= 0, case .submenu(let sub) = items[hovered].kind {
                openChild(sub, rowIndex: hovered)
            }
        }
    }

    override func mouseExited(with event: NSEvent) { /* keep highlight so submenu stays reachable */ }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in items.indices where rowRect(i).contains(p) {
            guard let bid = items[i].bundleID else { return }
            CustomIconPicker.present(for: bid, in: self, at: p) { [weak self] in self?.controller?.dismissAll() }
            return
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in items.indices where rowRect(i).contains(p) {
            switch items[i].kind {
            case .action(let run): controller?.dismissAll(); run()
            case .submenu(let sub): openChild(sub, rowIndex: i)
            case .separator: break
            }
            return
        }
    }

    private func openChild(_ sub: [BeOSMenuItem], rowIndex: Int) {
        guard let panel = ownerPanel else { return }
        let rr = rowRect(rowIndex)
        // row rect → screen coords
        let inWindow = convert(rr, to: nil)
        let inScreen = panel.convertToScreen(inWindow)
        controller?.openSubmenu(sub, from: panel, rowRectInScreen: inScreen, level: level + 1, openLeft: openLeft)
    }
}
