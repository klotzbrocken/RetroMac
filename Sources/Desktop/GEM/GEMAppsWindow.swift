import AppKit

/// An installed app as APPS lists it.
struct GEMApp: Equatable {
    let url: URL
    let name: String
    let bundleID: String?
    /// The App Store category it declares, short ("productivity"); empty when it declares none.
    let category: String
    var location: String { url.deletingLastPathComponent().path }
}

/// The apps the catalogue shows (Lastenheft section 5): the system's, the shared and the
/// personal Applications folders, the Utilities, and the vendor folders one level down; plus apps
/// installed on the desktop from elsewhere. An app is one entry however deep its helpers go.
enum GEMApps {
    static var roots: [URL] {
        ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
            .map { URL(fileURLWithPath: $0) }
    }

    /// File reading: off the main thread.
    static func scan(roots: [URL], extra: [URL] = []) -> [GEMApp] {
        let fm = FileManager.default
        var found: [URL] = []
        for root in roots {
            for child in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: .skipsHiddenFiles)) ?? [] {
                if child.pathExtension == "app" { found.append(child); continue }
                let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                guard v?.isDirectory == true, v?.isPackage != true else { continue }
                found += ((try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
                    .filter { $0.pathExtension == "app" }
            }
        }
        var seen = Set<String>(), out: [GEMApp] = []
        let all = found + extra.filter { fm.fileExists(atPath: $0.path) }
        let isLink = { (u: URL) in (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true }
        for url in all.filter({ !isLink($0) }) + all.filter(isLink) {   // the app itself, not a link to it, gives the name
            guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
            let bundle = Bundle(url: url)
            let declared = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String ?? ""
            out.append(GEMApp(url: url, name: fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                              bundleID: bundle?.bundleIdentifier,
                              category: declared.replacingOccurrences(of: "public.app-category.", with: "")))
        }
        return out
    }

    static func sorted(_ apps: [GEMApp], byType: Bool) -> [GEMApp] {
        apps.sorted {
            if byType, $0.category != $1.category {
                if $0.category.isEmpty || $1.category.isEmpty { return !$0.category.isEmpty }   // undeclared last
                return $0.category < $1.category
            }
            let n = $0.name.localizedStandardCompare($1.name)
            return n == .orderedSame ? $0.url.path < $1.url.path : n == .orderedAscending
        }
    }

    /// Starts the app, or brings it forward if it runs: the copy chosen, by its path.
    static func open(_ app: GEMApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { _, error in
            if error != nil { DispatchQueue.main.async { GEMDialog.show([.text("\(app.name)"), .text("could not be opened.")], buttons: ["OK"]) } }
        }
    }

    /// The theme's picture for an app (`iconMappings`, with its `_sel` state beside it), else the
    /// TOS program icon; a user's own icon for the app wins, as everywhere.
    private static var cache: [String: NSImage] = [:]
    static func icon(bundleID: String?, selected: Bool) -> NSImage? {
        guard let theme = ThemeManager.shared.activeTheme else { return nil }
        let key = "\(theme.stableID)|\(bundleID ?? "-")|\(selected)"
        if let i = cache[key] { return i }
        var file = bundleID.flatMap { theme.config.iconMappings[$0] }
        if bundleID.map({ ThemeManager.shared.hasThemedIcon(for: $0) }) == true, file == nil {
            return ThemeManager.shared.icon(for: bundleID!, size: 32)   // a user's or a package's icon: no selected state of its own
        }
        if file == nil { file = theme.config.fallbackIcon }
        guard var name = file else { return nil }
        if selected { name = name.replacingOccurrences(of: ".png", with: "_sel.png") }
        let i = theme.iconResource(name).flatMap { NSImage(contentsOf: $0) }
        cache[key] = i
        return i
    }
}

/// View settings for APPS, kept between sessions.
enum GEMAppsSettings {
    static var asText: Bool {
        get { UserDefaults.standard.bool(forKey: "gemAppsAsText") }
        set { UserDefaults.standard.set(newValue, forKey: "gemAppsAsText"); GEMAppsWindowController.shared.view?.relayout() }
    }
    static var byType: Bool {
        get { UserDefaults.standard.bool(forKey: "gemAppsByType") }
        set { UserDefaults.standard.set(newValue, forKey: "gemAppsByType"); GEMAppsWindowController.shared.view?.resort() }
    }
    static var sizeToFit: Bool {
        get { UserDefaults.standard.object(forKey: "gemAppsSizeToFit") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "gemAppsSizeToFit"); GEMAppsWindowController.shared.view?.relayout() }
    }
}

