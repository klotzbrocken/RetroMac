import AppKit

/// The NeXTSTEP "File Viewer" — the workspace's file/app browser, rebuilt from the original: a
/// shelf of category folders (Me / NextApps / Demos) across the top, a status line, and a grid of
/// icons for the selected shelf item. Wrapped in `NextWindowFrameView` (black title bar,
/// miniaturize-left / close-right, chiseled frame). Opened from the dock's Workspace tile and the
/// Workspace menu.
///
///  • **Me**       — no function (a placeholder home shelf, as requested)
///  • **NextApps** — every installed application; click launches it
///  • **Demos**    — the TV/stream bookmarks; click starts the stream in Tube mode
final class NextAppsWindowController {

    static let shared = NextAppsWindowController()
    private var window: NSPanel?
    private init() {}

    func toggle() { if window != nil { close() } else { show() } }

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 452, height: 524),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating
        let root = NextWindowFrameView(title: "File Viewer", onClose: { [weak self] in self?.close() })
        root.embed(NextFileViewerView(frame: root.contentRect()))
        panel.contentView = root
        if let f = NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x: f.midX - 226, y: f.midY - 262)) }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }
    func close() { window?.orderOut(nil); window = nil }
}

// MARK: - File Viewer content (shelf + status + icon grid)

struct NextFileItem { let name: String; let icon: NSImage; let action: () -> Void }

final class NextFileViewerView: NSView {
    private enum Category: Int, CaseIterable { case me, apps, demos
        var label: String { self == .me ? "me" : (self == .apps ? "NextApps" : "Demos") }
    }

    private var category: Category = .apps
    private let shelfH: CGFloat = 74
    private let statusH: CGFloat = 18
    private let pathH: CGFloat = 84      // the "current location" pane (host + opened drawer)
    private let paneInset: CGFloat = 2
    private var itemCount = 0

