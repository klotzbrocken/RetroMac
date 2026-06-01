import AppKit

/// The outer Windows 3.1 Program Manager frame: beveled border, title bar, a menu bar
/// (File/Options/Window/Help with working popups), and a gray workspace hosting the
/// group windows. Draggable by its title bar.
final class ProgramManagerView: NSView {

    private let config: DockThemeConfig.ProgramManagerConfig
    private let themeBundle: ThemeBundle?

    private let titleBarHeight: CGFloat = 22
    private let menuBarHeight: CGFloat = 20
    private let borderWidth: CGFloat = 4
    private let captionButtonW: CGFloat = 20

    private let workspace = WorkspaceView(frame: .zero)
    private var groups: [ProgramGroupView] = []
    private weak var activeGroup: ProgramGroupView?

    // Minimized group slot scales with the icon-size slider.
    private var minIconW: CGFloat { max(90, ProgramItemView.iconSize + 28) }
    private var minIconH: CGFloat { ProgramItemView.iconSize + 22 }

    private var dragOffset: NSPoint?
    private var didPosition = false

    // PM self-minimize state (#6)
    private var isMinimized = false
    private var savedPMFrame: NSRect = .zero
    private let pmIcon: NSImage?
    private let animator = ZoomRectAnimator()

    // Menu label hit rects (self coords), filled during draw
    private var menuRects: [(String, NSRect)] = []