final class GEMWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class GEMAppsWindowController {
    static let shared = GEMAppsWindowController()
    private var window: GEMWindow?
    var view: GEMAppsView? { window?.contentView as? GEMAppsView }
    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let screen = NSScreen.screens.first ?? NSScreen.main!
            let top = GEMDesktopController.barHeight(on: screen)
            // Beside the drive column, as a drive window opened on the Falcon.
            let f = NSRect(x: screen.frame.minX + 100, y: screen.frame.maxY - top - 30 - 360, width: 480, height: 360)
            let w = GEMWindow(contentRect: f, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.hasShadow = false
            w.title = "APPS"
            w.minSize = NSSize(width: 200, height: 140)
            w.contentView = GEMAppsView(frame: NSRect(origin: .zero, size: f.size))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        view?.rescan()
    }

    func close() { window?.orderOut(nil) }
}

/// The APPS window in GEM's furniture (D6, `_3.png`): the close box at the left of the title bar,
/// the full box at its right, the info line under it, scroll arrows and stippled tracks with a
/// grey slider, the size box in the bottom right corner.
final class GEMAppsView: NSView {
    private var all: [GEMApp] = []
    private(set) var apps: [GEMApp] = []
    private var selected: Int? { didSet { needsDisplay = true } }
    private var scroll = NSPoint.zero
    private var savedFrame: NSRect?
    private var typed = "", typedAt = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    static let g: CGFloat = 23   // a gadget with its line; neighbours share the line