    private let scroll = NSScrollView()
    private let grid = NextFileGridView(frame: .zero)
    private let scroller = NextScroller()
    private let scrollerW: CGFloat = 18

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        scroll.hasVerticalScroller = false      // the native scroller is replaced by NextScroller (left)
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.drawsBackground = true
        scroll.backgroundColor = NeXTChrome.face
        scroll.borderType = .noBorder
        scroll.documentView = grid
        scroll.contentView.postsBoundsChangedNotifications = true
        addSubview(scroll)
        scroller.attach(to: scroll)             // authentic NeXT scroller on the LEFT
        addSubview(scroller)
        layoutScroll()
        reload()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); layoutScroll() }
    private func pathPaneRect() -> NSRect { NSRect(x: 2, y: shelfH + statusH, width: bounds.width - 4, height: pathH - 2) }
    private func contentPaneRect() -> NSRect {
        let top = shelfH + statusH + pathH
        return NSRect(x: 2, y: top, width: bounds.width - 4, height: bounds.height - top - 2)
    }
    private func layoutScroll() {
        let pane = contentPaneRect().insetBy(dx: paneInset, dy: paneInset)
        scroller.frame = NSRect(x: pane.minX, y: pane.minY, width: scrollerW, height: pane.height)
        scroll.frame = NSRect(x: pane.minX + scrollerW, y: pane.minY, width: pane.width - scrollerW, height: pane.height)
        grid.relayout(width: scroll.contentSize.width)
        scroller.refresh()
    }

    private func themeIcon(_ name: String) -> NSImage {
        ThemeManager.shared.activeTheme?.iconResource(name).flatMap { NSImage(contentsOf: $0) } ?? NSImage()
    }

    private func reload() {
        let items: [NextFileItem]
        switch category {
        case .me:    items = []
        case .apps:  items = installedApps()
        case .demos: items = AppSettings.shared.tvBookmarks.map { bm in
            NextFileItem(name: bm.name, icon: themeIcon("nx_media.png"),
                         action: { TubeModeController.shared.startOnBookmark(url: bm.url) }) }
        }
        itemCount = items.count
        grid.setItems(items, emptyDash: category == .me)
        grid.relayout(width: scroll.contentSize.width)
        scroll.contentView.scroll(to: .zero)   // reset to top on category switch
        scroller.refresh()
        needsDisplay = true
    }

    private func installedApps() -> [NextFileItem] {
        let fm = FileManager.default
        var seen = Set<String>(); var out: [NextFileItem] = []
        for dir in ["/Applications", "/System/Applications", "/Applications/Utilities"] {
            for item in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where item.hasSuffix(".app") {
                let name = String(item.dropLast(4))
                guard seen.insert(name).inserted else { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
                let icon = NSWorkspace.shared.icon(forFile: url.path); icon.size = NSSize(width: 48, height: 48)
                out.append(NextFileItem(name: name, icon: icon, action: { NSWorkspace.shared.open(url) }))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // The header (shelf + status) is painted by this view; the grid scrolls below it.
    private func shelfRects() -> [NSRect] {
        Category.allCases.enumerated().map { i, _ in NSRect(x: 12 + CGFloat(i) * 92, y: 8, width: 80, height: shelfH - 10) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NeXTChrome.face.setFill(); ctx.fill(bounds)
        let shelf = NSRect(x: 0, y: 0, width: bounds.width, height: shelfH)
        NeXTChrome.bevel(shelf, raised: false, flipped: true, in: ctx)
        for (i, r) in shelfRects().enumerated() {
            let cat = Category.allCases[i]
            // Free (tile-less) variants: the shelf drawers/house float on the grey face, as the
            // original File Viewer showed them (no silver dock tile behind).
            themeIcon(cat == .me ? "nx_home_free.png" : "nx_folder_free.png").draw(in: NSRect(x: r.midX - 24, y: r.minY, width: 48, height: 48))
            if cat == category { NeXTChrome.black.withAlphaComponent(0.10).setFill(); ctx.fill(NSRect(x: r.midX - 34, y: r.minY + 50, width: 68, height: 15)) }
            drawLabel(cat.label, x: r.midX - 44, w: 88, y: r.minY + 50, align: .center)
        }
        drawLabel(statusText(), x: 10, w: bounds.width - 20, y: shelfH + 2, align: .left)
        // Path pane (recessed): the current location as icons — host machine + opened drawer.
        let pp = pathPaneRect()
        NeXTChrome.face.setFill(); ctx.fill(pp)
        NeXTChrome.bevel(pp, raised: false, flipped: true, in: ctx)
        drawPath(pp, ctx: ctx)
        // Content pane (recessed border; the scroller + grid fill its interior).
        NeXTChrome.bevel(contentPaneRect(), raised: false, flipped: true, in: ctx)
    }

    /// The "current location" strip the real File Viewer showed above the icon grid: the host
    /// machine icon, then the opened container — both freed (tile-less), floating on the grey pane
    /// like the shelf drawers above (no white box behind them).
    private func drawPath(_ pane: NSRect, ctx: CGContext) {
        let iy = pane.minY + 8
        themeIcon("nx_media_free.png").draw(in: NSRect(x: pane.minX + 18, y: iy, width: 48, height: 48))
        drawLabel(hostName(), x: pane.minX - 4, w: 88, y: iy + 50, align: .center)
        let dx = pane.minX + 110
        themeIcon(category == .me ? "nx_home_free.png" : "nx_folder_free.png").draw(in: NSRect(x: dx, y: iy, width: 48, height: 48))
        drawLabel(category.label, x: dx - 20, w: 88, y: iy + 50, align: .center)
    }

    private func hostName() -> String {
        let n = Host.current().localizedName ?? "NeXT"
        return n.count > 12 ? String(n.prefix(12)) : n
    }

    private func statusText() -> String {
        switch category {
        case .apps:  return "\(itemCount) applications"
        case .demos: return "\(itemCount) streams"
        case .me:    return diskFree()
        }
    }
    private func diskFree() -> String {
        if let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let bytes = v.volumeAvailableCapacity { return "\(bytes / 1_000_000_000) GB available on hard disk" }
        return "available on hard disk"
    }
    private func drawLabel(_ s: String, x: CGFloat, w: CGFloat, y: CGFloat, align: NSTextAlignment) {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byTruncatingTail
        let a: [NSAttributedString.Key: Any] = [.font: NeXTChrome.labelFont(12), .foregroundColor: NSColor.black, .paragraphStyle: p]
        (s as NSString).draw(in: NSRect(x: x, y: y, width: w, height: 14), withAttributes: a)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, r) in shelfRects().enumerated() where r.insetBy(dx: -6, dy: -4).contains(p) {
            category = Category.allCases[i]; reload(); return
        }
    }
}

/// Scrollable icon grid — the File Viewer's document view. Sizes itself to its content height so
/// the surrounding `NSScrollView` scrolls when there are more items than fit.
final class NextFileGridView: NSView {
    private let cell = NSSize(width: 96, height: 74)
    private var items: [NextFileItem] = []
    private var emptyDash = false
    private var cols = 4
    private var hover: Int? = nil

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func setItems(_ i: [NextFileItem], emptyDash: Bool) { items = i; self.emptyDash = emptyDash; needsDisplay = true }

    func relayout(width: CGFloat) {
        guard width > 0 else { return }
        cols = max(1, Int(width / cell.width))
        let rows = max(1, Int(ceil(Double(items.count) / Double(cols))))
        setFrameSize(NSSize(width: width, height: max(1, CGFloat(rows) * cell.height)))
        needsDisplay = true
    }

    private func itemRect(_ i: Int) -> NSRect {
        let c = i % cols, r = i / cols
        return NSRect(x: CGFloat(c) * cell.width + 6, y: CGFloat(r) * cell.height + 6, width: cell.width - 12, height: cell.height - 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        NeXTChrome.face.setFill(); dirtyRect.fill()
        for (i, it) in items.enumerated() {
            let r = itemRect(i); guard r.intersects(dirtyRect) else { continue }
            if hover == i { NeXTChrome.black.withAlphaComponent(0.10).setFill(); r.insetBy(dx: -2, dy: -2).fill() }
            it.icon.draw(in: NSRect(x: r.midX - 24, y: r.minY, width: 48, height: 48))
            let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingTail
            let a: [NSAttributedString.Key: Any] = [.font: NeXTChrome.labelFont(12), .foregroundColor: NSColor.black, .paragraphStyle: p]
            (it.name as NSString).draw(in: NSRect(x: r.midX - 44, y: r.minY + 50, width: 88, height: 14), withAttributes: a)
        }
        if items.isEmpty && emptyDash {
            let p = NSMutableParagraphStyle(); p.alignment = .center
            ("\u{2014}" as NSString).draw(in: NSRect(x: 0, y: 30, width: bounds.width, height: 16),
                withAttributes: [.font: NeXTChrome.labelFont(14), .foregroundColor: NeXTChrome.darkGray, .paragraphStyle: p])
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let idx = items.indices.first { itemRect($0).insetBy(dx: -2, dy: -2).contains(p) }
        if idx != hover { hover = idx; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = items.indices.first(where: { itemRect($0).contains(p) }) { items[i].action() }
    }
}

// MARK: - Authentic NeXT scroller (left side, arrows grouped at the bottom)

/// The NeXTSTEP vertical scroller, rebuilt from the reference File Viewer: a recessed well filled
/// with a 50% grey dither, a raised knob with a centre dimple, and — the signature detail — both
/// arrow buttons STACKED at the very bottom (up above down). It drives an `NSScrollView`'s clip view
/// directly (the native scroller is hidden) so it can sit on the LEFT of the content, as NeXT did.
final class NextScroller: NSView {
    private weak var scrollView: NSScrollView?
    private let arrowH: CGFloat = 15
    private let inset: CGFloat = 2
    private let minKnob: CGFloat = 24
    private let lineStep: CGFloat = 32

    // A 2×2 checkerboard of #555/#AAA — the classic NeXT scroller trough stipple.
    private static let dither: NSColor = {
        let img = NSImage(size: NSSize(width: 2, height: 2))
        img.lockFocus()
        NeXTChrome.face.setFill();     NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        NeXTChrome.darkGray.setFill(); NSRect(x: 0, y: 0, width: 1, height: 1).fill(); NSRect(x: 1, y: 1, width: 1, height: 1).fill()
        img.unlockFocus()
        return NSColor(patternImage: img)
    }()

    override var isFlipped: Bool { true }

    func attach(to sv: NSScrollView) {
        scrollView = sv
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: sv.contentView)
    }
    @objc private func scrolled() { needsDisplay = true }
    func refresh() { needsDisplay = true }

    // MARK: geometry
    private struct Regions { let up: NSRect; let down: NSRect; let trough: NSRect; let knob: NSRect }

    private func metrics() -> (visible: CGFloat, total: CGFloat, offset: CGFloat, maxOff: CGFloat) {
        guard let clip = scrollView?.contentView, let doc = scrollView?.documentView else { return (0, 0, 0, 0) }
        let visible = clip.bounds.height, total = max(doc.frame.height, visible)
        return (visible, total, clip.bounds.origin.y, max(0, total - visible))
    }

    private func regions() -> Regions {
        let iX = inset, iW = bounds.width - inset * 2
        let down = NSRect(x: iX, y: bounds.height - inset - arrowH, width: iW, height: arrowH)
        let up   = NSRect(x: iX, y: down.minY - arrowH, width: iW, height: arrowH)
        let trough = NSRect(x: iX, y: inset, width: iW, height: up.minY - 1 - inset)
        let m = metrics()
        let knobLen = m.total > m.visible ? max(minKnob, trough.height * m.visible / m.total) : trough.height
        let frac = m.maxOff > 0 ? m.offset / m.maxOff : 0
        let knobY = trough.minY + frac * (trough.height - knobLen)
        let knob = NSRect(x: iX, y: knobY, width: iW, height: knobLen)
        return Regions(up: up, down: down, trough: trough, knob: knob)
    }

    // MARK: drawing
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NeXTChrome.face.setFill(); ctx.fill(bounds)
        NeXTChrome.bevel(bounds, raised: false, flipped: true, in: ctx)   // recessed outer well
        let R = regions()
        // Trough stipple.
        Self.dither.setFill(); ctx.fill(R.trough)
        // Knob: raised grey tile with a centre dimple.
        let fits = metrics().total <= metrics().visible
        NeXTChrome.tile(R.knob, raised: true, flipped: true, in: ctx)
        if !fits { drawDimple(R.knob, ctx: ctx) }
        // Arrow buttons (up above down), both grouped at the bottom.
        NeXTChrome.tile(R.up, raised: pressed != .up, flipped: true, in: ctx);   drawTriangle(R.up, up: true)
        NeXTChrome.tile(R.down, raised: pressed != .down, flipped: true, in: ctx); drawTriangle(R.down, up: false)
    }

    private func drawDimple(_ knob: NSRect, ctx: CGContext) {
        let d: CGFloat = 7
        let c = NSRect(x: knob.midX - d/2, y: knob.midY - d/2, width: d, height: d)
        NeXTChrome.darkGray.setFill(); ctx.fillEllipse(in: c)                        // recessed hole
        NeXTChrome.white.setFill(); ctx.fillEllipse(in: c.offsetBy(dx: 1.5, dy: 1.5).insetBy(dx: 1.5, dy: 1.5)) // lower-right highlight
    }

    private func drawTriangle(_ r: NSRect, up: Bool) {
        let m = r.insetBy(dx: 4, dy: 4)
        let p = NSBezierPath()
        if up {   // apex at the visual top (minY in a flipped view)
            p.move(to: NSPoint(x: m.midX, y: m.minY)); p.line(to: NSPoint(x: m.maxX, y: m.maxY)); p.line(to: NSPoint(x: m.minX, y: m.maxY))
        } else {
            p.move(to: NSPoint(x: m.minX, y: m.minY)); p.line(to: NSPoint(x: m.maxX, y: m.minY)); p.line(to: NSPoint(x: m.midX, y: m.maxY))
        }
        p.close(); NeXTChrome.black.setFill(); p.fill()
    }

    // MARK: interaction
    private enum Part { case up, down, none }
    private var pressed: Part = .none

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let R = regions()
        if R.up.contains(p)   { pressArrow(up: true); return }
        if R.down.contains(p) { pressArrow(up: false); return }
        if R.knob.contains(p) { dragKnob(from: p); return }
        if R.trough.contains(p) { page(up: p.y < R.knob.minY); return }
    }

    private func pressArrow(up: Bool) {
        pressed = up ? .up : .down; needsDisplay = true
        scrollBy(up ? -lineStep : lineStep)
        NSEvent.startPeriodicEvents(afterDelay: 0.35, withPeriod: 0.05)
        loop: while let e = window?.nextEvent(matching: [.leftMouseUp, .periodic]) {
            switch e.type {
            case .periodic: scrollBy(up ? -lineStep : lineStep)
            case .leftMouseUp: break loop
            default: break
            }
        }
        NSEvent.stopPeriodicEvents()
        pressed = .none; needsDisplay = true
    }

    private func page(up: Bool) {
        let vis = metrics().visible
        scrollBy(up ? -vis * 0.9 : vis * 0.9)
    }

    private func dragKnob(from start: NSPoint) {
        let R = regions()
        let travel = R.trough.height - R.knob.height
        guard travel > 0 else { return }
        let m = metrics()
        let startFrac = m.maxOff > 0 ? m.offset / m.maxOff : 0
        loop: while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break loop }
            let p = convert(e.locationInWindow, from: nil)
            let frac = min(1, max(0, startFrac + (p.y - start.y) / travel))
            setOffset(frac * metrics().maxOff)
        }
    }

    private func scrollBy(_ dy: CGFloat) { setOffset(metrics().offset + dy) }
    private func setOffset(_ y: CGFloat) {
        guard let clip = scrollView?.contentView else { return }
        let clamped = min(metrics().maxOff, max(0, y))
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: clamped))
        scrollView?.reflectScrolledClipView(clip)
        needsDisplay = true
    }
}

