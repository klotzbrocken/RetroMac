import AppKit

// MARK: - Shared helpers

private func clampedAbove(_ anchor: NSRect, size: NSSize, gap: CGFloat) -> NSRect {
    let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main!
    let vf = screen.visibleFrame
    var x = anchor.midX - size.width / 2
    x = min(max(x, vf.minX + 4), vf.maxX - size.width - 4)
    var y = anchor.maxY + gap                       // above the dock icon
    if y + size.height > vf.maxY - 4 {              // not enough room above → place below
        y = anchor.minY - gap - size.height
    }
    y = max(y, vf.minY + 4)
    return NSRect(x: x, y: y, width: size.width, height: size.height)
}

/// Aspect-preserving pixelation: shrink to a small grid (smooth) then nearest-upscale (blocky).
private func pixelate(_ src: NSImage, blocksWide: Int, to display: NSSize) -> NSImage {
    let ar = src.size.height / max(1, src.size.width)
    let bw = max(8, blocksWide)
    let bh = max(8, Int((CGFloat(bw) * ar).rounded()))
    guard let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bw, pixelsHigh: bh,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0) else { return src }
    small.size = NSSize(width: bw, height: bh)
    NSGraphicsContext.saveGraphicsState()
    if let ctx = NSGraphicsContext(bitmapImageRep: small) {
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        src.draw(in: NSRect(x: 0, y: 0, width: bw, height: bh), from: .zero, operation: .copy, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()

    let out = NSImage(size: display)
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    small.draw(in: NSRect(origin: .zero, size: display), from: NSRect(x: 0, y: 0, width: bw, height: bh),
               operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
    out.unlockFocus()
    return out
}

// MARK: - Window preview (hover a running app ~2s)

/// Shows a small pixelated snapshot of a running app's front window above its dock icon.
final class DockPreviewController {
    static let shared = DockPreviewController()
    private var panel: NSPanel?
    private var currentBundleID: String?
    private init() {}

    func show(for bundleID: String, anchorScreenRect: NSRect) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
              let (image, aspect) = snapshot(pid: app.processIdentifier) else { return }

        currentBundleID = bundleID
        // Display size: ~220 wide, height from the window's aspect, capped.
        let w: CGFloat = 220
        let h = min(max(w * aspect, 80), 200)
        let pixels = pixelate(image, blocksWide: 96, to: NSSize(width: w, height: h))

        let framePad: CGFloat = 6
        let titleH: CGFloat = 18
        let panelSize = NSSize(width: w + framePad * 2, height: h + framePad * 2 + titleH)
        let frame = clampedAbove(anchorScreenRect, size: panelSize, gap: 10)

        let p = panel ?? makePanel()
        p.setFrame(frame, display: false)
        let content = DockPreviewView(frame: NSRect(origin: .zero, size: panelSize))
        content.image = pixels
        content.title = app.localizedName ?? bundleID
        content.framePad = framePad; content.titleH = titleH
        p.contentView = content
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        currentBundleID = nil
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: 25)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true     // preview is non-interactive; icon hover controls it
        p.hidesOnDeactivate = false
        return p
    }

    /// Capture the app's frontmost on-screen window as an NSImage + aspect (h/w).
    private func snapshot(pid: pid_t) -> (NSImage, CGFloat)? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
        // Pick the largest layer-0 window belonging to this pid.
        var bestID: CGWindowID?
        var bestArea: CGFloat = 0
        for info in infos {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let b = info[kCGWindowBounds as String] as? [String: Any],
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat,
                  let num = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let area = w * h
            if area > bestArea, w > 40, h > 40 { bestArea = area; bestID = num }
        }
        guard let windowID = bestID,
              let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                               [.boundsIgnoreFraming, .nominalResolution]) else { return nil }
        let size = NSSize(width: cg.width, height: cg.height)
        guard size.width > 1, size.height > 1 else { return nil }
        let img = NSImage(cgImage: cg, size: size)
        return (img, size.height / size.width)
    }
}

