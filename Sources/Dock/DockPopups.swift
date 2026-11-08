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
        p.setAccessibilityElement(false)   // a picture of a window, not one: no "new window" for VoiceOver
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

// MARK: - Folder stack (click a folder → fan, grid or list of what is in it)

/// What 10.5 to 10.8 offered on a dock folder's right-click: Sort by, Display as and View content
/// as (Apple, "Welcome to Snow Leopard", pp. 7–9). Kept per folder.
struct StackOptions: Codable, Equatable {
    enum Sort: String, Codable, CaseIterable {
        case name, dateAdded, dateModified, dateCreated, kind
        var title: String {
            switch self {
            case .name: "Name"
            case .dateAdded: "Date Added"
            case .dateModified: "Date Modified"
            case .dateCreated: "Date Created"
            case .kind: "Kind"
            }
        }
    }
    enum Display: String, Codable, CaseIterable {
        case folder, stack
        var title: String { self == .folder ? "Folder" : "Stack" }
    }
    enum ViewStyle: String, Codable, CaseIterable {
        case fan, grid, list, automatic
        var title: String { rawValue.capitalized }
    }

    var sort: Sort
    /// nil: what the theme shows on its own (Mountain Lion's pile, the folder elsewhere).
    var display: Display?
    var view: ViewStyle = .automatic

    /// Applications by name and Downloads by when things arrived, as 10.6 set them up; any other
    /// folder by what changed last, which is what RetroMac's stacks always showed.
    static func defaults(for path: String) -> StackOptions {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if url.path == "/Applications" { return StackOptions(sort: .name) }
        if url.lastPathComponent.caseInsensitiveCompare("Downloads") == .orderedSame { return StackOptions(sort: .dateAdded) }
        return StackOptions(sort: .dateModified)
    }

    private static let key = "dockStackOptions"

    static func load(_ path: String) -> StackOptions {
        guard let data = UserDefaults.standard.dictionary(forKey: key)?[path] as? Data,
              let o = try? JSONDecoder().decode(StackOptions.self, from: data) else { return defaults(for: path) }
        return o
    }

