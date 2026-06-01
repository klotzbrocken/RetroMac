import AppKit
import UniformTypeIdentifiers

/// A Program Manager group window (MDI child): title bar with system box + min/max
/// buttons, beveled border, and a grid of program items. Draggable, minimizable to
/// an icon, maximizable to fill the workspace. Lives inside a FLIPPED workspace,
/// so its frame origin is top-left.
final class ProgramGroupView: NSView {

    let group: DockThemeConfig.ProgramGroup
    private let themeBundle: ThemeBundle?

    private(set) var isActive = false
    private(set) var isMinimized = false
    private(set) var isMaximized = false
    var savedFrame: NSRect = .zero          // frame before maximize/minimize (top-left coords)

    private let titleBarHeight: CGFloat = 20
    private let borderWidth: CGFloat = 4
    private let captionButtonW: CGFloat = 18

    private let clientContainer = FlippedClip(frame: .zero)
    private var itemViews: [ProgramItemView] = []
    private let groupIcon: NSImage?
    private(set) var minimizedSelected = false

    // Scroll state (Win 3.1 scrollbars appear when items overflow the client area)
    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var contentW: CGFloat = 0
    private var contentH: CGFloat = 0
    private var viewW: CGFloat = 0
    private var viewH: CGFloat = 0
    private var showV = false
    private var showH = false
    private var thumbDrag: (vertical: Bool, grabOffset: CGFloat)?

    var onActivate: ((ProgramGroupView) -> Void)?
    var onStateChange: ((ProgramGroupView) -> Void)?
    var onMinimizeRequested: ((ProgramGroupView) -> Void)?
    var onRestoreRequested: ((ProgramGroupView) -> Void)?

    private var dragOffset: NSPoint?
    private var custom: ProgramManagerStore.GroupCustom
    private var themeName: String { ThemeManager.shared.activeTheme?.config.name ?? "?" }

    init(group: DockThemeConfig.ProgramGroup, themeBundle: ThemeBundle?) {
        self.group = group
        self.themeBundle = themeBundle
        self.custom = ProgramManagerStore.load(theme: ThemeManager.shared.activeTheme?.config.name ?? "?", group: group.name)
        // Minimized groups always use the standard Win 3.1 program-group icon (PROGM004)
        self.groupIcon = Self.loadNamedIcon("groupicon.png", themeBundle: themeBundle)
            ?? Self.loadIcon(group.items.first, themeBundle: themeBundle)
        super.init(frame: .zero)
        clientContainer.clipsToBounds = true
        addSubview(clientContainer)
        rebuildItems()
    }

    /// Effective entries = config items (minus deleted) + user-added shortcuts.
    private func effectiveEntries() -> [DockThemeConfig.DesktopIconEntry] {
        let base = group.items.filter { !custom.deleted.contains($0.name) }
        let added = custom.added.filter { !custom.deleted.contains($0.name) }
        return base + added
    }