private final class DockPreviewView: NSView {
    var image: NSImage?
    var title: String = ""
    var framePad: CGFloat = 6
    var titleH: CGFloat = 18
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Pixel-theme frame: dark border + light face.
        NSColor(calibratedWhite: 0.10, alpha: 0.95).setFill(); bounds.fill()
        let titleRect = NSRect(x: 0, y: 0, width: bounds.width, height: titleH)
        NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1).setFill(); titleRect.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        ]
        let s = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: 6, y: (titleH - s.height) / 2), withAttributes: attrs)
        if let image = image {
            let r = NSRect(x: framePad, y: titleH + framePad,
                           width: bounds.width - framePad * 2, height: bounds.height - titleH - framePad * 2)
            image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

// MARK: - Folder stack (click a folder → fan of recent files)

/// Shows the most-recent files of a folder in a small list popover (macOS-stack style).
final class DockStackController {
    static let shared = DockStackController()
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private init() {}

    func toggle(folderPath: String, anchorScreenRect: NSRect) {
        if panel?.isVisible == true { hide(); return }
        show(folderPath: folderPath, anchorScreenRect: anchorScreenRect)
    }

    func show(folderPath: String, anchorScreenRect: NSRect) {
        let url = URL(fileURLWithPath: folderPath)
        let files = recentFiles(in: url, limit: 16)   // 4×4 grid

        let cfg = ThemeManager.shared.activeTheme?.config
        let iconSize = min(max(cfg?.dock.iconSize ?? 56, 44), 64)
        let cols = 4
        let gap: CGFloat = 10, labelH: CGFloat = 13, headerH: CGFloat = 22, footerH: CGFloat = 24, pad: CGFloat = 10
        let cellW = iconSize + 8, cellH = iconSize + labelH + 6
        let rows = max(1, Int(ceil(Double(max(files.count, 1)) / Double(cols))))
        let width = pad * 2 + CGFloat(cols) * cellW + CGFloat(cols - 1) * gap
        let height = headerH + pad + CGFloat(rows) * cellH + CGFloat(rows - 1) * gap + footerH + pad
        let frame = clampedAbove(anchorScreenRect, size: NSSize(width: width, height: height), gap: 10)

        let p = panel ?? makePanel()
        p.setFrame(frame, display: false)
        let view = DockStackView(frame: NSRect(origin: .zero, size: frame.size))
        view.folderURL = url
        view.files = files
        view.iconSize = iconSize
        view.cols = cols; view.gap = gap; view.labelH = labelH
        view.headerH = headerH; view.footerH = footerH; view.pad = pad
        view.cellW = cellW; view.cellH = cellH
        view.onPick = { [weak self] picked in NSWorkspace.shared.open(picked); self?.hide() }
        view.onOpenFolder = { [weak self] in NSWorkspace.shared.open(url); self?.hide() }
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
        installDismissMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: 25)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        return p
    }

    private func installDismissMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func recentFiles(in dir: URL, limit: Int) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isHiddenKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        return items.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.prefix(limit).map { $0 }
    }
}

private final class DockStackView: NSView, NSDraggingSource {
    var folderURL: URL?
    var files: [URL] = []
    var iconSize: CGFloat = 56
    var cols = 4
    var gap: CGFloat = 10
    var labelH: CGFloat = 13
    var headerH: CGFloat = 22
    var footerH: CGFloat = 24
    var pad: CGFloat = 10
    var cellW: CGFloat = 64
    var cellH: CGFloat = 80
    var onPick: ((URL) -> Void)?
    var onOpenFolder: (() -> Void)?

    private var hovered = -1
    private var trackingArea: NSTrackingArea?
    private var pressIndex = -1
    private var pressPoint = NSPoint.zero
    private var didDrag = false
    private var dropActive = false
    private let pixelize = ThemeManager.shared.activeTheme?.config.isPixelated == true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func cellRect(_ i: Int) -> NSRect {
        let row = i / cols, col = i % cols
        return NSRect(x: pad + CGFloat(col) * (cellW + gap),
                      y: headerH + pad + CGFloat(row) * (cellH + gap),
                      width: cellW, height: cellH)
    }
    private func iconRect(_ i: Int) -> NSRect {
        let c = cellRect(i)
        return NSRect(x: c.midX - iconSize / 2, y: c.minY, width: iconSize, height: iconSize)
    }
    private var footerRect: NSRect { NSRect(x: 0, y: bounds.height - footerH, width: bounds.width, height: footerH) }

    private func fileIcon(_ url: URL, size: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return pixelize ? ThemeManager.shared.pixelatedIfNeeded(icon, size: size) : icon
    }