    static func save(_ o: StackOptions, for path: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[path] = try? JSONEncoder().encode(o)
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Everything in `dir` except hidden files: names A to Z, dates newest first, kinds grouped.
    /// No cap — a stack scrolls rather than leaving things out.
    static func contents(of dir: URL, sort: Sort) -> [URL] {
        let dateKey: URLResourceKey? = switch sort {
        case .dateAdded: .addedToDirectoryDateKey
        case .dateModified: .contentModificationDateKey
        case .dateCreated: .creationDateKey
        default: nil
        }
        let keys = [dateKey, URLResourceKey.localizedTypeDescriptionKey].compactMap { $0 }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let byName: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        if let k = dateKey {
            // Read once per file: a sort comparator asking the file system n log n times was slow
            // on a big Downloads folder.
            let dates = Dictionary(items.map { ($0, (try? $0.resourceValues(forKeys: [k]))?.allValues[k] as? Date ?? .distantPast) },
                                   uniquingKeysWith: { a, _ in a })
            return items.sorted { a, b in
                let da = dates[a]!, db = dates[b]!
                return da == db ? byName(a, b) : da > db
            }
        }
        if sort == .kind {
            let kinds = Dictionary(items.map { ($0, (try? $0.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? "") },
                                   uniquingKeysWith: { a, _ in a })
            return items.sorted { a, b in
                let ka = kinds[a]!, kb = kinds[b]!
                return ka == kb ? byName(a, b) : ka.localizedStandardCompare(kb) == .orderedAscending
            }
        }
        return items.sorted(by: byName)
    }

    /// A folder the stack can step into. An app or other package is a file here, as in Finder.
    static func isFolder(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return v?.isDirectory == true && v?.isPackage != true
    }
}

final class DockStackController {
    static let shared = DockStackController()
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private weak var view: DockStackView?
    /// The dock folder this stack belongs to, where it hangs, and the folders stepped into.
    private var rootPath = ""
    private var anchor = NSRect.zero
    private var shown: URL?
    private var trail: [URL] = []
    private init() {}

    func toggle(folderPath: String, anchorScreenRect: NSRect) {
        if panel?.isVisible == true { hide(); return }
        show(folderPath: folderPath, anchorScreenRect: anchorScreenRect)
    }

    func show(folderPath: String, anchorScreenRect: NSRect) {
        rootPath = folderPath
        anchor = anchorScreenRect
        trail = []
        let url = URL(fileURLWithPath: folderPath)
        let opts = StackOptions.load(folderPath)
        let items = StackOptions.contents(of: url, sort: opts.sort)
        switch opts.view {
        case .list:
            hide()
            let menu = StackListMenu(dir: url, sort: opts.sort)
            menu.menuNeedsUpdate(menu)   // its folders fill themselves when opened
            menu.popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY + 6), in: nil)
        case .grid:
            present(url, items: items, fan: false)
        case .fan, .automatic:
            // The fan rises off a dock along the bottom edge and only has room for so many;
            // Automatic takes it while everything fits, as 10.5 did, and the grid beyond that.
            // An empty folder gets the grid, which says where to drop things.
            let fits = fanAllowed && !items.isEmpty && items.count <= fanCapacity
            present(url, items: items, fan: opts.view == .fan ? fanAllowed : fits)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        HeldKeys.release("dockStack")
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    /// Fan is Aqua's (10.5 to 10.8, the "snowleopard" chrome) and needs the dock at the bottom.
    var fanAllowed: Bool {
        RetroFrameTheme.key() == "snowleopard"
            && ThemeManager.shared.activeTheme?.config.effectiveDockPosition == "bottom"
    }

    private var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
    }

    private var fanIconSize: CGFloat {
        min(max(ThemeManager.shared.activeTheme?.config.dock.iconSize ?? 48, 44), 56)
    }

    /// How many entries the fan holds above the dock, the Open in Finder entry at its top aside.
    private var fanCapacity: Int {
        let room = (screen?.visibleFrame.maxY ?? 900) - anchor.maxY - 24
        return max(1, Int(room / (fanIconSize + 6)) - 1)
    }

    private func present(_ url: URL, items: [URL], fan: Bool) {
        shown = url
        let cfg = ThemeManager.shared.activeTheme?.config
        let p = panel ?? makePanel()
        let view = DockStackView(frame: .zero)
        view.folderURL = url
        view.canGoBack = !trail.isEmpty
        view.fan = fan
        let frame: NSRect
        if fan {
            frame = layoutFan(view, items: items)
        } else {
            frame = layoutGrid(view, items: items, cfg: cfg)
        }
        p.setFrame(frame, display: false)
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.onPick = { [weak self] picked in self?.pick(picked) }
        view.onOpenFolder = { [weak self] in NSWorkspace.shared.open(url); self?.hide() }
        view.onBack = { [weak self] in self?.back() }
        view.onChanged = { [weak self] in self?.refresh() }
        p.contentView = view
        p.title = FileManager.default.displayName(atPath: url.path)   // what VoiceOver calls the stack
        p.invalidateShadow()      // the outline changes shape between folders
        p.orderFrontRegardless()
        panel = p
        self.view = view
        installDismissMonitor()
        // The arrows, Return and Esc while it is open: RetroMac stays in the background, so they
        // are held as hotkeys and let go on close, as the theme menus do.
        HeldKeys.hold("dockStack") { [weak self] key in
            guard let self else { return }
            if key == .escape { self.hide() } else { self.view?.key(key) }
        }
    }

    private func layoutGrid(_ view: DockStackView, items: [URL], cfg: DockThemeConfig?) -> NSRect {
        // 10.6's grid runs noticeably larger than a dock icon. The old 44...64 window made the
        // tiles read as a shrunken copy of the dock rather than a browser of their own.
        let iconSize = min(max(cfg?.dock.iconSize ?? 56, 56), 72)
        // 10.8 put Open in Finder into the grid as a tile of its own, the arrow in a circle.
        let openTile = cfg?.hasStackPreview == true
        let gap: CGFloat = 8, labelH: CGFloat = 14, headerH: CGFloat = 24
        let footerH: CGFloat = openTile ? 0 : 24, pad: CGFloat = 12
        let cellW = iconSize + 42, cellH = iconSize + labelH + 6
        // 10.6 hung the grid off a callout nose pointing back at the dock icon. Only this theme
        // draws one; everything else keeps its own window chrome.
        let noseH: CGFloat = RetroFrameTheme.key() == "snowleopard" ? 13 : 0

        let n = max(items.count + (openTile ? 1 : 0), 1)
        // Squarish, capped at the 7 columns the 10.6 grid uses.
        let cols = min(7, max(4, Int(ceil((Double(n) * 1.4).squareRoot()))))
        let rows = Int(ceil(Double(n) / Double(cols)))
        // Never taller than the screen: what does not fit scrolls, as 10.6's grid did.
        let room = (screen?.visibleFrame.height ?? 900) - anchor.height - 40 - noseH
        let maxRows = max(1, Int((room - headerH - footerH - pad * 2 + gap) / (cellH + gap)))
        let shownRows = min(rows, maxRows)

        let width = pad * 2 + CGFloat(cols) * cellW + CGFloat(cols - 1) * gap
        let height = headerH + pad + CGFloat(shownRows) * cellH + CGFloat(shownRows - 1) * gap + footerH + pad + noseH
        // The nose fills most of the old gap, so the tip ends up where the panel edge used to be.
        let frame = clampedAbove(anchor, size: NSSize(width: width, height: height), gap: noseH > 0 ? 6 : 10)

        view.files = items
        view.iconSize = iconSize
        view.openTile = openTile
        view.cols = cols; view.gap = gap; view.labelH = labelH
        view.headerH = headerH; view.footerH = footerH; view.pad = pad
        view.cellW = cellW; view.cellH = cellH
        view.contentRows = rows
        // No room above means the panel sat below the icon instead, and a nose would then point
        // away from what it is supposed to be attached to.
        view.noseH = frame.minY >= anchor.maxY ? noseH : 0
        view.noseCenterX = anchor.midX - frame.minX
        return frame
    }

    /// The fan: the first entry just above the dock, each one higher bending a little further
    /// right, names on dark labels to the left, Open in Finder (or "N more") at the top.
    private func layoutFan(_ view: DockStackView, items: [URL]) -> NSRect {
        let icon = fanIconSize, step = icon + 6
        let files = Array(items.prefix(fanCapacity))
        let count = files.count + 1
        let labelRoom: CGFloat = 250
        let bend = DockStackView.fanBend(count - 1)
        let width = labelRoom + icon + bend + 24
        let height = CGFloat(count) * step + 8
        var frame = NSRect(x: anchor.midX - (labelRoom + icon / 2), y: anchor.maxY + 2, width: width, height: height)
        if let vf = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, vf.minX + 4), vf.maxX - width - 4)
        }
        view.files = files
        view.openTile = true
        view.moreCount = items.count - files.count
        view.iconSize = icon
        view.cellH = step
        view.labelRoom = labelRoom
        view.fanX = anchor.midX - frame.minX
        return frame
    }

    private func pick(_ url: URL) {
        // 10.6's grid steps into a folder, with a back arrow up top; the fan opens it in Finder.
        if view?.fan == false, StackOptions.isFolder(url), let current = shown {
            trail.append(current)
            present(url, items: StackOptions.contents(of: url, sort: StackOptions.load(rootPath).sort), fan: false)
            return
        }
        NSWorkspace.shared.open(url)
        hide()
    }

    private func back() {
        guard let previous = trail.popLast() else { return }
        present(previous, items: StackOptions.contents(of: previous, sort: StackOptions.load(rootPath).sort), fan: false)
    }

    /// Something was dropped in: show the folder again with it.
    private func refresh() {
        guard let url = shown, let fan = view?.fan else { return }
        present(url, items: StackOptions.contents(of: url, sort: StackOptions.load(rootPath).sort), fan: fan)
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
}

