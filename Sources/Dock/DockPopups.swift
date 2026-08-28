import AppKit
import QuickLookThumbnailing

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
        // /Applications is the one stack that lists everything alphabetically; a Downloads-style
        // stack shows what arrived last. That is what 10.6 does with each.
        let isApplications = url.standardizedFileURL.path == "/Applications"

        let cfg = ThemeManager.shared.activeTheme?.config
        // 10.6's grid runs noticeably larger than a dock icon. The old 44...64 window made the
        // tiles read as a shrunken copy of the dock rather than a browser of their own.
        let iconSize = min(max(cfg?.dock.iconSize ?? 56, 56), 72)
        let gap: CGFloat = 8, labelH: CGFloat = 14, headerH: CGFloat = 24
        let footerH: CGFloat = 24, pad: CGFloat = 12
        let cellW = iconSize + 42, cellH = iconSize + labelH + 6
        // 10.6 hung the grid off a callout nose pointing back at the dock icon. Only this theme
        // draws one; everything else keeps its own window chrome.
        let noseH: CGFloat = RetroFrameTheme.key() == "snowleopard" ? 13 : 0

        let all = isApplications ? applications() : recentFiles(in: url, limit: 40)
        let n = max(all.count, 1)
        // Squarish, capped at the 7 columns the 10.6 grid uses.
        let cols = min(7, max(4, Int(ceil((Double(n) * 1.4).squareRoot()))))

        // Never build a panel taller than the screen: clampedAbove only repositions, it does not
        // shrink, so an uncapped /Applications would run straight off the top.
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorScreenRect) }) ?? NSScreen.main
        let room = (screen?.visibleFrame.height ?? 900) - anchorScreenRect.height - 40 - noseH
        let maxRows = max(1, Int((room - headerH - footerH - pad * 2 + gap) / (cellH + gap)))
        let files = Array(all.prefix(cols * maxRows))

        let rows = max(1, Int(ceil(Double(max(files.count, 1)) / Double(cols))))
        let width = pad * 2 + CGFloat(cols) * cellW + CGFloat(cols - 1) * gap
        let height = headerH + pad + CGFloat(rows) * cellH + CGFloat(rows - 1) * gap + footerH + pad + noseH
        // The nose fills most of the old gap, so the tip ends up where the panel edge used to be.
        let frame = clampedAbove(anchorScreenRect, size: NSSize(width: width, height: height),
                                 gap: noseH > 0 ? 6 : 10)

        let p = panel ?? makePanel()
        p.setFrame(frame, display: false)
        let view = DockStackView(frame: NSRect(origin: .zero, size: frame.size))
        view.folderURL = url
        view.files = files
        view.isApplications = isApplications
        // Only meaningful for /Applications, which claims to list everything. A recent-files
        // stack shows the newest by design, so "N more" there would be noise, and the number
        // would be relative to the fetch limit rather than the folder anyway.
        view.truncatedCount = isApplications ? all.count - files.count : 0
        view.iconSize = iconSize
        view.cols = cols; view.gap = gap; view.labelH = labelH
        view.headerH = headerH; view.footerH = footerH; view.pad = pad
        view.cellW = cellW; view.cellH = cellH
        // No room above means the panel sat below the icon instead, and a nose would then point
        // away from what it is supposed to be attached to.
        view.noseH = frame.minY >= anchorScreenRect.maxY ? noseH : 0
        view.noseCenterX = anchorScreenRect.midX - frame.minX
        view.onPick = { [weak self] picked in NSWorkspace.shared.open(picked); self?.hide() }
        view.onOpenFolder = { [weak self] in NSWorkspace.shared.open(url); self?.hide() }
        p.contentView = view
        p.invalidateShadow()      // the outline changes shape between folders
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

    /// Everything installed, the way the 10.6 Applications stack lists it: by name, not by date.
    private func applications() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"),
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
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
    /// /Applications lists apps by name and wears their themed artwork; other folders list
    /// recent files and get Quick Look previews.
    var isApplications = false
    /// How many entries did not fit on screen. Shown in the footer rather than dropped quietly.
    var truncatedCount = 0
    var iconSize: CGFloat = 56
    /// How far the callout nose hangs below the slab. 0 draws none.
    var noseH: CGFloat = 0
    /// Where the nose points, in this view's coordinates — the centre of the dock icon.
    var noseCenterX: CGFloat = 0
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
    /// Quick Look previews, keyed by path + modification date so an edited file re-renders.
    /// Static so reopening the stack does not regenerate what it already has.
    private static var thumbs: [String: NSImage] = [:]
    private var requested = Set<String>()

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
    /// The slab proper, without the strip the nose hangs down into.
    private var slab: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - noseH) }
    private var footerRect: NSRect { NSRect(x: 0, y: slab.height - footerH, width: bounds.width, height: footerH) }

    /// A rounded slab with a triangular nose on its bottom edge, as one path — filling a rect and
    /// then a triangle separately leaves the outline drawing a line straight across the nose's base.
    private func slabPath(_ r: NSRect, radius rad: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX, y: r.minY + rad))
        p.appendArc(from: NSPoint(x: r.minX, y: r.minY), to: NSPoint(x: r.minX + rad, y: r.minY), radius: rad)
        p.line(to: NSPoint(x: r.maxX - rad, y: r.minY))
        p.appendArc(from: NSPoint(x: r.maxX, y: r.minY), to: NSPoint(x: r.maxX, y: r.minY + rad), radius: rad)
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - rad))
        p.appendArc(from: NSPoint(x: r.maxX, y: r.maxY), to: NSPoint(x: r.maxX - rad, y: r.maxY), radius: rad)
        if noseH > 0 {
            // Measured off the 10.6 reference: about twice as wide as it is tall, tip softened.
            let half = noseH
            let cx = min(max(noseCenterX, r.minX + rad + half + 2), r.maxX - rad - half - 2)
            p.line(to: NSPoint(x: cx + half, y: r.maxY))
            p.appendArc(from: NSPoint(x: cx, y: r.maxY + noseH),
                        to: NSPoint(x: cx - half, y: r.maxY), radius: 2.5)
            p.line(to: NSPoint(x: cx - half, y: r.maxY))
        }
        p.line(to: NSPoint(x: r.minX + rad, y: r.maxY))
        p.appendArc(from: NSPoint(x: r.minX, y: r.maxY), to: NSPoint(x: r.minX, y: r.maxY - rad), radius: rad)
        p.close()
        return p
    }

    private func thumbKey(_ url: URL) -> String {
        let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)|\(Int(m))|\(Int(iconSize))"
    }

    /// Ask Quick Look for a real preview. NSWorkspace only ever returns the generic icon for a
    /// file type, which is why a folder of screenshots and PDFs came up as a wall of identical
    /// placeholders. Async: the workspace icon is drawn until this arrives.
    private func requestThumbnail(_ url: URL) {
        let key = thumbKey(url)
        guard !requested.contains(key), Self.thumbs[key] == nil else { return }
        requested.insert(key)
        let scale = window?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(fileAt: url,
                                               size: NSSize(width: iconSize, height: iconSize),
                                               scale: scale,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let rep = rep else { return }
            let img = NSImage(cgImage: rep.cgImage, size: NSSize(width: rep.cgImage.width, height: rep.cgImage.height))
            DispatchQueue.main.async {
                Self.thumbs[key] = img
                self?.needsDisplay = true
            }
        }
    }

    private func fileIcon(_ url: URL, size: CGFloat) -> NSImage {
        // Apps wear whatever the dock would give them: theme mapping first, then a custom icon
        // the user set, then the real one. Keeps the grid consistent with the dock beside it.
        if url.pathExtension == "app", let bid = Bundle(url: url)?.bundleIdentifier {
            return ThemeManager.shared.icon(for: bid, size: size)
        }
        if let t = Self.thumbs[thumbKey(url)] { return t }
        requestThumbnail(url)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return pixelize ? ThemeManager.shared.pixelatedIfNeeded(icon, size: size) : icon
    }

    /// Fit into the icon box without distorting: a Quick Look preview of a photo is not square.
    private func iconDrawRect(_ img: NSImage, in box: NSRect) -> NSRect {
        let s = img.size
        guard s.width > 0, s.height > 0 else { return box }
        let f = min(box.width / s.width, box.height / s.height)
        let w = s.width * f, h = s.height * f
        return NSRect(x: box.midX - w / 2, y: box.maxY - h, width: w, height: h)
    }

    /// Middle truncation, the way Finder and the real stacks shorten a long file name.
    private func fitted(_ name: String, width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> String {
        guard name.size(withAttributes: attrs).width > width else { return name }
        var head = Array(name), tail: [Character] = []
        while head.count > 1 {
            if head.count > tail.count { tail.insert(head.removeLast(), at: 0) } else { head.removeLast() }
            let candidate = String(head) + "\u{2026}" + String(tail.dropFirst(max(0, tail.count - head.count)))
            if candidate.size(withAttributes: attrs).width <= width { return candidate }
        }
        return "\u{2026}"
    }

    override func draw(_ dirtyRect: NSRect) {
        let header = NSRect(x: 0, y: 0, width: bounds.width, height: headerH)
        let key = RetroFrameTheme.key()
        let snowLeopard = key == "snowleopard"
        if snowLeopard {
            // 10.6 grid stack: a dark translucent rounded slab, white labels, no window chrome.
            let panel = slabPath(slab.insetBy(dx: 0.5, dy: 0.5), radius: 6)
            NSColor(calibratedWhite: 0.11, alpha: 0.88).setFill(); panel.fill()
            (dropActive ? NSColor(calibratedRed: 0.35, green: 0.62, blue: 1, alpha: 0.9)
                        : NSColor(calibratedWhite: 1, alpha: 0.22)).setStroke()
            panel.lineWidth = dropActive ? 2 : 1; panel.stroke()
            let hAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Lucida Grande Bold", size: 11) ?? .systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.92)]
            let title = folderURL?.lastPathComponent ?? "Folder"
            let ts = title.size(withAttributes: hAttrs)
            title.draw(at: NSPoint(x: bounds.width / 2 - ts.width / 2, y: 5), withAttributes: hAttrs)
        } else if key == "maiksfav" {
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
        let lAttrs: [NSAttributedString.Key: Any] = snowLeopard
            ? [.font: NSFont(name: "Lucida Grande", size: 10) ?? .systemFont(ofSize: 10),
               .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.95),
               .shadow: { let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.8)
                          sh.shadowBlurRadius = 2; sh.shadowOffset = .zero; return sh }()]
            : [.font: NSFont.systemFont(ofSize: 10),
               .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)]
        for (i, url) in files.enumerated() {
            let c = cellRect(i)
            if i == hovered { (snowLeopard ? NSColor(calibratedWhite: 1, alpha: 0.20)
                                            : NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.95, alpha: 0.18)).setFill()
                NSBezierPath(roundedRect: c.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill() }
            let img = fileIcon(url, size: iconSize)
            img.draw(in: iconDrawRect(img, in: iconRect(i)), from: .zero, operation: .sourceOver,
                     fraction: 1, respectFlipped: true,
                     hints: [.interpolation: NSImageInterpolation.high])
            let label = fitted(url.lastPathComponent, width: cellW - 4, attrs: lAttrs)
            let ls = label.size(withAttributes: lAttrs)
            label.draw(at: NSPoint(x: c.midX - ls.width / 2, y: c.minY + iconSize + 2), withAttributes: lAttrs)
        }

        let f = footerRect
        if snowLeopard {
            NSColor(calibratedWhite: 1, alpha: 0.06).setFill(); f.fill()
            NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
        } else {
            NSColor(calibratedWhite: 0.88, alpha: 1).setFill(); f.fill()
            NSColor(calibratedWhite: 0.30, alpha: 1).setStroke()
        }
        let top = NSBezierPath(); top.move(to: NSPoint(x: 0, y: f.minY)); top.line(to: NSPoint(x: f.maxX, y: f.minY)); top.stroke()
        let fAttrs: [NSAttributedString.Key: Any] = snowLeopard
            ? [.font: NSFont(name: "Lucida Grande", size: 11) ?? .systemFont(ofSize: 11),
               .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.9)]
            : [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
               .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1)]
        // Say what did not fit rather than dropping it silently.
        let footer = truncatedCount > 0 ? "Open in Finder  (\(truncatedCount) more)" : "Open in Finder"
        footer.draw(at: NSPoint(x: 8, y: f.midY - 7), withAttributes: fAttrs)
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