    init(config: DockThemeConfig.ProgramManagerConfig, themeBundle: ThemeBundle?, frame: NSRect) {
        self.config = config
        self.themeBundle = themeBundle
        self.pmIcon = themeBundle.flatMap {
            NSImage(contentsOf: $0.iconsDirectory.appendingPathComponent("progman.png"))
        }
        super.init(frame: frame)
        addSubview(workspace)
        for g in config.groups {
            let gv = ProgramGroupView(group: g, themeBundle: themeBundle)
            gv.onActivate = { [weak self] grp in self?.activate(grp) }
            gv.onStateChange = { [weak self] _ in self?.layoutMinimizedIcons() }
            gv.onMinimizeRequested = { [weak self] grp in self?.minimizeGroup(grp) }
            gv.onRestoreRequested = { [weak self] grp in self?.restoreGroup(grp) }
            gv.onActivateNext = { [weak self] grp in self?.activateNext(after: grp) }
            workspace.addSubview(gv)
            groups.append(gv)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutWorkspace()
    }

    /// Called by the controller once the view is in the hierarchy at its final size.
    func performInitialLayout() {
        layoutWorkspace()
    }

    private func layoutWorkspace() {
        workspace.frame = NSRect(x: borderWidth, y: borderWidth,
                                 width: bounds.width - borderWidth * 2,
                                 height: bounds.height - titleBarHeight - menuBarHeight - borderWidth * 2)
        positionGroupsIfNeeded()
    }

    private func positionGroupsIfNeeded() {
        guard !didPosition, workspace.bounds.width > 0 else { return }
        didPosition = true
        var fallback: CGFloat = 12
        for (i, gv) in groups.enumerated() {
            let g = gv.group
            let w = CGFloat(g.width ?? 280), h = CGFloat(g.height ?? 180)
            let x = CGFloat(g.x ?? Int(fallback))
            let y = CGFloat(g.y ?? Int(12 + CGFloat(i) * 26))
            if g.x == nil { fallback += 28 }
            gv.frame = NSRect(x: x, y: y, width: w, height: h)   // flipped workspace → top-left origin
            gv.relayout()
            if g.minimized == true { gv.minimize() }
        }
        if let first = groups.first(where: { !$0.isMinimized }) ?? groups.first { activate(first) }
        layoutMinimizedIcons()
    }

    private func layoutMinimizedIcons() {
        var x: CGFloat = 8
        let y = workspace.bounds.height - minIconH - 6   // flipped → bottom
        for gv in groups where gv.isMinimized {
            gv.frame = NSRect(x: x, y: y, width: minIconW, height: minIconH)
            x += minIconW + 8
        }
    }

    private func activate(_ grp: ProgramGroupView) {
        // Clear minimized-icon selection on all other groups
        for other in groups where other !== grp { other.setMinimizedSelected(false) }
        if activeGroup !== grp {
            activeGroup?.setActive(false)
            activeGroup = grp
            grp.setActive(true)
        }
        workspace.addSubview(grp)   // bring to front
    }

    private func activateNext(after grp: ProgramGroupView) {
        guard let idx = groups.firstIndex(where: { $0 === grp }), groups.count > 1 else { return }
        let next = groups[(idx + 1) % groups.count]
        if next.isMinimized { restoreGroup(next) } else { activate(next) }
    }

    private func nextMinimizedSlot() -> NSRect {
        let count = groups.filter { $0.isMinimized }.count
        let x = 8 + CGFloat(count) * (minIconW + 8)
        let y = workspace.bounds.height - minIconH - 6
        return NSRect(x: x, y: y, width: minIconW, height: minIconH)
    }

    private func minimizeGroup(_ grp: ProgramGroupView) {
        guard !grp.isMinimized else { return }
        let target = nextMinimizedSlot()
        animator.animate(in: workspace, from: grp.frame, to: target) { [weak self] in
            grp.minimize()
            self?.layoutMinimizedIcons()
        }
    }

    private func restoreGroup(_ grp: ProgramGroupView) {
        guard grp.isMinimized else { return }
        let target = grp.savedFrame != .zero ? grp.savedFrame : grp.frame
        animator.animate(in: workspace, from: grp.frame, to: target, speedMultiplier: 1.25) { [weak self] in
            grp.restore()
            self?.activate(grp)
            self?.layoutMinimizedIcons()
        }
    }

    // MARK: - PM self-minimize (#6)

    private var pmIconSlot: NSRect {
        let w = max(100, ProgramItemView.iconSize + 36)
        let h = ProgramItemView.iconSize + 28
        return NSRect(x: 24, y: 24, width: w, height: h)   // bottom-left of the desktop overlay
    }

    private func minimizePM() {
        guard !isMinimized, let parent = superview else { return }
        savedPMFrame = frame
        animator.animate(in: parent, from: frame, to: pmIconSlot) { [weak self] in
            guard let self = self else { return }
            self.isMinimized = true
            self.workspace.isHidden = true
            self.frame = self.pmIconSlot
            self.needsDisplay = true
        }
    }

    private func restorePM() {
        guard isMinimized, let parent = superview else { return }
        let target = savedPMFrame != .zero ? savedPMFrame : frame
        animator.animate(in: parent, from: frame, to: target, speedMultiplier: 1.25) { [weak self] in
            guard let self = self else { return }
            self.isMinimized = false
            self.frame = target
            self.workspace.isHidden = false
            self.needsDisplay = true
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isMinimized {
            let iconSize = ProgramItemView.iconSize
            let iconRect = NSRect(x: (bounds.width - iconSize) / 2, y: bounds.height - iconSize - 6,
                                  width: iconSize, height: iconSize)
            if let img = pmIcon {
                NSGraphicsContext.current?.imageInterpolation = .none
                img.draw(in: iconRect, from: .zero, operation: .sourceOver,
                         fraction: 1.0, respectFlipped: true, hints: nil)
            }
            Win31Chrome.drawText(config.title, in: NSRect(x: 0, y: 2, width: bounds.width, height: 14),
                                 size: 11, color: .white, centered: true)
            return
        }

        Win31Chrome.face.setFill()
        bounds.fill()
        Win31Chrome.drawWindowFrame(bounds, border: borderWidth)

        let tb = titleBarRect
        Win31Chrome.drawTitleBar(tb, active: true)
        Win31Chrome.drawSystemBox(systemBoxRect)
        let textRect = NSRect(x: systemBoxRect.maxX + 5, y: tb.minY,
                              width: pmMinimizeRect.minX - systemBoxRect.maxX - 10, height: tb.height)
        Win31Chrome.drawText(config.title, in: textRect, size: 13, color: Win31Chrome.titleText)
        Win31Chrome.drawCaptionButton(pmMinimizeRect, glyph: .minimize)
        Win31Chrome.drawCaptionButton(pmMaximizeRect, glyph: .maximize)

        // Menu bar
        let mb = menuBarRect
        Win31Chrome.face.setFill(); mb.fill()
        Win31Chrome.darkGray.setFill()
        NSRect(x: mb.minX, y: mb.minY, width: mb.width, height: 1).fill()
        Win31Chrome.white.setFill()
        NSRect(x: mb.minX, y: mb.minY + 1, width: mb.width, height: 1).fill()
        menuRects.removeAll()
        var mx = mb.minX + 10
        for label in ["File", "Options", "Window", "Help"] {
            let w: CGFloat = label.count <= 4 ? 42 : 56
            let r = NSRect(x: mx, y: mb.minY, width: w, height: mb.height)
            Win31Chrome.drawText(label, in: r.insetBy(dx: 2, dy: 0), size: 12, color: .black)
            menuRects.append((label, r))
            mx += w
        }
    }

    // MARK: - Hit rects

    private var titleBarRect: NSRect {
        NSRect(x: borderWidth, y: bounds.maxY - borderWidth - titleBarHeight,
               width: bounds.width - borderWidth * 2, height: titleBarHeight)
    }
    private var menuBarRect: NSRect {
        NSRect(x: borderWidth, y: titleBarRect.minY - menuBarHeight,
               width: bounds.width - borderWidth * 2, height: menuBarHeight)
    }
    private var systemBoxRect: NSRect {
        NSRect(x: titleBarRect.minX + 2, y: titleBarRect.minY + 3,
               width: titleBarHeight - 6, height: titleBarHeight - 6)
    }
    private var pmMaximizeRect: NSRect {
        NSRect(x: titleBarRect.maxX - captionButtonW - 2, y: titleBarRect.minY + 3,
               width: captionButtonW, height: titleBarHeight - 6)
    }
    private var pmMinimizeRect: NSRect {
        NSRect(x: pmMaximizeRect.minX - captionButtonW - 1, y: titleBarRect.minY + 3,
               width: captionButtonW, height: titleBarHeight - 6)
    }

    // MARK: - Mouse: menus + title-bar drag

    override func mouseDown(with event: NSEvent) {
        // Minimized PM: double-click restores; single click can drag the icon
        if isMinimized {
            if event.clickCount >= 2 { restorePM() }
            else {
                let pParent = superview?.convert(event.locationInWindow, from: nil) ?? .zero
                dragOffset = NSPoint(x: pParent.x - frame.minX, y: pParent.y - frame.minY)
            }
            return
        }

        let p = convert(event.locationInWindow, from: nil)

        // Resize from border edges/corners (PM is non-flipped in a non-flipped parent)
        let e = pmResizeEdges(at: p)
        if e.any {
            resizeEdges = e
            resizeStartFrame = frame
            return
        }

        // Caption buttons
        if pmMinimizeRect.contains(p) { minimizePM(); return }
        if pmMaximizeRect.contains(p) { return }   // PM maximize: no-op (already large)
        if systemBoxRect.contains(p) {
            if event.clickCount >= 2 { minimizePM() }
            return
        }

        // Menu bar clicks
        for (label, r) in menuRects where r.contains(p) {
            showMenu(label, at: NSPoint(x: r.minX, y: r.minY))
            return
        }

        if titleBarRect.contains(p) {
            let pParent = superview?.convert(event.locationInWindow, from: nil) ?? .zero
            dragOffset = NSPoint(x: pParent.x - frame.minX, y: pParent.y - frame.minY)
        }
    }

    private struct PMEdges { var left = false; var right = false; var top = false; var bottom = false
        var any: Bool { left || right || top || bottom } }
    private var resizeEdges: PMEdges?
    private var resizeStartFrame: NSRect = .zero
    private let pmResizeMargin: CGFloat = 6
    private let minPMSize = NSSize(width: 420, height: 320)

    private func pmResizeEdges(at p: NSPoint) -> PMEdges {
        var e = PMEdges()
        e.left = p.x <= pmResizeMargin
        e.right = p.x >= bounds.width - pmResizeMargin
        e.top = p.y >= bounds.height - pmResizeMargin     // self maxY == visual top
        e.bottom = p.y <= pmResizeMargin
        return e
    }

    override func mouseDragged(with event: NSEvent) {
        guard let parent = superview else { return }
        let p = parent.convert(event.locationInWindow, from: nil)

        if let e = resizeEdges {
            let sf = resizeStartFrame
            var f = sf
            if e.right  { f.size.width  = max(minPMSize.width,  p.x - sf.minX) }
            if e.top    { f.size.height = max(minPMSize.height, p.y - sf.minY) }   // bottom fixed
            if e.left   { let nx = min(p.x, sf.maxX - minPMSize.width);  f.origin.x = nx; f.size.width  = sf.maxX - nx }
            if e.bottom { let ny = min(p.y, sf.maxY - minPMSize.height); f.origin.y = ny; f.size.height = sf.maxY - ny }
            frame = f
            needsDisplay = true
            return
        }

        guard let off = dragOffset else { return }
        var o = NSPoint(x: p.x - off.x, y: p.y - off.y)
        o.x = max(-frame.width + 120, min(o.x, parent.bounds.width - 120))
        o.y = max(-frame.height + 120, min(o.y, parent.bounds.height - 40))
        setFrameOrigin(o)
    }

    override func mouseUp(with event: NSEvent) { dragOffset = nil; resizeEdges = nil }

    // MARK: - Menus

    private func showMenu(_ label: String, at point: NSPoint) {
        guard let host = window?.contentView else { return }
        let tl = convert(point, to: host)
        var items: [Win31MenuItem] = []
        switch label {
        case "File":
            items = [
                Win31MenuItem("&Run…") { [weak self] in self?.menuRun() },
                .separator,
                Win31MenuItem("E&xit Windows…") { [weak self] in self?.menuExit() },
            ]
        case "Options":
            items = [
                Win31MenuItem("&Arrange Icons") { [weak self] in self?.menuArrange() },
                Win31MenuItem("&Cascade") { [weak self] in self?.menuCascade() },
                Win31MenuItem("&Tile") { [weak self] in self?.menuTile() },
            ]
        case "Window":
            items = [
                Win31MenuItem("&Cascade") { [weak self] in self?.menuCascade() },
                Win31MenuItem("&Tile") { [weak self] in self?.menuTile() },
                Win31MenuItem("&Arrange Icons") { [weak self] in self?.menuArrange() },
                .separator,
            ]
            for (i, gv) in groups.enumerated() {
                items.append(Win31MenuItem("\(i + 1) \(gv.group.name)") { [weak self] in
                    if gv.isMinimized { self?.restoreGroup(gv) } else { self?.activate(gv) }
                })
            }
        case "Help":
            items = [
                Win31MenuItem("&Contents") { [weak self] in self?.menuAbout() },
                .separator,
                Win31MenuItem("&About Program Manager…") { [weak self] in self?.menuAbout() },
            ]
        default: break
        }
        Win31Menu.present(items: items, topLeft: tl, in: host)
    }

    private func menuRun() {
        // Authentic "Run…" — open Finder so the user can pick/launch anything
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
    }
    @objc private func menuExit() {
        let a = NSAlert()
        a.messageText = "This will end your Windows session."
        a.informativeText = "Exit Windows?"
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            AppDelegate.shared?.deactivateActiveTheme()
        }
    }
    @objc private func menuArrange() {
        activeGroup?.relayout()
        layoutMinimizedIcons()
    }
    @objc private func menuCascade() {
        var off: CGFloat = 0
        for gv in groups where !gv.isMinimized {
            gv.frame = NSRect(x: 12 + off, y: 12 + off, width: 300, height: 200)
            gv.relayout()
            off += 26
        }
        layoutMinimizedIcons()
    }
    @objc private func menuTile() {
        let visible = groups.filter { !$0.isMinimized }
        guard !visible.isEmpty else { return }
        let cols = Int(ceil(sqrt(Double(visible.count))))
        let rows = Int(ceil(Double(visible.count) / Double(cols)))
        let availH = workspace.bounds.height - (groups.contains { $0.isMinimized } ? minIconH + 12 : 0)
        let w = workspace.bounds.width / CGFloat(cols)
        let h = availH / CGFloat(rows)
        for (i, gv) in visible.enumerated() {
            let c = i % cols, r = i / cols
            gv.frame = NSRect(x: CGFloat(c) * w + 2, y: CGFloat(r) * h + 2, width: w - 4, height: h - 4)
            gv.relayout()
        }
        layoutMinimizedIcons()
    }
    @objc private func menuSelectGroup(_ sender: NSMenuItem) {
        guard let gv = sender.representedObject as? ProgramGroupView else { return }
        if gv.isMinimized { gv.restore() }
        activate(gv)
    }
    @objc private func menuHelp() { menuAbout() }
    @objc private func menuAbout() {
        let a = NSAlert()
        a.messageText = "Program Manager"
        a.informativeText = "RetroMac — Windows 3.1\nMicrosoft Windows-style desktop\n\nA faithful Program Manager recreation."
        a.runModal()
    }
}

/// Flipped workspace view that draws the gray well + sunken bevel and hosts groups.
final class WorkspaceView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Win31Chrome.workspace.setFill()
        bounds.fill()
        Win31Chrome.drawSunkenBevel(bounds, thickness: 1)
    }
}
