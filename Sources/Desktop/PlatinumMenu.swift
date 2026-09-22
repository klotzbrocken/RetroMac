import AppKit

/// A Platinum pop-up menu, drawn by RetroMac: #DADADA face inside a black line with a
/// white/grey bevel, Charcoal 12, 16 pt icons, a tick for the chosen row, fly-out submenus.
/// Not an NSMenu — the Apple menu, the Application menu and the Control Strip modules of the
/// "Mac OS 9 (authentic)" theme wear the menus of their day, and (on this macOS) an NSMenu
/// shows no item images at all.
struct PlatinumMenuItem {
    enum Kind {
        case action(() -> Void)
        case submenu([PlatinumMenuItem])
        case separator
    }
    var title: String
    var icon: NSImage? = nil
    var kind: Kind
    var ticked = false
    var dimmed = false

    static func separator() -> PlatinumMenuItem { PlatinumMenuItem(title: "", kind: .separator) }
    static func action(_ title: String, icon: NSImage? = nil, ticked: Bool = false, dimmed: Bool = false, _ run: @escaping () -> Void) -> PlatinumMenuItem {
        PlatinumMenuItem(title: title, icon: icon, kind: .action(run), ticked: ticked, dimmed: dimmed)
    }
    static func submenu(_ title: String, icon: NSImage? = nil, _ items: [PlatinumMenuItem]) -> PlatinumMenuItem {
        PlatinumMenuItem(title: title, icon: icon, kind: .submenu(items))
    }
    static func label(_ title: String) -> PlatinumMenuItem { PlatinumMenuItem(title: title, kind: .action({}), dimmed: true) }

    /// An NSMenu's rows as Platinum rows (a module's menu, built the AppKit way): the same
    /// titles, ticks and enabling, the action sent to its target.
    static func rows(of menu: NSMenu) -> [PlatinumMenuItem] {
        menu.items.map { item in
            if item.isSeparatorItem { return .separator() }
            if let sub = item.submenu { return .submenu(item.title, icon: item.image, rows(of: sub)) }
            let target = item.target, action = item.action
            return .action(item.title, icon: item.image, ticked: item.state == .on, dimmed: !item.isEnabled || action == nil) {
                if let action { NSApp.sendAction(action, to: target, from: item) }
            }
        }
    }
}

final class PlatinumMenuController {
    static let shared = PlatinumMenuController()
    private var panels: [PlatinumMenuPanel] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private init() {}

    static let rowHeight: CGFloat = 20
    static let separatorHeight: CGFloat = 9
    /// Chicago 12 of the day: ChiKareGo2 at its 16 px bitmap size.
    static var font: NSFont { RetroFonts.chicago(16) }
    /// A window whose clicks must not dismiss (the button that opens the menu toggles it itself).
    weak var ignoreClickWindow: NSWindow?
    var isOpen: Bool { !panels.isEmpty }

    /// Show the root menu below `anchor` (screen coordinates, AppKit), left edges aligned;
    /// above it when there is no room below (the Control Strip at the bottom of the screen).
    func show(_ items: [PlatinumMenuItem], below anchor: NSRect) {
        dismissAll()
        let panel = makePanel(items: items, level: 0)
        let size = panel.contentSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        var x = min(max(anchor.minX, vf.minX), vf.maxX - size.width)
        var y = anchor.minY - size.height
        if y < vf.minY { y = anchor.maxY }                          // no room below: open above
        y = max(vf.minY, min(y, vf.maxY - size.height))
        x = max(vf.minX, x)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        panels = [panel]
        installMonitors()
    }