    override func draw(_ dirtyRect: NSRect) {
        let header = NSRect(x: 0, y: 0, width: bounds.width, height: headerH)
        if RetroFrameTheme.key() == "maiksfav" {
            // Pixel-art macOS window (matches the CPU widget / App Folder in this theme).
            NSColor(calibratedWhite: 0.925, alpha: 1).setFill(); bounds.fill()   // #ECECEC
            NSColor(calibratedWhite: 0.149, alpha: 1).setStroke()                 // #262626 outline
            let b = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)); b.lineWidth = 2; b.stroke()
            NSColor(calibratedWhite: 0.89, alpha: 1).setFill(); header.fill()     // #E3E3E3 toolbar
            NSColor(calibratedWhite: 0.149, alpha: 1).setStroke()
            let sep = NSBezierPath(); sep.move(to: NSPoint(x: 0, y: headerH)); sep.line(to: NSPoint(x: bounds.width, y: headerH)); sep.lineWidth = 2; sep.stroke()
            let dots = [NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1),
                        NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1),
                        NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)]
            var dx: CGFloat = 9
            for c in dots { c.setFill(); NSBezierPath(ovalIn: NSRect(x: dx, y: headerH/2 - 5, width: 10, height: 10)).fill(); dx += 16 }
            let title = folderURL?.lastPathComponent ?? "Folder"
            let ha: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Pixelify Sans", size: 12) ?? .boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor(calibratedWhite: 0.23, alpha: 1)]
            let ts = title.size(withAttributes: ha)
            title.draw(at: NSPoint(x: bounds.width/2 - ts.width/2, y: 4), withAttributes: ha)
        } else {
            NSColor(calibratedWhite: 0.96, alpha: 0.98).setFill(); bounds.fill()
            (dropActive ? NSColor(calibratedRed: 0.2, green: 0.5, blue: 1, alpha: 1)
                        : NSColor(calibratedWhite: 0.30, alpha: 1)).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)); border.lineWidth = dropActive ? 2 : 1; border.stroke()
            NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1).setFill(); header.fill()
            let hAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.0, alpha: 1)]
            (folderURL?.lastPathComponent ?? "Folder").draw(at: NSPoint(x: 8, y: 4), withAttributes: hAttrs)
        }

        if files.isEmpty {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                    .foregroundColor: NSColor.secondaryLabelColor]
            "Drop files here".draw(at: NSPoint(x: pad + 4, y: headerH + 12), withAttributes: a)
        }
        let lAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10),
                                                     .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)]
        for (i, url) in files.enumerated() {
            let c = cellRect(i)
            if i == hovered { NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.95, alpha: 0.18).setFill()
                NSBezierPath(roundedRect: c.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill() }
            fileIcon(url, size: iconSize).draw(in: iconRect(i), from: .zero, operation: .sourceOver,
                                               fraction: 1, respectFlipped: true, hints: nil)
            var label = url.lastPathComponent
            let maxW = cellW - 2
            while label.size(withAttributes: lAttrs).width > maxW && label.count > 1 { label = String(label.dropLast()) }
            if label != url.lastPathComponent { label = String(label.dropLast()) + "…" }
            let ls = label.size(withAttributes: lAttrs)
            label.draw(at: NSPoint(x: c.midX - ls.width / 2, y: c.minY + iconSize + 1), withAttributes: lAttrs)
        }

        let f = footerRect
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill(); f.fill()
        NSColor(calibratedWhite: 0.30, alpha: 1).setStroke()
        let top = NSBezierPath(); top.move(to: NSPoint(x: 0, y: f.minY)); top.line(to: NSPoint(x: f.maxX, y: f.minY)); top.stroke()
        let fAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                     .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1)]
        "Open in Finder".draw(at: NSPoint(x: 8, y: f.midY - 7), withAttributes: fAttrs)
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
        for i in files.indices where cellRect(i).contains(p) { hovered = i }
        if old != hovered { needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { if hovered != -1 { hovered = -1; needsDisplay = true } }

    // Click opens; press-and-drag drags the file OUT to Finder/other apps.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        didDrag = false; pressIndex = -1
        if footerRect.contains(p) { onOpenFolder?(); return }
        for i in files.indices where cellRect(i).contains(p) { pressIndex = i; pressPoint = p; return }
    }
    override func mouseDragged(with event: NSEvent) {
        guard pressIndex >= 0, !didDrag, pressIndex < files.count else { return }
        let p = convert(event.locationInWindow, from: nil)
        if hypot(p.x - pressPoint.x, p.y - pressPoint.y) > 4 {
            didDrag = true
            let url = files[pressIndex]
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(iconRect(pressIndex), contents: fileIcon(url, size: iconSize))
            beginDraggingSession(with: [item], event: event, source: self)
        }
    }
    override func mouseUp(with event: NSEvent) {
        if pressIndex >= 0, !didDrag, pressIndex < files.count { onPick?(files[pressIndex]) }
        pressIndex = -1; didDrag = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    // Dropping files INTO the folder.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropActive = true; needsDisplay = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropActive = false; needsDisplay = true }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropActive = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let folder = folderURL,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        var changed = false
        for src in urls where src.standardizedFileURL.deletingLastPathComponent() != folder.standardizedFileURL {
            var dest = folder.appendingPathComponent(src.lastPathComponent)
            var n = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                let base = src.deletingPathExtension().lastPathComponent, ext = src.pathExtension
                dest = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"); n += 1
            }
            if (try? FileManager.default.copyItem(at: src, to: dest)) != nil { changed = true }
        }
        if changed { reload() }
        return changed
    }

    private func reload() {
        guard let folder = folderURL,
              let items = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        files = items.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.prefix(16).map { $0 }
        needsDisplay = true
    }
}