// MARK: - Reusable NeXT window frame (chrome around arbitrary content)

/// A borderless-panel content view that paints the NeXT window chrome (title bar + buttons +
/// chiseled frame) and hosts a single embedded content view below the title bar.
final class NextWindowFrameView: NSView {
    private let title: String
    private let onClose: () -> Void
    private let titleH: CGFloat = 22
    private let border: CGFloat = 2
    private var closeRect: NSRect = .zero
    private var hosted: NSView?

    init(title: String, onClose: @escaping () -> Void) {
        self.title = title; self.onClose = onClose
        super.init(frame: NSRect(x: 0, y: 0, width: 452, height: 460))
        wantsLayer = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func contentRect() -> NSRect {
        NSRect(x: border, y: border + titleH, width: bounds.width - border * 2,
               height: bounds.height - border * 2 - titleH)
    }
    func embed(_ v: NSView) { hosted?.removeFromSuperview(); v.frame = contentRect(); v.autoresizingMask = [.width, .height]; addSubview(v); hosted = v }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); hosted?.frame = contentRect() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NeXTChrome.face.setFill(); ctx.fill(bounds)
        NeXTChrome.bevel(bounds, raised: true, width: 2, flipped: true, in: ctx)
        let bar = NSRect(x: border, y: border, width: bounds.width - border * 2, height: titleH)
        NeXTChrome.titleBar(bar, title: title, state: .key, in: ctx)
        let s: CGFloat = 16
        let by = bar.midY - s / 2
        NeXTChrome.button(NSRect(x: bar.minX + 3, y: by, width: s, height: s), kind: .miniaturize, flipped: true, in: ctx)
        closeRect = NSRect(x: bar.maxX - 3 - s, y: by, width: s, height: s)
        NeXTChrome.button(closeRect, kind: .close, flipped: true, in: ctx)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.insetBy(dx: -2, dy: -2).contains(p) { onClose(); return }
        if p.y <= border + titleH { window?.performDrag(with: event) }   // drag by the title bar
    }
}

