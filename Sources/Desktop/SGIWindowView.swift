import AppKit

/// An SGI 4Dwm-style window (used for the Icon Catalog): title bar with window-menu,
/// minimize, maximize and close buttons; draggable, edge-resizable, scrollable icon grid.
final class SGIWindowView: NSView {
    let group: DockThemeConfig.ProgramGroup
    private let theme: ThemeBundle

    var onClose: (() -> Void)?
    var onMinimizeRequested: (() -> Void)?

    private let titleH: CGFloat = 22
    private let border: CGFloat = 3
    private let btnW: CGFloat = 18
    private let clientContainer = FlippedClip(frame: .zero)
    private var items: [ProgramItemView] = []
    private var scrollY: CGFloat = 0
    private var contentH: CGFloat = 0

    private var dragOff: NSPoint?
    private var resizeEdges: (l: Bool, r: Bool, t: Bool, b: Bool)?
    private var resizeStart: NSRect = .zero
    private var savedFrame: NSRect = .zero
    private var isMax = false
    private let minSize = NSSize(width: 220, height: 150)
    private let resizeMargin: CGFloat = 6

    init(group: DockThemeConfig.ProgramGroup, theme: ThemeBundle, frame: NSRect) {
        self.group = group; self.theme = theme
        super.init(frame: frame)
        clientContainer.clipsToBounds = true
        addSubview(clientContainer)
        for e in group.items {
            let iv = ProgramItemView(entry: e, image: loadIcon(e))
            clientContainer.addSubview(iv); items.append(iv)
        }
        relayout()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }

