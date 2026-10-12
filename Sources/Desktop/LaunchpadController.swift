import AppKit
import CoreImage

/// Lion and Mountain Lion's Launchpad, for a theme whose dock has the Launchpad tile: the
/// desktop picture fades in blurred over the whole screen, a search field at the top, the apps
/// in a grid of large icons, pages with dots under them, the dock left on top. Measured off a
/// Mountain Lion screenshot: 8 columns of 11.6 % of the width, 5 rows of 15 % of the height,
/// icons 5.4 % of the width (Safari's compass, 88 % of its icon, measured 4.7 %) or 8.7 % of the
/// height, whichever is smaller — on a 16:9 screen the width alone made them too big.
/// ponytail: top-level apps only (no Utilities folder, no folders of your own, no drag to
/// rearrange); add them if anyone misses them.
final class LaunchpadController: NSObject, NSSearchFieldDelegate {
    static let shared = LaunchpadController()

    struct App { let name: String; let url: URL; let bundleID: String? }

    static let columns = 8, rows = 5
    static var perPage: Int { columns * rows }

    private var panel: LaunchpadPanel?
    private var view: LaunchpadView?
    private var cameFrom: NSRunningApplication?
    private var apps: [App] = []
    private var shown: [App] = []
    private var page = 0

    var isOpen: Bool { panel != nil }
    func toggle() { isOpen ? close() : open() }

    func open() {
        guard panel == nil, let screen = NSScreen.main else { return }
        apps = Self.installedApps()
        shown = apps
        page = 0
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
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            if let first = shown.first { launch(first) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if textView.string.isEmpty { close(); return true }
            return false   // the field clears itself first
        case #selector(NSResponder.moveLeft(_:)) where textView.string.isEmpty:
            turn(by: -1); return true
        case #selector(NSResponder.moveRight(_:)) where textView.string.isEmpty:
            turn(by: 1); return true
        default:
            return false
        }
    }

    var pageCount: Int { max(1, (shown.count + Self.perPage - 1) / Self.perPage) }

    func turn(by delta: Int) { show(page: page + delta) }

    func show(page p: Int) {
        let target = min(max(p, 0), pageCount - 1)
        guard target != page else { return }
        page = target
        reload()
        MenuKeyboard.announce("Page \(page + 1) of \(pageCount)")
    }

    private func reload() {
        let start = page * Self.perPage
        view?.show(Array(shown.dropFirst(start).prefix(Self.perPage)), page: page, of: pageCount)
    }

    // MARK: Apps and picture

    static func installedApps() -> [App] {
        let dirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        let fm = FileManager.default
        var seen = Set<String>(), out: [App] = []
        for dir in dirs {
            for item in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
                let id = Bundle(url: url)?.bundleIdentifier
                guard seen.insert(id ?? url.path).inserted, id != "com.apple.apps.launcher" else { continue }   // not itself
                out.append(App(name: fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                               url: url, bundleID: id))
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

    func show(_ apps: [LaunchpadController.App], page: Int, of pages: Int) {
        grid.subviews.forEach { $0.removeFromSuperview() }
        let w = bounds.width, h = bounds.height
        let pitchX = w * 0.116, pitchY = h * 0.15, icon = min(w * 0.054, h * 0.087).rounded()
        let label = max(11, (h * 0.0135).rounded())
        for (i, app) in apps.enumerated() {
            let col = i % LaunchpadController.columns, row = i / LaunchpadController.columns
            let cx = w / 2 + (CGFloat(col) - CGFloat(LaunchpadController.columns - 1) / 2) * pitchX
            let cy = h * 0.135 + CGFloat(row) * pitchY
            let b = NSButton(frame: NSRect(x: cx - pitchX / 2, y: cy - icon / 2 - 4, width: pitchX, height: icon + label + 14))
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