// MARK: - Icon picker (bundled NeXT "Fleet" set + a custom-file fallback)

/// The "Change Icon…" chooser used by both docks and the running-app tiles. Instead of jumping
/// straight to an open panel, it shows the bundled NeXT icon set (`icons/fleet/`) in a scrollable
/// grid so a tile can be re-skinned with one click; an "Eigene…" button still opens the file
/// picker for a custom image. Wrapped in the standard NeXT window chrome.
final class NextIconPickerController {

    static let shared = NextIconPickerController()
    private var window: NSPanel?
    private init() {}

    /// `done(path, fillWhole)` — `fillWhole` is the state of the "Ganze Fläche füllen" checkbox:
    /// true → the pick fills the whole dock tile edge-to-edge (for the full-tile Fleet art), false
    /// → it sits inset on the silver dock tile (for a motif or custom photo).
    func present(done: @escaping (String, Bool) -> Void) {
        close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 428, height: 460),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .modalPanel
        let root = NextWindowFrameView(title: "Choose Icon", onClose: { [weak self] in self?.close() })
        let picker = NextIconPickerView(icons: Self.bundledIcons(), frame: root.contentRect(),
                                        done: { [weak self] path, fill in self?.close(); done(path, fill) },
                                        onCustom: { [weak self] fill in self?.pickCustom(fill, done) })
        root.embed(picker)
        panel.contentView = root
        if let f = NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x: f.midX - 214, y: f.midY - 230)) }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }

    private func pickCustom(_ fill: Bool, _ done: @escaping (String, Bool) -> Void) {
        close()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns, .image]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { done(url.path, fill) }
    }

    func close() { window?.orderOut(nil); window = nil }

    /// The bundled NeXT icon set shipped in the active theme (`icons/fleet/*.png`), sorted.
    static func bundledIcons() -> [String] {
        guard let dir = ThemeManager.shared.activeTheme?.iconsDirectory.appendingPathComponent("fleet") else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "png" }.map { $0.path }.sorted()
    }
}

