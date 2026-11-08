import AppKit
import CoreImage

/// Lion and Mountain Lion's Launchpad, for a theme whose dock has the Launchpad tile: the
/// desktop picture fades in blurred over the whole screen, a search field at the top, the apps
/// in a grid of large icons, pages with dots under them, the dock left on top. Measured off a
/// Mountain Lion screenshot: 8 columns of 11.6 % of the width, 5 rows of 15 % of the height,
/// icons 5.4 % of the width (Safari's compass, 88 % of its icon, measured 4.7 %) or 8.7 % of the
/// height, whichever is smaller — on a 16:9 screen the width alone made them too big.
/// Apps in a folder of the Applications folders (Utilities) are in the grid like the others;
/// Launchpad's own folders, which held them on Lion, are not built yet. Drag an icon to move it,
/// to a screen edge to take it to the next page; the order is kept, new apps go to the end.
final class LaunchpadController: NSObject, NSSearchFieldDelegate {
    static let shared = LaunchpadController()

    struct App {
        let name: String; let url: URL; let bundleID: String?
        /// What the saved order remembers it by.
        var key: String { bundleID ?? url.path }
    }

    static let columns = 8, rows = 5
    static var perPage: Int { columns * rows }

    private var panel: LaunchpadPanel?
    private var view: LaunchpadView?
    private var cameFrom: NSRunningApplication?
    private var apps: [App] = []
    private var shown: [App] = []
    private var page = 0
    /// The icon the arrow keys are on, counted on the page shown.
    private var selected: Int?
    var isSearching: Bool { !(view?.search.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }

    var isOpen: Bool { panel != nil }
    func toggle() { isOpen ? close() : open() }

    func open() {
        guard panel == nil, let screen = NSScreen.main else { return }
        apps = Self.arranged(Self.installedApps(), order: UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? [])
        shown = apps
        page = 0
        selected = nil
        if !NSApp.isActive { cameFrom = NSWorkspace.shared.frontmostApplication }

        let p = LaunchpadPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: DockWindow.defaultLevel)   // over the menu bar, the dock raised above it
        p.isOpaque = false
        p.backgroundColor = .black
        p.hasShadow = false
        p.title = "Launchpad"
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.onCancel = { [weak self] in self?.close() }
        let v = LaunchpadView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: self)
        v.setBackground(Self.blurredDesktop(for: screen))
        p.contentView = v
        panel = p; view = v
        reload()