    fileprivate func openSubmenu(_ items: [PlatinumMenuItem], from parent: PlatinumMenuPanel, rowRectInScreen: NSRect, level: Int) {
        while panels.count > level { panels.removeLast().orderOut(nil) }
        let panel = makePanel(items: items, level: level)
        let size = panel.contentSize
        let screen = NSScreen.screens.first { $0.frame.intersects(rowRectInScreen) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        var x = parent.frame.maxX - 1
        if x + size.width > vf.maxX { x = parent.frame.minX - size.width + 1 }
        var y = rowRectInScreen.maxY - size.height + 1   // the first row level with the parent row
        y = max(vf.minY, min(y, vf.maxY - size.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    fileprivate func closeDeeperThan(_ level: Int) {
        while panels.count > level + 1 { panels.removeLast().orderOut(nil) }
    }

    func dismissAll() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func makePanel(items: [PlatinumMenuItem], level: Int) -> PlatinumMenuPanel {
        let view = PlatinumMenuView(items: items, level: level, controller: self)
        view.maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 8
        let panel = PlatinumMenuPanel(contentRect: NSRect(origin: .zero, size: view.intrinsicSize),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false   // the drawn 1 px shadow is the shadow
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        view.frame = NSRect(origin: .zero, size: view.intrinsicSize)
        panel.contentView = view
        panel.contentSize = view.intrinsicSize
        view.ownerPanel = panel
        return panel
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissAll()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if let w = event.window as? PlatinumMenuPanel, self.panels.contains(w) { return event }
            if let ignore = self.ignoreClickWindow, event.window === ignore { return event }
            self.dismissAll()
            return event
        }
    }
}

final class PlatinumMenuPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    var contentSize: NSSize = .zero
}

private final class PlatinumMenuView: NSView {
    private let items: [PlatinumMenuItem]
    private let level: Int
    private weak var controller: PlatinumMenuController?
    weak var ownerPanel: PlatinumMenuPanel?
    private var hovered = -1
    private var trackingArea: NSTrackingArea?
    /// A menu taller than the screen scrolls, the Mac OS 9 way: an arrow row at either end,
    /// hovering it rolls the rows past, one every tenth of a second.
    var maxHeight: CGFloat = .greatestFiniteMagnitude
    private var firstRow = 0
    private var scrollTimer: Timer?
    private var fullHeight: CGFloat { 4 + items.reduce(0) { $0 + (isSeparator($1) ? sepH : rowH) } }
    private var scrolls: Bool { fullHeight > maxHeight }

    private let rowH = PlatinumMenuController.rowHeight
    private let sepH = PlatinumMenuController.separatorHeight
    /// Four greys (System 7.1 (authentic)): a white menu in a black line with a 1 px shadow,
    /// the selected row inverted, dimmed rows in #AAAAAA; else Platinum.
    private let mono = FourGrays.active
    /// The rows' icons in 1 bit, converted once per menu (the conversion walks every pixel).
    private var monoIcons: [Int: NSImage] = [:]
    private func monoIcon(_ row: Int, _ icon: NSImage) -> NSImage {
        if let c = monoIcons[row] { return c }
        let bit = FourGrays.quantize(icon, points: 16, scale: window?.backingScaleFactor ?? 2); monoIcons[row] = bit; return bit
    }
    private var face: NSColor { mono ? .white : NSColor(srgbRed: 0.855, green: 0.855, blue: 0.855, alpha: 1) }      // #DADADA
    private var highlight: NSColor { mono ? .black : NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1) }      // the Platinum "Blue" highlight
    private var textDim: NSColor { mono ? FourGrays.light : NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1) }
    private let iconColumn: CGFloat = 26

    var intrinsicSize: NSSize {
        let font = PlatinumMenuController.font
        var maxW: CGFloat = 100
        let hasIcons = items.contains { $0.icon != nil }
        for it in items where !it.title.isEmpty {
            let w = it.title.size(withAttributes: [.font: font]).width
            maxW = max(maxW, w + 16 + (hasIcons ? iconColumn : 0) + 16 + 12)   // tick column, icon, arrow room
        }
        let h = min(fullHeight, maxHeight)
        return NSSize(width: min(max(maxW.rounded(.up), 140), 360), height: h)
    }

    init(items: [PlatinumMenuItem], level: Int, controller: PlatinumMenuController) {
        self.items = items; self.level = level; self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 200, height: 200)))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func isSeparator(_ it: PlatinumMenuItem) -> Bool { if case .separator = it.kind { return true }; return false }
    private var hasIcons: Bool { items.contains { $0.icon != nil } }

    /// Where a row sits; rows scrolled past sit above the top and are not drawn or hit.
    private func rowRect(_ i: Int) -> NSRect {
        var y: CGFloat = 2 + (scrolls ? rowH : 0)   // below the up-arrow row when scrolling
        for j in 0..<i { y += isSeparator(items[j]) ? sepH : rowH }
        for j in 0..<min(firstRow, items.count) { y -= isSeparator(items[j]) ? sepH : rowH }
        let h = isSeparator(items[i]) ? sepH : rowH
        return NSRect(x: 1, y: y, width: bounds.width - 3, height: h)   // inside the line and the shadow
    }
    private var upArrowRect: NSRect { NSRect(x: 1, y: 2, width: bounds.width - 3, height: rowH) }
    private var downArrowRect: NSRect { NSRect(x: 1, y: bounds.height - 3 - rowH, width: bounds.width - 3, height: rowH) }
    /// The band the rows may show in: between the arrow rows.
    private var rowBand: NSRect { scrolls ? NSRect(x: 0, y: upArrowRect.maxY, width: bounds.width, height: downArrowRect.minY - upArrowRect.maxY) : bounds }
    private var canScrollDown: Bool { scrolls && (rowRect(items.count - 1).maxY > rowBand.maxY + 0.5) }
    private var canScrollUp: Bool { scrolls && firstRow > 0 }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        // The menu's own shadow: one dark line below and to the right, as os9.ca draws it.
        NSColor(white: 0.067, alpha: 1).setFill()
        NSRect(x: 1, y: 1, width: b.width - 1, height: b.height - 1).fill()
        let box = NSRect(x: 0, y: 0, width: b.width - 1, height: b.height - 1)
        face.setFill(); box.fill()
        NSColor.black.setFill()
        NSRect(x: box.minX, y: box.minY, width: box.width, height: 1).fill()
        NSRect(x: box.minX, y: box.maxY - 1, width: box.width, height: 1).fill()
        NSRect(x: box.minX, y: box.minY, width: 1, height: box.height).fill()
        NSRect(x: box.maxX - 1, y: box.minY, width: 1, height: box.height).fill()
        if !mono {   // the Platinum bevel; a 1-bit menu is a plain black line
            NSColor.white.setFill()
            NSRect(x: 1, y: 1, width: box.width - 2, height: 1).fill()
            NSRect(x: 1, y: 1, width: 1, height: box.height - 2).fill()
            NSColor(white: 0.6, alpha: 1).setFill()
            NSRect(x: 1, y: box.maxY - 2, width: box.width - 2, height: 1).fill()
            NSRect(x: box.maxX - 2, y: 1, width: 1, height: box.height - 2).fill()
        }

        let font = PlatinumMenuController.font
        let icons = hasIcons
        if scrolls {
            NSGraphicsContext.current?.saveGraphicsState()
            rowBand.clip()
        }
        for (i, it) in items.enumerated() {
            let r = rowRect(i)
            if scrolls, r.maxY <= rowBand.minY || r.minY >= rowBand.maxY { continue }
            if isSeparator(it) {
                if mono {
                    FourGrays.dark.setFill(); NSRect(x: r.minX + 1, y: r.midY.rounded(), width: r.width - 2, height: 1).fill()
                    continue
                }
                NSColor(white: 0.6, alpha: 1).setFill(); NSRect(x: r.minX + 1, y: r.midY.rounded() - 1, width: r.width - 2, height: 1).fill()
                NSColor.white.setFill(); NSRect(x: r.minX + 1, y: r.midY.rounded(), width: r.width - 2, height: 1).fill()
                continue
            }
            let selected = i == hovered && !it.dimmed
            if selected { highlight.setFill(); r.fill() }
            let colour = it.dimmed ? textDim : (selected ? NSColor.white : NSColor.black)
            var x = r.minX + 16   // the tick column
            if it.ticked {
                // A tick, in the row's text colour.
                let p = NSBezierPath()
                p.move(to: NSPoint(x: r.minX + 5, y: r.midY)); p.line(to: NSPoint(x: r.minX + 8, y: r.midY + 3)); p.line(to: NSPoint(x: r.minX + 13, y: r.midY - 4))
                p.lineWidth = 2; colour.setStroke(); p.stroke()
            }
            if icons {
                if let icon = it.icon {
                    // Inverted with the row on a 1-bit menu, as the Finder's icons were.
                    let pic = mono ? monoIcon(i, icon) : icon
                    pic.draw(in: NSRect(x: x, y: r.midY - 8, width: 16, height: 16), from: .zero,
                             operation: mono && selected ? .difference : .sourceOver,
                             fraction: it.dimmed ? 0.5 : 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
                }
                x += iconColumn
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
            let ts = it.title.size(withAttributes: attrs)
            it.title.draw(at: NSPoint(x: x, y: (r.midY - ts.height / 2).rounded()), withAttributes: attrs)
            if case .submenu = it.kind {
                let ax = r.maxX - 12, ay = r.midY
                let p = NSBezierPath()
                p.move(to: NSPoint(x: ax, y: ay - 4)); p.line(to: NSPoint(x: ax + 5, y: ay)); p.line(to: NSPoint(x: ax, y: ay + 4)); p.close()
                colour.setFill(); p.fill()
            }
        }
        if scrolls {
            NSGraphicsContext.current?.restoreGraphicsState()
            face.setFill(); upArrowRect.fill(); downArrowRect.fill()
            for (rect, up, on) in [(upArrowRect, true, canScrollUp), (downArrowRect, false, canScrollDown)] {
                let p = NSBezierPath()
                let cx = rect.midX, cy = rect.midY
                if up { p.move(to: NSPoint(x: cx - 4, y: cy + 2)); p.line(to: NSPoint(x: cx, y: cy - 2)); p.line(to: NSPoint(x: cx + 4, y: cy + 2)) }
                else { p.move(to: NSPoint(x: cx - 4, y: cy - 2)); p.line(to: NSPoint(x: cx, y: cy + 2)); p.line(to: NSPoint(x: cx + 4, y: cy - 2)) }
                p.close()
                (on ? NSColor.black : (mono ? FourGrays.light : NSColor(white: 0.6, alpha: 1))).setFill(); p.fill()
            }
        }
    }

    private func scroll(by delta: Int) {
        let next = firstRow + delta
        guard next >= 0, next < items.count, delta < 0 || canScrollDown else { return }
        firstRow = next
        hovered = -1
        needsDisplay = true
    }

    private func armScroll(_ delta: Int) {
        guard scrollTimer == nil else { return }
        scroll(by: delta)
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.scroll(by: delta) }
    }
    private func disarmScroll() { scrollTimer?.invalidate(); scrollTimer = nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(t); trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if scrolls {
            if upArrowRect.contains(p) { armScroll(-1); return }
            if downArrowRect.contains(p) { armScroll(1); return }
            disarmScroll()
        }
        let old = hovered
        hovered = -1
        for i in items.indices where !isSeparator(items[i]) && rowRect(i).contains(p) && rowBand.contains(p) { hovered = i }
        if old != hovered {
            needsDisplay = true
            controller?.closeDeeperThan(level)
            if hovered >= 0, case .submenu(let sub) = items[hovered].kind { openChild(sub, rowIndex: hovered) }
        }
    }

    override func mouseExited(with event: NSEvent) { disarmScroll() /* the highlight stays so a submenu remains reachable */ }

    /// The trackpad rolls a long menu too: a row per 12 points of travel.
    private var wheelRemainder: CGFloat = 0
    override func scrollWheel(with event: NSEvent) {
        guard scrolls else { return }
        // Natural scrolling arrives already inverted: a positive delta means "show what
        // is above", exactly as a document scrolls.
        wheelRemainder += event.scrollingDeltaY
        let rows = Int(wheelRemainder / 12)
        if rows != 0 {
            wheelRemainder -= CGFloat(rows) * 12
            scroll(by: -rows)
            mouseMoved(with: event)   // re-evaluate the row under the pointer
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if scrolls, !rowBand.contains(p) { return }
        for i in items.indices where rowRect(i).contains(p) {
            switch items[i].kind {
            case .action(let run): if !items[i].dimmed { controller?.dismissAll(); run() }
            case .submenu(let sub): openChild(sub, rowIndex: i)
            case .separator: break
            }
            return
        }
    }

    private func openChild(_ sub: [PlatinumMenuItem], rowIndex: Int) {
        guard let panel = ownerPanel else { return }
        let inScreen = panel.convertToScreen(convert(rowRect(rowIndex), to: nil))
        controller?.openSubmenu(sub, from: panel, rowRectInScreen: inScreen, level: level + 1)
    }
}