/// Picker body: the bundled-icon grid (scrolled by the authentic left `NextScroller`) plus a
/// bottom bar with a "Ganze Fläche füllen" checkbox and an "Eigene…" button (file picker).
final class NextIconPickerView: NSView {
    private let scroll = NSScrollView()
    private let grid = NextFileGridView(frame: .zero)
    private let scroller = NextScroller()
    private let scrollerW: CGFloat = 18
    private let barH: CGFloat = 40
    private let paneInset: CGFloat = 2
    private var customRect: NSRect = .zero
    private var checkRect: NSRect = .zero
    private var fillWhole = true      // Fleet art is full tiles → fill the cell by default
    private let done: (String, Bool) -> Void
    private let onCustom: (Bool) -> Void

    init(icons: [String], frame: NSRect, done: @escaping (String, Bool) -> Void, onCustom: @escaping (Bool) -> Void) {
        self.done = done; self.onCustom = onCustom
        super.init(frame: frame)
        wantsLayer = true
        scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true; scroll.backgroundColor = NeXTChrome.face; scroll.borderType = .noBorder
        scroll.documentView = grid
        scroll.contentView.postsBoundsChangedNotifications = true
        addSubview(scroll)
        scroller.attach(to: scroll); addSubview(scroller)
        let items = icons.map { path in
            NextFileItem(name: "", icon: NSImage(contentsOfFile: path) ?? NSImage(),
                         action: { [weak self] in self?.done(path, self?.fillWhole ?? true) })
        }
        grid.setItems(items, emptyDash: false)
        layoutBits()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); layoutBits() }

    private func contentPane() -> NSRect { NSRect(x: 2, y: 2, width: bounds.width - 4, height: bounds.height - 4 - barH) }
    private func layoutBits() {
        let pane = contentPane().insetBy(dx: paneInset, dy: paneInset)
        scroller.frame = NSRect(x: pane.minX, y: pane.minY, width: scrollerW, height: pane.height)
        scroll.frame = NSRect(x: pane.minX + scrollerW, y: pane.minY, width: pane.width - scrollerW, height: pane.height)
        grid.relayout(width: scroll.contentSize.width)
        scroller.refresh()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NeXTChrome.face.setFill(); ctx.fill(bounds)
        NeXTChrome.bevel(contentPane(), raised: false, flipped: true, in: ctx)
        let by = bounds.height - barH + 8
        // "Ganze Fläche füllen" checkbox (left).
        checkRect = NSRect(x: 12, y: by, width: 16, height: 16)
        NeXTChrome.tile(checkRect, raised: !fillWhole, flipped: true, in: ctx)
        if fillWhole {
            let m = checkRect.insetBy(dx: 4, dy: 4); let p = NSBezierPath(); p.lineWidth = 2
            NeXTChrome.black.setStroke()
            p.move(to: NSPoint(x: m.minX, y: m.midY)); p.line(to: NSPoint(x: m.midX - 1, y: m.maxY)); p.line(to: NSPoint(x: m.maxX, y: m.minY)); p.stroke()
        }
        label("Ganze Fläche füllen", in: NSRect(x: 34, y: by, width: 180, height: 16), align: .left)
        // "Eigene…" button (right).
        customRect = NSRect(x: bounds.width - 122, y: by, width: 110, height: barH - 16)
        NeXTChrome.tile(customRect, raised: true, flipped: true, in: ctx)
        label("Eigene\u{2026}", in: customRect, align: .center)
    }
    private func label(_ s: String, in r: NSRect, align: NSTextAlignment) {
        let p = NSMutableParagraphStyle(); p.alignment = align
        let a: [NSAttributedString.Key: Any] = [.font: NeXTChrome.labelFont(12), .foregroundColor: NSColor.black, .paragraphStyle: p]
        let sz = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(in: NSRect(x: r.minX, y: r.midY - sz.height / 2, width: r.width, height: sz.height), withAttributes: a)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if checkRect.insetBy(dx: -4, dy: -4).contains(p) || (p.y >= checkRect.minY - 4 && p.y <= checkRect.maxY + 4 && p.x < 220) {
            fillWhole.toggle(); needsDisplay = true; return
        }
        if customRect.contains(p) { onCustom(fillWhole) }
    }
}