        p.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(v.search)
        DockController.shared.raiseWindow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }
        MenuKeyboard.announce("Launchpad, \(apps.count) apps. Type to search, Escape closes.")
    }

    /// Fades out. `launched`: an app is coming to the front, so the one before does not.
    func close(launched: Bool = false) {
        guard let p = panel else { return }
        panel = nil; view = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
        })
        if !launched, let back = cameFrom, !back.isTerminated { back.activate() }
        cameFrom = nil
    }

    func launch(_ app: App) {
        close(launched: true)
        if let id = app.bundleID, NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil {
            AppLauncher.launchOrActivate(bundleID: id)
        } else {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Search and pages

    func controlTextDidChange(_ note: Notification) {
        let q = view?.search.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        shown = q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
        page = 0
        // Typing marks the first match, which Return then opens.
        selected = q.isEmpty || shown.isEmpty ? nil : 0
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            if let s = selected, shown.indices.contains(page * Self.perPage + s) { launch(shown[page * Self.perPage + s]) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if textView.string.isEmpty { close(); return true }
            return false   // the field clears itself first
        // Left and right move the cursor while there is text to move it in.
        case #selector(NSResponder.moveLeft(_:)) where textView.string.isEmpty:
            step(-1); return true
        case #selector(NSResponder.moveRight(_:)) where textView.string.isEmpty:
            step(1); return true
        case #selector(NSResponder.moveUp(_:)):
            step(-Self.columns); return true
        case #selector(NSResponder.moveDown(_:)):
            step(Self.columns); return true
        default:
            return false
        }
    }

    private var onPage: Int { max(0, min(Self.perPage, shown.count - page * Self.perPage)) }

    /// The arrows: the first press marks the first icon; left and right run on over the page
    /// edge to the next page, up and down stop at the top and bottom row.
    private func step(_ delta: Int) {
        guard onPage > 0 else { return }
        guard let s = selected else { select(0); return }
        let next = s + delta
        if abs(delta) == 1, next < 0 || next >= onPage {
            let target = page + delta
            guard target >= 0, target < pageCount else { return }
            page = target
            reload()
            select(delta > 0 ? 0 : onPage - 1)
            return
        }
        guard next >= 0, next < onPage else { return }
        select(next)
    }

    private func select(_ i: Int?) {
        selected = i
        view?.highlight(i)
        if let i, shown.indices.contains(page * Self.perPage + i) {
            MenuKeyboard.announce(shown[page * Self.perPage + i].name)
        }
    }

    var pageCount: Int { max(1, (shown.count + Self.perPage - 1) / Self.perPage) }

    func turn(by delta: Int) { show(page: page + delta) }

    func show(page p: Int) {
        let target = min(max(p, 0), pageCount - 1)
        guard target != page else { return }
        page = target
        selected = nil
        reload()
        MenuKeyboard.announce("Page \(page + 1) of \(pageCount)")
    }

    private func reload() {
        let start = page * Self.perPage
        view?.show(Array(shown.dropFirst(start).prefix(Self.perPage)), page: page, of: pageCount)
        view?.highlight(selected)
    }

    // MARK: Arranging

    static let orderKey = "launchpadOrder"

    /// The saved order first; anything installed since goes to the end, by name.
    static func arranged(_ apps: [App], order: [String]) -> [App] {
        let byKey = Dictionary(apps.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let placed = Set(order)
        return order.compactMap { byKey[$0] } + apps.filter { !placed.contains($0.key) }
    }

    /// Moves `app` to `index` of the whole list (not the page) and keeps the order.
    func move(_ app: App, to index: Int) {
        guard !isSearching, let from = apps.firstIndex(where: { $0.key == app.key }) else { return }
        let a = apps.remove(at: from)
        apps.insert(a, at: min(max(index, 0), apps.count))
        shown = apps
        UserDefaults.standard.set(apps.map(\.key), forKey: Self.orderKey)
    }

    /// Dropped on slot `slot` of the page shown.
    func drop(_ app: App, at slot: Int) {
        move(app, to: page * Self.perPage + slot)
        selected = nil
        reload()
    }

    /// Held at a screen edge while dragged: the app goes to the first slot of the next page or the
    /// last of the one before, and that page comes up. False when there is no page that way.
    func carry(_ app: App, by delta: Int) -> Bool {
        let target = page + delta
        guard target >= 0, target < pageCount else { return false }
        move(app, to: delta > 0 ? target * Self.perPage : page * Self.perPage - 1)
        page = target
        selected = nil
        reload()
        MenuKeyboard.announce("Page \(page + 1) of \(pageCount)")
        return true
    }

    // MARK: Apps and picture

    static func installedApps(in dirs: [String] = ["/Applications", "/System/Applications",
                                                   NSHomeDirectory() + "/Applications"]) -> [App] {
        let fm = FileManager.default
        var seen = Set<String>(), out: [App] = []
        func add(_ url: URL) {
            let id = Bundle(url: url)?.bundleIdentifier
            guard seen.insert(id ?? url.path).inserted, id != "com.apple.apps.launcher" else { return }   // not itself
            out.append(App(name: fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                           url: url, bundleID: id))
        }
        for dir in dirs {
            let base = URL(fileURLWithPath: dir)
            for item in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !item.hasPrefix(".") {
                let url = base.appendingPathComponent(item)
                if item.hasSuffix(".app") { add(url); continue }
                // One folder down, where Utilities and many vendors' apps live; no deeper, where
                // installers keep helpers nobody opens from Launchpad.
                guard StackOptions.isFolder(url) else { continue }
                for sub in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] where sub.hasSuffix(".app") {
                    add(url.appendingPathComponent(sub))
                }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The desktop picture, blurred, as Launchpad laid it under the icons.
    static func blurredDesktop(for screen: NSScreen) -> CGImage? {
        NSWorkspace.shared.desktopImageURL(for: screen).flatMap(blurred)
    }

    static func blurred(_ url: URL) -> CGImage? {
        guard let input = CIImage(contentsOf: url) else { return nil }
        let radius = max(input.extent.width, input.extent.height) / 60
        let out = input.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.02, kCIInputSaturationKey: 0.9])
            .cropped(to: input.extent)
        return CIContext().createCGImage(out, from: input.extent)
    }

    static func icon(for app: App, size: CGFloat) -> NSImage {
        let img = (app.bundleID.map { ThemeManager.shared.icon(for: $0, size: size) }
                   ?? NSWorkspace.shared.icon(forFile: app.url.path)).copy() as! NSImage
        img.size = NSSize(width: size, height: size)
        return img
    }
}

final class LaunchpadPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// The picture, the search field, the grid and the dots.
final class LaunchpadView: NSView {
    private weak var controller: LaunchpadController?
    private let background = CALayer()
    let search = NSSearchField()
    let grid = FlippedGrid()
    private let dots = LaunchpadDots()
    private var scrolled: CGFloat = 0

    override var isFlipped: Bool { true }

    init(frame: NSRect, controller: LaunchpadController) {
        self.controller = controller
        super.init(frame: frame)
        wantsLayer = true
        background.contentsGravity = .resizeAspectFill
        background.frame = bounds
        layer?.addSublayer(background)

        let w = bounds.width, h = bounds.height
        search.frame = NSRect(x: (w - w * 0.17) / 2, y: h * 0.045 - 11, width: w * 0.17, height: 22)
        search.placeholderString = ""
        search.focusRingType = .none
        search.appearance = NSAppearance(named: .darkAqua)
        search.delegate = controller
        search.setAccessibilityLabel("Search Launchpad")
        addSubview(search)

        grid.frame = bounds
        addSubview(grid)

        dots.frame = NSRect(x: 0, y: h * 0.845 - 8, width: w, height: 16)
        dots.onPick = { [weak controller] i in controller?.show(page: i) }
        addSubview(dots)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBackground(_ image: CGImage?) {
        background.contents = image
        background.backgroundColor = NSColor(srgbRed: 0.1, green: 0.15, blue: 0.25, alpha: 1).cgColor
    }

    private var iconSize: CGFloat { min(bounds.width * 0.054, bounds.height * 0.087).rounded() }
    private var labelSize: CGFloat { max(11, (bounds.height * 0.0135).rounded()) }

    /// Slot `i` of a page, in the grid's flipped coordinates.
    private func cellFrame(_ i: Int) -> NSRect {
        let w = bounds.width, h = bounds.height
        let pitchX = w * 0.116, pitchY = h * 0.15
        let col = i % LaunchpadController.columns, row = i / LaunchpadController.columns
        let cx = w / 2 + (CGFloat(col) - CGFloat(LaunchpadController.columns - 1) / 2) * pitchX
        let cy = h * 0.135 + CGFloat(row) * pitchY
        return NSRect(x: cx - pitchX / 2, y: cy - iconSize / 2 - 4, width: pitchX, height: iconSize + labelSize + 14)
    }

    func show(_ apps: [LaunchpadController.App], page: Int, of pages: Int) {
        grid.subviews.forEach { $0.removeFromSuperview() }
        let icon = iconSize, label = labelSize
        for (i, app) in apps.enumerated() {
            let b = LaunchpadIcon(frame: cellFrame(i))
            b.onPress = { [weak self, weak b] event in if let self, let b { self.track(b, event) } }
            b.isBordered = false
            b.imagePosition = .imageAbove
            b.image = LaunchpadController.icon(for: app, size: icon)
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
            shadow.shadowBlurRadius = 2; shadow.shadowOffset = NSSize(width: 0, height: -1)
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
            b.attributedTitle = NSAttributedString(string: app.name, attributes: [
                .font: NSFont.systemFont(ofSize: label, weight: .medium), .foregroundColor: NSColor.white,
                .shadow: shadow, .paragraphStyle: para])
            b.target = self
            b.action = #selector(pick(_:))
            b.tag = i
            b.setAccessibilityLabel(app.name)
            grid.addSubview(b)
        }
        current = apps
        dots.set(count: pages, current: page)
    }

    private var current: [LaunchpadController.App] = []
    @objc private func pick(_ sender: NSButton) {
        guard current.indices.contains(sender.tag) else { return }
        controller?.launch(current[sender.tag])
    }

    /// The arrow keys' mark: a soft light plate behind the icon.
    func highlight(_ index: Int?) {
        for case let b as LaunchpadIcon in grid.subviews {
            b.wantsLayer = true
            b.layer?.cornerRadius = 10
            b.layer?.backgroundColor = b.tag == index ? NSColor.white.withAlphaComponent(0.22).cgColor : nil
        }
    }

    /// A click opens the app; pressed and moved, the icon follows the pointer, the others make
    /// room, and it lands where it is let go. Held at the left or right edge it changes page.
    func track(_ icon: LaunchpadIcon, _ down: NSEvent) {
        guard let win = window, current.indices.contains(icon.tag) else { return }
        let app = current[icon.tag]
        let start = grid.convert(down.locationInWindow, from: nil)
        var dragged = icon, offset = NSPoint.zero, lifted = false, slot = icon.tag
        var edgeSince: Date?
        NSEvent.startPeriodicEvents(afterDelay: 0.1, withPeriod: 0.1)
        defer { NSEvent.stopPeriodicEvents() }

        func lift(_ b: LaunchpadIcon, at p: NSPoint) {
            dragged = b
            offset = NSPoint(x: p.x - b.frame.midX, y: p.y - b.frame.midY)
            grid.addSubview(b, positioned: .above, relativeTo: nil)
            b.alphaValue = 0.85
        }
        var last = start
        while let e = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .periodic]) {
            if e.type != .periodic { last = grid.convert(e.locationInWindow, from: nil) }
            if e.type == .leftMouseUp { break }
            if !lifted {
                guard hypot(last.x - start.x, last.y - start.y) > 6, controller?.isSearching == false else { continue }
                lifted = true
                lift(icon, at: start)
            }
            dragged.setFrameOrigin(NSPoint(x: last.x - offset.x - dragged.frame.width / 2,
                                           y: last.y - offset.y - dragged.frame.height / 2))
            // Make room: the others close up around the slot under the pointer.
            let target = (0..<current.count).min { a, b in
                let fa = cellFrame(a), fb = cellFrame(b)
                return hypot(fa.midX - last.x, fa.midY - last.y) < hypot(fb.midX - last.x, fb.midY - last.y)
            } ?? slot
            if target != slot {
                slot = target
                var order = current.indices.filter { $0 != dragged.tag }
                order.insert(dragged.tag, at: min(slot, order.count))
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    for case let b as LaunchpadIcon in grid.subviews where b !== dragged {
                        if let pos = order.firstIndex(of: b.tag) { b.animator().frame = cellFrame(pos) }
                    }
                }
            }
            // At an edge for a moment: over to the next page, still carrying it.
            let edge = last.x < bounds.width * 0.03 ? -1 : last.x > bounds.width * 0.97 ? 1 : 0
            if edge == 0 { edgeSince = nil; continue }
            if edgeSince == nil { edgeSince = Date(); continue }
            guard Date().timeIntervalSince(edgeSince!) > 0.6 else { continue }
            edgeSince = nil
            guard controller?.carry(app, by: edge) == true,
                  let i = current.firstIndex(where: { $0.key == app.key }),
                  let b = grid.subviews.compactMap({ $0 as? LaunchpadIcon }).first(where: { $0.tag == i }) else { continue }
            slot = i
            offset = .zero
            lift(b, at: NSPoint(x: b.frame.midX, y: b.frame.midY))
        }
        if lifted { controller?.drop(app, at: slot) } else { pick(icon) }
    }

    /// A click on the picture, not on an app, closes it, as on the real thing.
    override func mouseDown(with event: NSEvent) { controller?.close() }

    /// Two-finger swipes and the wheel turn the page.
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == [] && event.momentumPhase == [] { scrolled = 0 }
        guard event.momentumPhase == [] else { return }
        scrolled += abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : event.scrollingDeltaY
        if abs(scrolled) > 40 {
            controller?.turn(by: scrolled > 0 ? 1 : -1)
            scrolled = 0
        }
    }
}