/// View content as List: a menu of the folder, its folders as submenus filled when opened.
private final class StackListMenu: NSMenu, NSMenuDelegate {
    private let dir: URL
    private let sort: StackOptions.Sort

    init(dir: URL, sort: StackOptions.Sort) {
        self.dir = dir
        self.sort = sort
        super.init(title: FileManager.default.displayName(atPath: dir.path))
        delegate = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard items.isEmpty else { return }
        for url in StackOptions.contents(of: dir, sort: sort) {
            let item = ClosureMenuItem(title: FileManager.default.displayName(atPath: url.path)) {
                NSWorkspace.shared.open(url)
            }
            item.image = DockStackView.icon(for: url, size: 16)
            if StackOptions.isFolder(url) { item.submenu = StackListMenu(dir: url, sort: sort) }
            addItem(item)
        }
        if !items.isEmpty { addItem(.separator()) }
        addItem(ClosureMenuItem(title: "Open in Finder") { [dir] in NSWorkspace.shared.open(dir) })
    }
}

final class DockStackView: NSView, NSDraggingSource {
    var folderURL: URL?
    var files: [URL] = []
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
    /// Rows in the whole grid; more than fit on screen scroll.
    var contentRows = 1
    var onPick: ((URL) -> Void)?
    var onOpenFolder: (() -> Void)?
    var onBack: (() -> Void)?
    var onChanged: (() -> Void)?
    /// Open in Finder as the last tile instead of a footer line (10.8's grid, every fan).
    var openTile = false
    /// Stepped into a subfolder: the header carries a back arrow.
    var canGoBack = false