    override init(frame: NSRect) {
        super.init(frame: frame)
        for n in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] note in
                if (note.object as? NSWindow) === self?.window { self?.needsDisplay = true }
            })
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var selectedApp: GEMApp? { selected.flatMap { $0 < apps.count ? apps[$0] : nil } }

    func rescan() {
        let extra = DesktopStore.load(theme: ThemeManager.shared.activeTheme?.config.settingsKey ?? "gem").added
            .compactMap { $0.path.map { URL(fileURLWithPath: $0) } }
        DispatchQueue.global(qos: .userInitiated).async {
            let found = GEMApps.scan(roots: GEMApps.roots, extra: extra)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let keep = self.selectedApp?.url
                self.all = found
                self.resort()
                self.selected = keep.flatMap { u in self.apps.firstIndex { $0.url == u } }
            }
        }
    }

    func resort() {
        let keep = selectedApp?.url
        apps = GEMApps.sorted(all, byType: GEMAppsSettings.byType)
        selected = keep.flatMap { u in apps.firstIndex { $0.url == u } }
        relayout()
    }

    func relayout() { clampScroll(); needsDisplay = true }

    // MARK: Geometry

    private var W: CGFloat { bounds.width }
    private var H: CGFloat { bounds.height }
    private var g: CGFloat { Self.g }
    var closeBox: NSRect { NSRect(x: 0, y: 0, width: g, height: g) }
    var fullBox: NSRect { NSRect(x: W - g, y: 0, width: g, height: g) }
    var titleBar: NSRect { NSRect(x: g - 1, y: 0, width: W - 2 * g + 2, height: g) }
    var infoLine: NSRect { NSRect(x: 0, y: g - 1, width: W, height: 18) }
    var contentBox: NSRect { NSRect(x: 0, y: infoLine.maxY - 1, width: W - g + 1, height: H - infoLine.maxY + 1 - g + 1) }
    var content: NSRect { contentBox.insetBy(dx: 1, dy: 1) }
    var upBox: NSRect { NSRect(x: W - g, y: contentBox.minY, width: g, height: g) }
    var downBox: NSRect { NSRect(x: W - g, y: H - 2 * g + 1, width: g, height: g) }
    var vTrack: NSRect { NSRect(x: W - g, y: upBox.maxY - 1, width: g, height: downBox.minY - upBox.maxY + 2) }
    var leftBox: NSRect { NSRect(x: 0, y: H - g, width: g, height: g) }
    var rightBox: NSRect { NSRect(x: W - 2 * g + 1, y: H - g, width: g, height: g) }
    var hTrack: NSRect { NSRect(x: leftBox.maxX - 1, y: H - g, width: rightBox.minX - leftBox.maxX + 2, height: g) }
    var sizeBox: NSRect { NSRect(x: W - g, y: H - g, width: g, height: g) }

    private var cellW: CGFloat { GEMChrome.cellW }
    private var cellH: CGFloat { GEMChrome.cellH }
    /// Icon columns: as many as the window holds with Size to Fit, else a fixed eight.
    var columns: Int { GEMAppsSettings.sizeToFit ? max(1, Int(content.width / cellW)) : 8 }
    static let textChars = 64
    var contentSize: NSSize {
        if GEMAppsSettings.asText { return NSSize(width: CGFloat(Self.textChars) * GEMChrome.charW, height: CGFloat(apps.count) * GEMChrome.rowH + 4) }
        let rows = (apps.count + columns - 1) / columns
        return NSSize(width: CGFloat(columns) * cellW, height: CGFloat(rows) * cellH + 4)
    }
    /// An entry's rectangle in view coordinates, scrolled.
    func entryRect(_ i: Int) -> NSRect {
        if GEMAppsSettings.asText {
            return NSRect(x: content.minX - scroll.x, y: content.minY + 2 + CGFloat(i) * GEMChrome.rowH - scroll.y,
                          width: max(content.width, contentSize.width), height: GEMChrome.rowH)
        }
        return NSRect(x: content.minX + CGFloat(i % columns) * cellW - scroll.x, y: content.minY + 4 + CGFloat(i / columns) * cellH - scroll.y,
                      width: cellW, height: cellH)
    }

    private func clampScroll() {
        scroll.x = max(0, min(scroll.x, contentSize.width - content.width))
        scroll.y = max(0, min(scroll.y, contentSize.height - content.height))
    }

    /// The slider in a track: its length the visible share, its place the scrolled share.
    private func thumb(in track: NSRect, vertical: Bool) -> NSRect {
        let len = vertical ? track.height : track.width
        let total = vertical ? contentSize.height : contentSize.width
        let visible = vertical ? content.height : content.width
        let pos = vertical ? scroll.y : scroll.x
        let t = total <= visible ? len : max(g, (len * visible / total).rounded())
        let off = total <= visible ? 0 : ((len - t) * pos / (total - visible)).rounded()
        return vertical ? NSRect(x: track.minX, y: track.minY + off, width: track.width, height: t)
                        : NSRect(x: track.minX + off, y: track.minY, width: t, height: track.height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        let active = window?.isKeyWindow == true
        let ink: NSColor = active ? .black : .white

        gadget(closeBox); GEMChrome.bitmap(GEMChrome.closeMark, at: NSPoint(x: closeBox.midX - 3, y: closeBox.midY - 5), color: ink)
        gadget(fullBox); GEMChrome.bitmap(GEMChrome.fullMark, at: NSPoint(x: fullBox.midX - 3, y: fullBox.midY - 6), color: ink)
        gadget(titleBar)
        let title = "D:\\*.*"
        GEMChrome.text(title, at: NSPoint(x: (titleBar.midX - GEMChrome.textWidth(title) / 2).rounded(), y: titleBar.minY + 3), color: ink)

        NSColor.white.setFill(); infoLine.fill(); GEMChrome.outline(infoLine)
        let info = selectedApp.map { _ in "1 of \(apps.count) applications selected." } ?? "\(apps.count) applications."
        GEMChrome.text(info, at: NSPoint(x: infoLine.minX + 8, y: infoLine.minY + 1), color: active ? .black : GEMChrome.shade)

        NSColor.white.setFill(); contentBox.fill(); GEMChrome.outline(contentBox)
        NSGraphicsContext.current?.saveGraphicsState()
        content.clip()
        for i in apps.indices {
            let r = entryRect(i)
            guard r.intersects(content) else { continue }
            let sel = i == selected
            if GEMAppsSettings.asText {
                if sel { NSColor.black.setFill(); r.fill() }
                let name = apps[i].name.count > 30 ? String(apps[i].name.prefix(29)) + "…" : apps[i].name
                GEMChrome.text("  " + name.padding(toLength: 32, withPad: " ", startingAt: 0) + apps[i].location, at: r.origin, color: sel ? .white : .black)
            } else {
                GEMDesktopView.drawIcon(GEMApps.icon(bundleID: apps[i].bundleID, selected: sel), letter: nil, name: apps[i].name,
                                        icon: NSRect(x: r.minX + GEMChrome.iconInset, y: r.minY, width: 32, height: 32),
                                        labelBox: NSRect(x: r.minX, y: r.minY + 32, width: GEMChrome.labelW, height: GEMChrome.labelH), selected: sel)
            }
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        for (box, dir) in [(upBox, 0), (downBox, 1), (leftBox, 2), (rightBox, 3)] { gadget(box); arrow(box, dir, ink) }
        for (track, v) in [(vTrack, true), (hTrack, false)] {
            NSColor.white.setFill(); track.fill()
            GEMChrome.checker(track.insetBy(dx: 1, dy: 1), color: .black)
            GEMChrome.outline(track)
            gadget(thumb(in: track, vertical: v))
        }
        gadget(sizeBox)
        GEMChrome.bitmap(["#######", "#.....#", "#.....#", "#..####", "#..#..#", "#..#..#", "####..#"], at: NSPoint(x: sizeBox.midX - 4, y: sizeBox.midY - 4), color: ink)
    }

    private func gadget(_ r: NSRect) { GEMChrome.outline(r); GEMChrome.raised(r.insetBy(dx: 1, dy: 1)) }

    /// The hollow arrows of the scroll boxes: 0 up, 1 down, 2 left, 3 right.
    private func arrow(_ r: NSRect, _ dir: Int, _ ink: NSColor) {
        let up = ["...#...", "..#.#..", ".#...#.", "##...##", "..#.#..", "..#.#..", "..#.#..", "..###.."]
        var rows = up
        switch dir {
        case 1: rows = up.reversed()
        case 2, 3:
            rows = (0..<7).map { x in String((0..<8).map { y in Array(up[y])[x] }) }
            if dir == 3 { rows = rows.map { String($0.reversed()) } }
        default: break
        }
        let w = CGFloat(rows.first?.count ?? 0), h = CGFloat(rows.count)
        GEMChrome.bitmap(rows, at: NSPoint(x: (r.midX - w / 2).rounded(), y: (r.midY - h / 2).rounded()), color: ink)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if closeBox.contains(p) { GEMAppsWindowController.shared.close(); return }
        if fullBox.contains(p) { toggleFull(); return }
        if sizeBox.contains(p) { track(event) { [weak self] q, start, frame in self?.resize(from: frame, by: NSSize(width: q.x - start.x, height: q.y - start.y)) }; return }
        if titleBar.contains(p) { window?.performDrag(with: event); return }
        let step = GEMAppsSettings.asText ? GEMChrome.rowH : cellH
        if upBox.contains(p) { scrollBy(0, -step); return }
        if downBox.contains(p) { scrollBy(0, step); return }
        if leftBox.contains(p) { scrollBy(-cellW, 0); return }
        if rightBox.contains(p) { scrollBy(cellW, 0); return }
        for (trackRect, v) in [(vTrack, true), (hTrack, false)] where trackRect.contains(p) {
            let t = thumb(in: trackRect, vertical: v)
            if t.contains(p) { dragThumb(event, track: trackRect, vertical: v); return }
            let page = v ? content.height : content.width
            let before = v ? p.y < t.minY : p.x < t.minX
            if v { scrollBy(0, before ? -page : page) } else { scrollBy(before ? -page : page, 0) }
            return
        }
        guard content.contains(p) else { return }
        guard let i = apps.indices.first(where: { entryHit($0, p) }) else { selected = nil; return }
        selected = i
        if event.clickCount == 2 { GEMApps.open(apps[i]); return }
        dragOut(event, app: apps[i])
    }

    private func entryHit(_ i: Int, _ p: NSPoint) -> Bool {
        let r = entryRect(i)
        if GEMAppsSettings.asText { return r.contains(p) }
        return NSRect(x: r.minX + GEMChrome.iconInset, y: r.minY, width: 32, height: 32).contains(p)
            || NSRect(x: r.minX, y: r.minY + 32, width: GEMChrome.labelW, height: GEMChrome.labelH).contains(p)
    }

    /// Follows the pointer until the button comes up: `step(point in screen, start, window frame at start)`.
    private func track(_ event: NSEvent, _ step: (NSPoint, NSPoint, NSRect) -> Void) {
        guard let window else { return }
        let start = NSEvent.mouseLocation, frame = window.frame
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            step(NSEvent.mouseLocation, start, frame)
            if e.type == .leftMouseUp { break }
        }
    }

    private func resize(from frame: NSRect, by d: NSSize) {
        guard let window else { return }
        let w = max(window.minSize.width, frame.width + d.width), h = max(window.minSize.height, frame.height - d.height)
        window.setFrame(NSRect(x: frame.minX, y: frame.maxY - h, width: w, height: h), display: true)   // the top left stays
        relayout()
    }

    private func toggleFull() {
        guard let window, let screen = window.screen ?? NSScreen.screens.first else { return }
        if let saved = savedFrame { window.setFrame(saved, display: true); savedFrame = nil }
        else {
            savedFrame = window.frame
            let top = GEMDesktopController.barHeight(on: screen)
            window.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height - top), display: true)
        }
        relayout()
    }

    private func dragThumb(_ event: NSEvent, track: NSRect, vertical v: Bool) {
        let s0 = scroll
        let thumbLen = v ? thumb(in: track, vertical: true).height : thumb(in: track, vertical: false).width
        let room = (v ? track.height : track.width) - thumbLen
        let range = v ? contentSize.height - content.height : contentSize.width - content.width
        guard room > 0, range > 0 else { return }
        self.track(event) { [weak self] q, start, _ in
            guard let self else { return }
            let d = v ? start.y - q.y : q.x - start.x   // screen y grows upwards, the view's downwards
            if v { self.scroll.y = s0.y + d * range / room } else { self.scroll.x = s0.x + d * range / room }
            self.relayout()
        }
    }

    private func scrollBy(_ dx: CGFloat, _ dy: CGFloat) { scroll.x += dx; scroll.y += dy; relayout() }
    override func scrollWheel(with event: NSEvent) {
        scroll.x -= event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 10)
        scroll.y -= event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        relayout()
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); clampScroll() }

    /// Drags an app out as its file: onto the desktop it is installed as an icon (D2).
    private func dragOut(_ event: NSEvent, app: GEMApp) {
        guard let window else { return }
        let start = event.locationInWindow
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { return }
            if hypot(e.locationInWindow.x - start.x, e.locationInWindow.y - start.y) > 4 {
                let item = NSDraggingItem(pasteboardWriter: app.url as NSURL)
                let pic = GEMApps.icon(bundleID: app.bundleID, selected: true) ?? NSWorkspace.shared.icon(forFile: app.url.path)
                let p = convert(e.locationInWindow, from: nil)
                item.setDraggingFrame(NSRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32), contents: pic)
                beginDraggingSession(with: [item], event: e, source: self)
                return
            }
        }
    }

    // MARK: Keyboard: arrows, Return, type to jump

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { GEMAppsWindowController.shared.close(); return }
        let cols = GEMAppsSettings.asText ? 1 : columns
        switch event.keyCode {
        case 36, 76: if let a = selectedApp { GEMApps.open(a) }; return
        case 125: move(cols); return
        case 126: move(-cols); return
        case 124: move(GEMAppsSettings.asText ? 0 : 1); return
        case 123: move(GEMAppsSettings.asText ? 0 : -1); return
        default: break
        }
        guard let chars = event.characters, !chars.isEmpty, !event.modifierFlags.contains(.command) else { super.keyDown(with: event); return }
        if Date().timeIntervalSince(typedAt) > 1 { typed = "" }
        typed += chars; typedAt = Date()
        if let i = apps.firstIndex(where: { $0.name.lowercased().hasPrefix(typed.lowercased()) }) { selected = i; reveal(i) }
    }

    private func move(_ by: Int) {
        guard !apps.isEmpty else { return }
        let i = min(apps.count - 1, max(0, (selected ?? -by.signum()) + by))
        selected = i
        reveal(i)
    }

    private func reveal(_ i: Int) {
        let r = entryRect(i)
        if r.minY < content.minY { scroll.y -= content.minY - r.minY }
        if r.maxY > content.maxY { scroll.y += r.maxY - content.maxY }
        if !GEMAppsSettings.asText {
            if r.minX < content.minX { scroll.x -= content.minX - r.minX }
            if r.maxX > content.maxX { scroll.x += r.maxX - content.maxX }
        }
        relayout()
    }

    // MARK: VoiceOver

    private var axParts: [AccessibleHotspot] = []
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        var parts = [AccessibleHotspot.make(in: self, label: "Close", rect: closeBox) { GEMAppsWindowController.shared.close() },
                     AccessibleHotspot.make(in: self, label: "Full size", rect: fullBox) { [weak self] in self?.toggleFull() },
                     AccessibleHotspot.make(in: self, label: "Scroll up", rect: upBox) { [weak self] in self?.scrollBy(0, -(self?.content.height ?? 0)) },
                     AccessibleHotspot.make(in: self, label: "Scroll down", rect: downBox) { [weak self] in self?.scrollBy(0, self?.content.height ?? 0) }]
        for i in apps.indices where entryRect(i).intersects(content) {
            let app = apps[i]
            parts.append(AccessibleHotspot.make(in: self, label: app.name, rect: entryRect(i).intersection(content)) { GEMApps.open(app) })
        }
        axParts = parts
        return parts
    }
}

extension GEMAppsView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.link, .delete] : [.copy, .link]
    }
}