    private func loadIcon(_ e: DockThemeConfig.DesktopIconEntry) -> NSImage? {
        let url = theme.iconsDirectory.appendingPathComponent(e.icon)
        if let img = NSImage(contentsOf: url) { return img }
        if e.type == "app", let bid = e.bundleID { return ThemeManager.shared.icon(for: bid, size: 48) }
        return nil
    }

    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); relayout() }

    private func relayout() {
        let clientH = max(0, bounds.height - titleH - border * 2)
        let clientW = max(0, bounds.width - border * 2)
        clientContainer.frame = NSRect(x: border, y: border, width: clientW, height: clientH)
        let cw = ProgramItemView.cellWidth, ch = ProgramItemView.cellHeight
        let padX: CGFloat = 8, padY: CGFloat = 8
        let cols = max(1, Int((clientW - padX) / cw))
        let rows = Int(ceil(Double(max(1, items.count)) / Double(cols)))
        contentH = CGFloat(rows) * ch + padY * 2
        scrollY = min(max(0, scrollY), max(0, contentH - clientH))
        for (i, it) in items.enumerated() {
            let c = i % cols, r = i / cols
            it.frame = NSRect(x: padX + CGFloat(c) * cw, y: padY + CGFloat(r) * ch - scrollY, width: cw, height: ch)
        }
    }

    override func scrollWheel(with e: NSEvent) {
        let clientH = clientContainer.bounds.height
        scrollY = min(max(0, scrollY - e.scrollingDeltaY), max(0, contentH - clientH))
        relayout(); needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.93, alpha: 1).setFill(); bounds.fill()   // light client
        SGIChrome.face.setFill()
        // border bands
        NSRect(x: 0, y: bounds.maxY - titleH - border * 2, width: bounds.width, height: titleH + border * 2).fill()
        SGIChrome.drawRaised(bounds, t: 2)
        let tb = titleRect
        SGIChrome.activeTitle.setFill(); tb.fill()
        SGIChrome.drawRaised(menuBtnRect, t: 2)
        SGIChrome.drawText(group.name, in: tb.insetBy(dx: 26, dy: 0), size: 12, color: SGIChrome.titleText, centered: true)
        drawBtn(minBtnRect, "_")
        drawBtn(maxBtnRect, isMax ? "❐" : "□")
        drawBtn(closeBtnRect, "✕")
    }

    private func drawBtn(_ r: NSRect, _ glyph: String) {
        SGIChrome.face.setFill(); r.fill(); SGIChrome.drawRaised(r, t: 2)
        SGIChrome.drawText(glyph, in: r, size: 11, color: .black, centered: true)
    }

    private var titleRect: NSRect { NSRect(x: border, y: bounds.maxY - border - titleH, width: bounds.width - border * 2, height: titleH) }
    private var menuBtnRect: NSRect { NSRect(x: titleRect.minX + 2, y: titleRect.minY + 2, width: btnW, height: titleH - 4) }
    private var closeBtnRect: NSRect { NSRect(x: titleRect.maxX - btnW - 2, y: titleRect.minY + 2, width: btnW, height: titleH - 4) }
    private var maxBtnRect: NSRect { NSRect(x: closeBtnRect.minX - btnW - 2, y: titleRect.minY + 2, width: btnW, height: titleH - 4) }
    private var minBtnRect: NSRect { NSRect(x: maxBtnRect.minX - btnW - 2, y: titleRect.minY + 2, width: btnW, height: titleH - 4) }

    // MARK: Mouse

    private func edges(at p: NSPoint) -> (l: Bool, r: Bool, t: Bool, b: Bool) {
        (p.x <= resizeMargin, p.x >= bounds.width - resizeMargin,
         p.y >= bounds.height - resizeMargin, p.y <= resizeMargin)
    }

    override func mouseDown(with event: NSEvent) {
        superview?.addSubview(self)   // bring to front
        let p = convert(event.locationInWindow, from: nil)
        if closeBtnRect.contains(p) { onClose?(); return }
        if minBtnRect.contains(p) { onMinimizeRequested?(); return }
        if maxBtnRect.contains(p) { toggleMax(); return }
        if menuBtnRect.contains(p) {
            guard let host = window?.contentView else { return }
            let tl = convert(NSPoint(x: menuBtnRect.minX, y: menuBtnRect.minY), to: host)
            Win31Menu.present(items: [
                Win31MenuItem("Maximize", enabled: !isMax) { [weak self] in self?.toggleMax() },
                Win31MenuItem("Minimize") { [weak self] in self?.onMinimizeRequested?() },
                .separator,
                Win31MenuItem("Close") { [weak self] in self?.onClose?() },
            ], topLeft: tl, in: host)
            return
        }
        if !isMax {
            let e = edges(at: p)
            if e.l || e.r || e.t || e.b { resizeEdges = e; resizeStart = frame; return }
        }
        if titleRect.contains(p) {
            if event.clickCount >= 2 { toggleMax(); return }
            if !isMax, let parent = superview {
                let pp = parent.convert(event.locationInWindow, from: nil)
                dragOff = NSPoint(x: pp.x - frame.minX, y: pp.y - frame.minY)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let parent = superview else { return }
        let p = parent.convert(event.locationInWindow, from: nil)
        if let e = resizeEdges {
            let s = resizeStart; var f = s
            if e.r { f.size.width = max(minSize.width, p.x - s.minX) }
            if e.t { f.size.height = max(minSize.height, p.y - s.minY) }
            if e.l { let nx = min(p.x, s.maxX - minSize.width); f.origin.x = nx; f.size.width = s.maxX - nx }
            if e.b { let ny = min(p.y, s.maxY - minSize.height); f.origin.y = ny; f.size.height = s.maxY - ny }
            frame = f; needsDisplay = true; return
        }
        guard let off = dragOff else { return }
        setFrameOrigin(NSPoint(x: p.x - off.x, y: p.y - off.y))
    }

    override func mouseUp(with event: NSEvent) { dragOff = nil; resizeEdges = nil }

    private func toggleMax() {
        guard let parent = superview else { return }
        if isMax { isMax = false; if savedFrame != .zero { frame = savedFrame } }
        else { savedFrame = frame; isMax = true; frame = parent.bounds }
        relayout(); needsDisplay = true
    }
}