/// One app in the grid. A press goes to the view, which tells a click from a drag; VoiceOver's
/// press still goes through the button's action.
final class LaunchpadIcon: NSButton {
    var onPress: ((NSEvent) -> Void)?
    override func mouseDown(with event: NSEvent) { onPress?(event) }
}

/// The grid counts its rows from the top, as the picture does.
final class FlippedGrid: NSView { override var isFlipped: Bool { true } }

/// The page dots under the grid; the current one white, the others dim. A click goes there.
final class LaunchpadDots: NSView {
    var onPick: ((Int) -> Void)?
    private var count = 1, current = 0
    private let size: CGFloat = 7, gap: CGFloat = 9

    func set(count: Int, current: Int) {
        self.count = count; self.current = current
        isHidden = count < 2
        needsDisplay = true
        setAccessibilityLabel("Page \(current + 1) of \(count)")
    }

    private func dotRect(_ i: Int) -> NSRect {
        let total = CGFloat(count) * size + CGFloat(count - 1) * gap
        return NSRect(x: (bounds.width - total) / 2 + CGFloat(i) * (size + gap), y: (bounds.height - size) / 2, width: size, height: size)
    }

    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<count {
            (i == current ? NSColor.white : NSColor.white.withAlphaComponent(0.35)).setFill()
            NSBezierPath(ovalIn: dotRect(i)).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = (0..<count).first(where: { dotRect($0).insetBy(dx: -4, dy: -6).contains(p) }) { onPick?(i) }
    }
}