    /// The fan instead of the grid.
    var fan = false
    /// The fan's icon column, at the bottom entry, in this view's coordinates.
    var fanX: CGFloat = 0
    var labelRoom: CGFloat = 250
    /// Entries the fan had no room for, counted on its top entry.
    var moreCount = 0

    /// Highlighted entry, by mouse or by arrow key. `files.count` is the Open in Finder tile.
    private var hovered = -1
    private var scrollY: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    private var pressIndex = -1
    private var pressPoint = NSPoint.zero
    private var didDrag = false
    private var dropActive = false
    private let pixelize = ThemeManager.shared.activeTheme?.config.isPixelated == true
    var chrome = RetroFrameTheme.key()
    /// Quick Look previews, keyed by path + modification date so an edited file re-renders.
    /// Static so reopening the stack does not regenerate what it already has — and bounded:
    /// every file a stack ever showed, in every version, used to stay for the whole session
    /// (a Downloads stack gathers a new one with every download).
    private static let thumbs: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 600
        c.totalCostLimit = 64 * 1024 * 1024   // bytes of pixels
        return c
    }()
    private var requested = Set<String>()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var entryCount: Int { files.count + (openTile ? 1 : 0) }

    /// VoiceOver: each file a button named after it that opens it, as a click does.
    private var axParts: [AccessibleHotspot] = []
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { folderURL.map { FileManager.default.displayName(atPath: $0.path) } }
    override func accessibilityChildren() -> [Any]? {
        axParts = files.indices.map { i in
            let url = files[i]
            return AccessibleHotspot.make(in: self, label: FileManager.default.displayName(atPath: url.path), rect: hitRect(i)) { [weak self] in self?.onPick?(url) }
        }
        if openTile {
            axParts.append(AccessibleHotspot.make(in: self, label: openLabel, rect: hitRect(files.count)) { [weak self] in self?.onOpenFolder?() })
        }
        if canGoBack {
            axParts.insert(AccessibleHotspot.make(in: self, label: "Back", rect: backRect) { [weak self] in self?.onBack?() }, at: 0)
        }
        return axParts
    }

    private var openLabel: String { moreCount > 0 ? "\(moreCount) more in Finder" : "Open in Finder" }

    // MARK: Geometry

    /// The fan's curve: how far right entry `i` (0 at the bottom) sits off the column.
    static func fanBend(_ i: Int) -> CGFloat { 0.7 * CGFloat(i * i) }

    private func cellRect(_ i: Int) -> NSRect {
        let row = i / cols, col = i % cols
        return NSRect(x: pad + CGFloat(col) * (cellW + gap),
                      y: headerH + pad + CGFloat(row) * (cellH + gap) - scrollY,
                      width: cellW, height: cellH)
    }
    private func iconRect(_ i: Int) -> NSRect {
        if fan {
            let y = bounds.height - 4 - CGFloat(i + 1) * cellH + (cellH - iconSize) / 2
            return NSRect(x: fanX + Self.fanBend(i) - iconSize / 2, y: y, width: iconSize, height: iconSize)
        }
        let c = cellRect(i)
        return NSRect(x: c.midX - iconSize / 2, y: c.minY, width: iconSize, height: iconSize)
    }
    /// Where a click lands on entry `i`: the grid cell, or the fan's icon and its label.
    private func hitRect(_ i: Int) -> NSRect {
        guard fan else { return cellRect(i) }
        let icon = iconRect(i)
        return NSRect(x: icon.minX - labelRoom, y: icon.minY, width: labelRoom + icon.width, height: icon.height)
    }
    /// The part of the grid between header and footer; cells scroll under its edges.
    private var gridClip: NSRect { NSRect(x: 0, y: headerH, width: bounds.width, height: slab.height - headerH - footerH) }
    private var maxScroll: CGFloat {
        let content = CGFloat(contentRows) * cellH + CGFloat(contentRows - 1) * gap
        return max(0, content - (gridClip.height - pad * 2))
    }
    private func entry(at p: NSPoint) -> Int? {
        if !fan && !gridClip.contains(p) { return nil }
        return (0..<entryCount).first { hitRect($0).contains(p) }
    }
    /// The slab proper, without the strip the nose hangs down into.
    private var slab: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - noseH) }
    private var footerRect: NSRect { NSRect(x: 0, y: slab.height - footerH, width: bounds.width, height: footerH) }
    private var backRect: NSRect {
        NSRect(x: chrome == "maiksfav" ? 58 : 6, y: 3, width: 24, height: headerH - 6)
    }

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

    // MARK: Icons

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
        guard !requested.contains(key), Self.thumbs.object(forKey: key as NSString) == nil else { return }
        requested.insert(key)
        let scale = window?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(fileAt: url,
                                               size: NSSize(width: iconSize, height: iconSize),
                                               scale: scale,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let rep = rep else { return }
            let img = NSImage(cgImage: rep.cgImage, size: NSSize(width: rep.cgImage.width, height: rep.cgImage.height))
            let cost = rep.cgImage.width * rep.cgImage.height * 4
            DispatchQueue.main.async {
                Self.thumbs.setObject(img, forKey: key as NSString, cost: cost)
                self?.needsDisplay = true
            }
        }
    }

    /// Apps wear whatever the dock would give them: theme mapping first, then a custom icon the
    /// user set, then the real one. Keeps the stack consistent with the dock beside it.
    static func icon(for url: URL, size: CGFloat) -> NSImage {
        if url.pathExtension == "app", let bid = Bundle(url: url)?.bundleIdentifier {
            return ThemeManager.shared.icon(for: bid, size: size)
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    private func fileIcon(_ url: URL, size: CGFloat) -> NSImage {
        if url.pathExtension == "app" { return Self.icon(for: url, size: size) }
        if let t = Self.thumbs.object(forKey: thumbKey(url) as NSString) { return t }
        requestThumbnail(url)
        let icon = Self.icon(for: url, size: size)
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

    private func openArrow(_ size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: "arrowshape.turn.up.right.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular).applying(.init(paletteColors: [.white])))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if fan { drawFan(); return }
        let header = NSRect(x: 0, y: 0, width: bounds.width, height: headerH)
        let snowLeopard = chrome == "snowleopard"
        let title = folderURL.map { FileManager.default.displayName(atPath: $0.path) } ?? "Folder"
        var headerInk = NSColor.white
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
            let ts = title.size(withAttributes: hAttrs)
            title.draw(at: NSPoint(x: bounds.width / 2 - ts.width / 2, y: 5), withAttributes: hAttrs)
        } else if chrome == "maiksfav" {
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
            let ha: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Pixelify Sans", size: 12) ?? .boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor(calibratedWhite: 0.23, alpha: 1)]
            let ts = title.size(withAttributes: ha)
            title.draw(at: NSPoint(x: bounds.width/2 - ts.width/2, y: 4), withAttributes: ha)
            headerInk = NSColor(calibratedWhite: 0.23, alpha: 1)
        } else {
            NSColor(calibratedWhite: 0.96, alpha: 0.98).setFill(); bounds.fill()
            (dropActive ? NSColor(calibratedRed: 0.2, green: 0.5, blue: 1, alpha: 1)
                        : NSColor(calibratedWhite: 0.30, alpha: 1)).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)); border.lineWidth = dropActive ? 2 : 1; border.stroke()
            NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1).setFill(); header.fill()
            let hAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.0, alpha: 1)]
            title.draw(at: NSPoint(x: canGoBack ? backRect.maxX + 6 : 8, y: 4), withAttributes: hAttrs)
            headerInk = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        }
        if canGoBack { drawBack(ink: headerInk, plate: snowLeopard) }

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

        NSGraphicsContext.saveGraphicsState()
        gridClip.clip()
        let hover = snowLeopard || openTile ? NSColor(calibratedWhite: 1, alpha: 0.20)
                                            : NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.95, alpha: 0.18)
        for i in 0..<entryCount {
            let c = cellRect(i)
            // Only what is in view: a folder of thousands draws a screenful and asks Quick Look
            // for that screenful, not for everything in it.
            guard c.intersects(gridClip) else { continue }
            if i == hovered { hover.setFill(); NSBezierPath(roundedRect: c.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill() }
            if i == files.count {
                if let arrow = openArrow(iconSize * 0.62) {
                    arrow.draw(in: iconDrawRect(arrow, in: iconRect(i).insetBy(dx: iconSize * 0.12, dy: iconSize * 0.12)),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                let label = "Open in Finder", ls = label.size(withAttributes: lAttrs)
                label.draw(at: NSPoint(x: c.midX - ls.width / 2, y: c.minY + iconSize + 2), withAttributes: lAttrs)
                continue
            }
            let url = files[i]
            let img = fileIcon(url, size: iconSize)
            img.draw(in: iconDrawRect(img, in: iconRect(i)), from: .zero, operation: .sourceOver,
                     fraction: 1, respectFlipped: true,
                     hints: [.interpolation: NSImageInterpolation.high])
            let label = fitted(url.lastPathComponent, width: cellW - 4, attrs: lAttrs)
            let ls = label.size(withAttributes: lAttrs)
            label.draw(at: NSPoint(x: c.midX - ls.width / 2, y: c.minY + iconSize + 2), withAttributes: lAttrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        drawScroller(light: snowLeopard)

        guard !openTile else { return }
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
        "Open in Finder".draw(at: NSPoint(x: 8, y: f.midY - 7), withAttributes: fAttrs)
    }

    /// The back arrow at the header's left, once the grid has stepped into a folder.
    private func drawBack(ink: NSColor, plate: Bool) {
        let r = backRect
        if plate {
            NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
            NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        }
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.midX + 3, y: r.midY - 5))
        p.line(to: NSPoint(x: r.midX - 3, y: r.midY))
        p.line(to: NSPoint(x: r.midX + 3, y: r.midY + 5))
        p.lineWidth = 2; p.lineCapStyle = .round; p.lineJoinStyle = .round
        ink.setStroke(); p.stroke()
    }

    /// A thin bar at the right edge while there is more than fits.
    private func drawScroller(light: Bool) {
        guard maxScroll > 0 else { return }
        let track = gridClip.insetBy(dx: 0, dy: 6)
        let visible = gridClip.height - pad * 2
        let h = max(24, track.height * visible / (visible + maxScroll))
        let y = track.minY + (track.height - h) * scrollY / maxScroll
        (light ? NSColor(calibratedWhite: 1, alpha: 0.35) : NSColor(calibratedWhite: 0, alpha: 0.3)).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.width - 7, y: y, width: 4, height: h), xRadius: 2, yRadius: 2).fill()
    }

    private func drawFan() {
        let font = NSFont(name: "Lucida Grande", size: 12) ?? .systemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        for i in 0..<entryCount {
            let icon = iconRect(i)
            let isOpen = i == files.count
            let name = isOpen ? openLabel : FileManager.default.displayName(atPath: files[i].path)
            let text = fitted(name, width: labelRoom - 28, attrs: attrs)
            let ts = text.size(withAttributes: attrs)
            let pill = NSRect(x: icon.minX - 10 - ts.width - 16, y: icon.midY - 10, width: ts.width + 16, height: 20)
            (i == hovered ? NSColor(calibratedRed: 0.22, green: 0.47, blue: 0.93, alpha: 0.95)
                          : NSColor(calibratedWhite: 0, alpha: 0.62)).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
            text.draw(at: NSPoint(x: pill.minX + 8, y: pill.midY - ts.height / 2), withAttributes: attrs)

            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            if isOpen {
                if let arrow = openArrow(iconSize * 0.6) {
                    arrow.draw(in: iconDrawRect(arrow, in: icon.insetBy(dx: iconSize * 0.15, dy: iconSize * 0.15)),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            } else {
                let img = fileIcon(files[i], size: iconSize)
                img.draw(in: iconDrawRect(img, in: icon), from: .zero, operation: .sourceOver,
                         fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseMoved(with event: NSEvent) {
        let now = entry(at: convert(event.locationInWindow, from: nil)) ?? -1
        if now != hovered { hovered = now; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { if hovered != -1 { hovered = -1; needsDisplay = true } }

    override func scrollWheel(with event: NSEvent) {
        guard !fan, maxScroll > 0 else { return }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        scrollY = min(max(0, scrollY - dy), maxScroll)
        mouseMoved(with: event)
        needsDisplay = true
    }

    // Click opens; press-and-drag drags the file OUT to Finder/other apps.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        didDrag = false; pressIndex = -1
        if canGoBack, backRect.contains(p) { onBack?(); return }
        if !openTile, footerRect.contains(p) { onOpenFolder?(); return }
        guard let i = entry(at: p) else { return }
        if i == files.count { onOpenFolder?(); return }
        pressIndex = i; pressPoint = p
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

    // MARK: Keys

    /// Arrows move the highlight (in the fan, Up climbs away from the dock), Return opens it.
    func key(_ key: NavKey) {
        guard entryCount > 0 else { return }
        if key == .enter {
            guard hovered >= 0 else { return }
            if hovered == files.count { onOpenFolder?() } else { onPick?(files[hovered]) }
            return
        }
        guard hovered >= 0 else { hovered = 0; reveal(); return }
        let delta: Int
        switch (key, fan) {
        case (.up, true): delta = 1
        case (.down, true): delta = -1
        case (.up, false): delta = -cols
        case (.down, false): delta = cols
        case (.left, false): delta = -1
        case (.right, false): delta = 1
        default: return
        }
        hovered = min(max(0, hovered + delta), entryCount - 1)
        reveal()
    }

    /// Scroll the highlighted cell into view.
    private func reveal() {
        if !fan, hovered >= 0 {
            let c = cellRect(hovered), clip = gridClip.insetBy(dx: 0, dy: pad)
            if c.minY < clip.minY { scrollY -= clip.minY - c.minY }
            if c.maxY > clip.maxY { scrollY += c.maxY - clip.maxY }
            scrollY = min(max(0, scrollY), maxScroll)
        }
        needsDisplay = true
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
        if changed { onChanged?() }
        return changed
    }
}