    private func rebuildItems() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        for entry in effectiveEntries() {
            var img = Self.loadIcon(entry, themeBundle: themeBundle)
            if let override = custom.iconOverrides[entry.name], let o = NSImage(contentsOf: URL(fileURLWithPath: override)) { img = o }
            let item = ProgramItemView(entry: entry, image: img)
            item.draggable = true
            item.onMoved = { [weak self] v in self?.itemMoved(v) }
            item.onContextMenu = { [weak self] v, e in self?.showItemMenu(v, e) }
            clientContainer.addSubview(item)
            itemViews.append(item)
        }
        relayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }   // own content drawn bottom-left; title bar at top

    private static func loadNamedIcon(_ name: String, themeBundle: ThemeBundle?) -> NSImage? {
        guard let bundle = themeBundle else { return nil }
        return NSImage(contentsOf: bundle.iconsDirectory.appendingPathComponent(name))
    }

    private static func loadIcon(_ entry: DockThemeConfig.DesktopIconEntry?, themeBundle: ThemeBundle?) -> NSImage? {
        guard let entry = entry else { return nil }
        if let bundle = themeBundle {
            let url = bundle.iconsDirectory.appendingPathComponent(entry.icon)
            if let img = NSImage(contentsOf: url) { return img }
        }
        if entry.type == "app", let bid = entry.bundleID {
            return ThemeManager.shared.icon(for: bid, size: 32)
        }
        return nil
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    private var clientFullRect: NSRect {
        NSRect(x: borderWidth, y: borderWidth,
               width: bounds.width - borderWidth * 2,
               height: bounds.height - titleBarHeight - borderWidth * 2)
    }

    func relayout() {
        guard !isMinimized else { clientContainer.isHidden = true; return }
        clientContainer.isHidden = false
        let t = Win31Chrome.scrollbarThickness
        let cellW = ProgramItemView.cellWidth, cellH = ProgramItemView.cellHeight
        let padX: CGFloat = 6, padY: CGFloat = 6
        let full = clientFullRect

        // Fixed "natural" column count from the group's configured width — the icon grid
        // does NOT reflow when the window shrinks, so a HORIZONTAL scrollbar appears once
        // the window is narrower than this fixed content (authentic Win 3.1 behavior).
        let baseW = CGFloat(group.width ?? 280) - borderWidth * 2
        let cols = max(1, Int((baseW - padX) / cellW))
        let rows = Int(ceil(Double(max(1, itemViews.count)) / Double(cols)))
        contentW = CGFloat(cols) * cellW + padX * 2
        contentH = CGFloat(rows) * cellH + padY * 2

        // Decide which scrollbars are needed (each one steals space from the other axis)
        showV = contentH > full.height
        showH = contentW > full.width
        if showV && contentW > full.width - t { showH = true }
        if showH && contentH > full.height - t { showV = true }

        viewW = full.width - (showV ? t : 0)
        viewH = full.height - (showH ? t : 0)
        scrollX = min(max(0, scrollX), max(0, contentW - viewW))
        scrollY = min(max(0, scrollY), max(0, contentH - viewH))

        clientContainer.frame = NSRect(x: borderWidth, y: full.minY + (showH ? t : 0),
                                       width: viewW, height: viewH)
        for (i, item) in itemViews.enumerated() {
            if let pos = custom.positions[item.entry.name] {   // user-dragged free position
                item.frame = NSRect(x: pos[0] - scrollX, y: pos[1] - scrollY, width: cellW, height: cellH)
            } else {
                let col = i % cols, row = i / cols
                item.frame = NSRect(x: padX + CGFloat(col) * cellW - scrollX,
                                    y: padY + CGFloat(row) * cellH - scrollY,
                                    width: cellW, height: cellH)
            }
        }
    }

    // MARK: - Customization (drag, context menu, persistence)

    private func persist() { ProgramManagerStore.save(custom, theme: themeName, group: group.name) }

    private func itemMoved(_ v: ProgramItemView) {
        // Store the position in content coords (add back scroll offset)
        custom.positions[v.entry.name] = [v.frame.minX + scrollX, v.frame.minY + scrollY]
        persist()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let host = window?.contentView else { return }
        let pSelf = convert(event.locationInWindow, from: nil)
        let tl = convert(pSelf, to: host)
        Win31Menu.present(items: [
            Win31MenuItem("&New Shortcut…") { [weak self] in self?.newShortcut() },
            Win31MenuItem("&Arrange Icons") { [weak self] in
                self?.custom.positions.removeAll(); self?.persist(); self?.relayout(); self?.needsDisplay = true
            },
        ], topLeft: tl, in: host)
    }

    private func showItemMenu(_ v: ProgramItemView, _ event: NSEvent) {
        guard let host = window?.contentView else { return }
        let tl = convert(convert(event.locationInWindow, from: nil), to: host)
        Win31Menu.present(items: [
            Win31MenuItem("&Open") { DesktopLauncher.launch(v.entry) },
            Win31MenuItem("Change &Icon…") { [weak self] in self?.changeIcon(v.entry) },
            .separator,
            Win31MenuItem("&Delete") { [weak self] in self?.deleteItem(v.entry) },
        ], topLeft: tl, in: host)
    }

    private func newShortcut() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an application for the new shortcut"
        guard panel.runModal() == .OK, let url = panel.url,
              let bid = Bundle(url: url)?.bundleIdentifier else { return }
        let name = url.deletingPathExtension().lastPathComponent
        var entry = DockThemeConfig.DesktopIconEntry(name: name, icon: "", type: "app")
        entry.bundleID = bid
        custom.added.append(entry)
        custom.deleted.removeAll { $0 == name }
        persist(); rebuildItems(); needsDisplay = true
    }

    private func changeIcon(_ entry: DockThemeConfig.DesktopIconEntry) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns, .image]
        panel.message = "Choose an icon image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        custom.iconOverrides[entry.name] = url.path
        persist(); rebuildItems(); needsDisplay = true
    }

    private func deleteItem(_ entry: DockThemeConfig.DesktopIconEntry) {
        custom.added.removeAll { $0.name == entry.name }
        if group.items.contains(where: { $0.name == entry.name }) { custom.deleted.append(entry.name) }
        custom.positions[entry.name] = nil
        custom.iconOverrides[entry.name] = nil
        persist(); rebuildItems(); needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isMinimized { drawMinimized(); return }

        // White client area + thick raised sizing border with corner marks (Win 3.1).
        NSColor.white.setFill()
        bounds.fill()
        Win31Chrome.drawWindowFrame(bounds, border: borderWidth)

        // Title bar (inside the border)
        let tb = titleBarRect
        Win31Chrome.drawTitleBar(tb, active: isActive)
        Win31Chrome.drawSystemBox(systemBoxRect)
        // Centered title across the full title bar
        Win31Chrome.drawText(group.name, in: tb, size: 12,
                             color: isActive ? Win31Chrome.titleText : Win31Chrome.inactiveTitleText,
                             centered: true)
        Win31Chrome.drawCaptionButton(minimizeButtonRect, glyph: .minimize)
        Win31Chrome.drawCaptionButton(maximizeButtonRect, glyph: isMaximized ? .restore : .maximize)

        drawScrollbars()
    }

    // MARK: - Scrollbars

    private var vScrollFrame: NSRect {
        let t = Win31Chrome.scrollbarThickness, f = clientFullRect
        return NSRect(x: f.maxX - t, y: f.minY + (showH ? t : 0), width: t, height: viewH)
    }
    private var hScrollFrame: NSRect {
        let t = Win31Chrome.scrollbarThickness, f = clientFullRect
        return NSRect(x: f.minX, y: f.minY, width: viewW, height: t)
    }
    private var vThumbFrame: NSRect {
        let t = Win31Chrome.scrollbarThickness, sb = vScrollFrame
        let trackTop = sb.maxY - t, trackBot = sb.minY + t
        let trackH = max(1, trackTop - trackBot)
        let thumbH = max(16, trackH * min(1, viewH / max(1, contentH)))
        let maxScroll = max(1, contentH - viewH)
        let posFrac = scrollY / maxScroll
        let thumbTop = trackTop - posFrac * (trackH - thumbH)
        return NSRect(x: sb.minX, y: thumbTop - thumbH, width: t, height: thumbH)
    }
    private var hThumbFrame: NSRect {
        let t = Win31Chrome.scrollbarThickness, sb = hScrollFrame
        let trackLeft = sb.minX + t, trackRight = sb.maxX - t
        let trackW = max(1, trackRight - trackLeft)
        let thumbW = max(16, trackW * min(1, viewW / max(1, contentW)))
        let maxScroll = max(1, contentW - viewW)
        let posFrac = scrollX / maxScroll
        let thumbLeft = trackLeft + posFrac * (trackW - thumbW)
        return NSRect(x: thumbLeft, y: sb.minY, width: thumbW, height: t)
    }

    private func drawScrollbars() {
        let t = Win31Chrome.scrollbarThickness
        if showV {
            let sb = vScrollFrame
            Win31Chrome.drawScrollTrack(sb)
            Win31Chrome.drawScrollArrow(NSRect(x: sb.minX, y: sb.maxY - t, width: t, height: t), dir: .up)
            Win31Chrome.drawScrollArrow(NSRect(x: sb.minX, y: sb.minY, width: t, height: t), dir: .down)
            Win31Chrome.drawScrollThumb(vThumbFrame)
        }
        if showH {
            let sb = hScrollFrame
            Win31Chrome.drawScrollTrack(sb)
            Win31Chrome.drawScrollArrow(NSRect(x: sb.minX, y: sb.minY, width: t, height: t), dir: .left)
            Win31Chrome.drawScrollArrow(NSRect(x: sb.maxX - t, y: sb.minY, width: t, height: t), dir: .right)
            Win31Chrome.drawScrollThumb(hThumbFrame)
        }
        // Corner square when both visible
        if showV && showH {
            let f = clientFullRect
            Win31Chrome.face.setFill()
            NSRect(x: f.maxX - t, y: f.minY, width: t, height: t).fill()
        }
    }

    private func scrollBy(dx: CGFloat, dy: CGFloat) {
        scrollX = min(max(0, scrollX + dx), max(0, contentW - viewW))
        scrollY = min(max(0, scrollY + dy), max(0, contentH - viewH))
        relayout(); needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isMinimized, (showV || showH) else { return }
        scrollBy(dx: -event.scrollingDeltaX, dy: -event.scrollingDeltaY)
    }

    private func drawMinimized() {
        // No window chrome — just the group icon + label sitting on the workspace.
        // Icon scales with the Settings icon-size slider, like program-item icons.
        let iconSize = ProgramItemView.iconSize
        let iconRect = NSRect(x: (bounds.width - iconSize) / 2, y: bounds.height - iconSize - 4,
                              width: iconSize, height: iconSize)
        if let img = groupIcon {
            NSGraphicsContext.current?.imageInterpolation = .none
            img.draw(in: iconRect, from: .zero, operation: .sourceOver,
                     fraction: 1.0, respectFlipped: true, hints: nil)
        }
        // Label: black on transparent normally; when selected, a navy highlight box
        // behind white text (classic Win 3.1 icon-title selection).
        let labelRect = NSRect(x: 0, y: 2, width: bounds.width, height: 14)
        if minimizedSelected {
            let attr = NSAttributedString(string: group.name, attributes: [
                .font: Win31Chrome.font(size: 11, bold: false)
            ])
            let tw = min(attr.size().width + 6, bounds.width)
            Win31Chrome.activeTitle.setFill()
            NSRect(x: (bounds.width - tw) / 2, y: labelRect.minY, width: tw, height: labelRect.height).integral.fill()
        }
        Win31Chrome.drawText(group.name, in: labelRect, size: 11,
                             color: minimizedSelected ? .white : .black, centered: true)
    }

    func setMinimizedSelected(_ s: Bool) {
        guard minimizedSelected != s else { return }
        minimizedSelected = s
        needsDisplay = true
    }

    // MARK: - Hit rects (self coords, non-flipped → title bar at top)

    private var titleBarRect: NSRect {
        NSRect(x: borderWidth, y: bounds.maxY - borderWidth - titleBarHeight,
               width: bounds.width - borderWidth * 2, height: titleBarHeight)
    }
    private var systemBoxRect: NSRect {
        NSRect(x: titleBarRect.minX + 1, y: titleBarRect.minY + 2,
               width: titleBarHeight - 4, height: titleBarHeight - 4)
    }
    private var maximizeButtonRect: NSRect {
        NSRect(x: titleBarRect.maxX - captionButtonW - 1, y: titleBarRect.minY + 2,
               width: captionButtonW, height: titleBarHeight - 4)
    }
    private var minimizeButtonRect: NSRect {
        NSRect(x: maximizeButtonRect.minX - captionButtonW - 1, y: titleBarRect.minY + 2,
               width: captionButtonW, height: titleBarHeight - 4)
    }

    // MARK: - Mouse

    private struct ResizeEdges { var left = false; var right = false; var top = false; var bottom = false
        var any: Bool { left || right || top || bottom } }
    private var resizeEdges: ResizeEdges?
    private var resizeStartFrame: NSRect = .zero
    private let resizeMargin: CGFloat = 6
    private let minGroupSize = NSSize(width: 180, height: 110)

    /// Detect which border edges the point (self coords, non-flipped) is near.
    private func resizeEdges(at p: NSPoint) -> ResizeEdges {
        var e = ResizeEdges()
        e.left   = p.x <= resizeMargin
        e.right  = p.x >= bounds.width - resizeMargin
        e.top    = p.y >= bounds.height - resizeMargin   // self maxY == visual top
        e.bottom = p.y <= resizeMargin
        return e
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?(self)
        let pSelf = convert(event.locationInWindow, from: nil)
        let pParent = superview?.convert(event.locationInWindow, from: nil) ?? .zero

        if isMinimized {
            if event.clickCount >= 2 { onRestoreRequested?(self) }
            else {
                setMinimizedSelected(true)
                dragOffset = NSPoint(x: pParent.x - frame.minX, y: pParent.y - frame.minY)
            }
            return
        }

        // Scrollbars (before resize so the right/bottom edges stay usable)
        if handleScrollbarMouseDown(pSelf) { return }

        // Resize from border edges/corners (before title-bar drag)
        if !isMaximized {
            let e = resizeEdges(at: pSelf)
            if e.any {
                resizeEdges = e
                resizeStartFrame = frame
                return
            }
        }

        if minimizeButtonRect.contains(pSelf) { onMinimizeRequested?(self); return }
        if maximizeButtonRect.contains(pSelf) { toggleMaximize(); return }
        if systemBoxRect.contains(pSelf) {
            // Single click opens the Win 3.1 system menu (Restore/Move/Size/…)
            showSystemMenu(at: NSPoint(x: systemBoxRect.minX, y: systemBoxRect.minY))
            return
        }
        if titleBarRect.contains(pSelf) {
            if event.clickCount >= 2 { toggleMaximize(); return }
            if !isMaximized { dragOffset = NSPoint(x: pParent.x - frame.minX, y: pParent.y - frame.minY) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let parent = superview else { return }
        let p = parent.convert(event.locationInWindow, from: nil)

        // Scrollbar thumb drag
        if let td = thumbDrag {
            let pSelf = convert(event.locationInWindow, from: nil)
            let t = Win31Chrome.scrollbarThickness
            if td.vertical {
                let sb = vScrollFrame
                let trackTop = sb.maxY - t, trackBot = sb.minY + t
                let thumbH = vThumbFrame.height
                let usable = max(1, (trackTop - trackBot) - thumbH)
                // pSelf.y is the desired thumb-top minus grab offset
                let thumbTop = min(trackTop, max(trackBot + thumbH, pSelf.y + td.grabOffset))
                let posFrac = (trackTop - thumbTop) / usable
                scrollY = posFrac * max(0, contentH - viewH)
                relayout(); needsDisplay = true
            } else {
                let sb = hScrollFrame
                let trackLeft = sb.minX + t, trackRight = sb.maxX - t
                let thumbW = hThumbFrame.width
                let usable = max(1, (trackRight - trackLeft) - thumbW)
                let thumbLeft = min(trackRight - thumbW, max(trackLeft, pSelf.x - td.grabOffset))
                let posFrac = (thumbLeft - trackLeft) / usable
                scrollX = posFrac * max(0, contentW - viewW)
                relayout(); needsDisplay = true
            }
            return
        }

        if let e = resizeEdges {
            let sf = resizeStartFrame
            var f = sf
            if e.right  { f.size.width  = max(minGroupSize.width,  p.x - sf.minX) }
            if e.bottom { f.size.height = max(minGroupSize.height, p.y - sf.minY) }
            if e.left   { let nx = min(p.x, sf.maxX - minGroupSize.width);  f.origin.x = nx; f.size.width  = sf.maxX - nx }
            if e.top    { let ny = min(p.y, sf.maxY - minGroupSize.height); f.origin.y = ny; f.size.height = sf.maxY - ny }
            // Clamp within workspace
            f.origin.x = max(0, f.origin.x); f.origin.y = max(0, f.origin.y)
            frame = f
            relayout()
            needsDisplay = true
            return
        }

        guard let off = dragOffset else { return }
        var o = NSPoint(x: p.x - off.x, y: p.y - off.y)
        o.x = max(0, min(o.x, parent.bounds.width - frame.width))
        o.y = max(0, min(o.y, parent.bounds.height - frame.height))
        setFrameOrigin(o)
    }

    override func mouseUp(with event: NSEvent) { dragOffset = nil; resizeEdges = nil; thumbDrag = nil }

    // MARK: - Scrollbar / system-menu interaction

    /// Returns true if the click was consumed by a scrollbar.
    private func handleScrollbarMouseDown(_ p: NSPoint) -> Bool {
        let t = Win31Chrome.scrollbarThickness
        if showV && vScrollFrame.contains(p) {
            let sb = vScrollFrame
            if p.y >= sb.maxY - t { scrollBy(dx: 0, dy: -ProgramItemView.cellHeight) }      // up arrow
            else if p.y <= sb.minY + t { scrollBy(dx: 0, dy: ProgramItemView.cellHeight) }   // down arrow
            else if vThumbFrame.contains(p) { thumbDrag = (true, vThumbFrame.maxY - p.y) }    // grab thumb
            else { scrollBy(dx: 0, dy: p.y > vThumbFrame.maxY ? -viewH : viewH) }             // page
            return true
        }
        if showH && hScrollFrame.contains(p) {
            let sb = hScrollFrame
            if p.x <= sb.minX + t { scrollBy(dx: -ProgramItemView.cellWidth, dy: 0) }         // left arrow
            else if p.x >= sb.maxX - t { scrollBy(dx: ProgramItemView.cellWidth, dy: 0) }     // right arrow
            else if hThumbFrame.contains(p) { thumbDrag = (false, p.x - hThumbFrame.minX) }   // grab thumb
            else { scrollBy(dx: p.x < hThumbFrame.minX ? -viewW : viewW, dy: 0) }             // page
            return true
        }
        return false
    }

    /// Win 3.1 control-menu: Restore / Move / Size / Minimize / Maximize / Close / Next.
    /// `boxBottomLeft` is the system box's bottom-left in self coords (menu drops from there).
    private func showSystemMenu(at boxBottomLeft: NSPoint) {
        guard let host = window?.contentView else { return }
        let tl = convert(boxBottomLeft, to: host)
        let items: [Win31MenuItem] = [
            Win31MenuItem("&Restore", enabled: isMaximized || isMinimized) { [weak self] in self?.sysRestore() },
            Win31MenuItem("&Move"),
            Win31MenuItem("&Size", enabled: !isMaximized),
            Win31MenuItem("Mi&nimize", enabled: !isMinimized) { [weak self] in self?.sysMinimize() },
            Win31MenuItem("Ma&ximize", enabled: !isMaximized) { [weak self] in self?.sysMaximize() },
            .separator,
            Win31MenuItem("&Close", accelerator: "Ctrl+F4") { [weak self] in self?.sysMinimize() },
            Win31MenuItem("&Next", accelerator: "Ctrl+F6") { [weak self] in self?.sysNext() },
        ]
        Win31Menu.present(items: items, topLeft: tl, in: host)
    }

    private func sysRestore() { if isMaximized || isMinimized { restore() } }
    private func sysMinimize() { if !isMinimized { onMinimizeRequested?(self) } }
    private func sysMaximize() { if !isMaximized { toggleMaximize() } }
    private func sysNext() { onActivateNext?(self) }

    var onActivateNext: ((ProgramGroupView) -> Void)?

    // MARK: - State

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        needsDisplay = true
    }

    func minimize() {
        guard !isMinimized else { return }
        if !isMaximized { savedFrame = frame }
        isMinimized = true
        isMaximized = false
        clientContainer.isHidden = true
        onStateChange?(self)
        needsDisplay = true
    }

    func restore() {
        guard isMinimized || isMaximized else { return }
        isMinimized = false
        isMaximized = false
        if savedFrame != .zero { frame = savedFrame }
        relayout()
        needsDisplay = true
        onStateChange?(self)
    }

    func toggleMaximize() {
        guard let parent = superview else { return }
        if isMaximized {
            isMaximized = false
            if savedFrame != .zero { frame = savedFrame }
        } else {
            if !isMinimized { savedFrame = frame }
            isMaximized = true
            isMinimized = false
            frame = parent.bounds
        }
        relayout()
        needsDisplay = true
        onStateChange?(self)
    }
}

/// A flipped, clipping container so program items lay out top-to-bottom.
final class FlippedClip: NSView {
    override var isFlipped: Bool { true }
}
