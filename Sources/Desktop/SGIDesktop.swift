import AppKit

// MARK: - SGI / IRIX 4Dwm chrome

enum SGIChrome {
    static let face       = NSColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1)   // Indigo Magic gray
    static let light      = NSColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1)
    static let dark       = NSColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
    static let black      = NSColor.black
    static let activeTitle   = NSColor(red: 0.25, green: 0.41, blue: 0.61, alpha: 1) // SGI blue
    static let inactiveTitle = NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
    static let titleText  = NSColor.white

    static func font(size: CGFloat, bold: Bool = false) -> NSFont {
        bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    }

    /// Raised bevel: light top-left, dark bottom-right (thicker, more rounded SGI look).
    static func drawRaised(_ r: NSRect, t: CGFloat = 2) {
        light.setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        dark.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
        if t >= 2 {
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 1).fill()
            NSRect(x: r.minX + 1, y: r.minY + 1, width: 1, height: r.height - 2).fill()
            black.withAlphaComponent(0.4).setFill()
            NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: 1).fill()
            NSRect(x: r.maxX - 2, y: r.minY + 1, width: 1, height: r.height - 2).fill()
        }
    }

    static func drawText(_ s: String, in rect: NSRect, size: CGFloat, color: NSColor, centered: Bool = false) {
        let st = NSMutableParagraphStyle(); st.alignment = centered ? .center : .left; st.lineBreakMode = .byTruncatingTail
        let a = NSAttributedString(string: s, attributes: [.font: font(size: size, bold: true), .foregroundColor: color, .paragraphStyle: st])
        let h = a.size().height
        a.draw(in: NSRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h))
    }
}

// MARK: - Controller

final class SGIDesktopController {
    static let shared = SGIDesktopController()
    private var window: NSPanel?
    private var desktopView: SGIDesktopView?
    private init() {}

    func update() {
        // Note: for SGI IRIX the desktop IS the dock (dockStyle "none" → no DockView),
        // so it must show even in dock-only mode — not gated on dockOnly.
        guard let theme = ThemeManager.shared.activeTheme,
              let cfg = theme.config.sgiDesktop else { hide(); return }
        show(cfg: cfg, theme: theme)
    }

    func hide() {
        window?.orderOut(nil); window = nil; desktopView = nil
    }

    private func show(cfg: DockThemeConfig.SGIDesktopConfig, theme: ThemeBundle) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        if window == nil {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = false
            panel.contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
            self.window = panel
        }
        guard let content = window?.contentView else { return }
        window?.setFrame(frame, display: false)
        content.frame = NSRect(origin: .zero, size: frame.size)
        desktopView?.removeFromSuperview()
        let dv = SGIDesktopView(cfg: cfg, theme: theme, frame: content.bounds)
        dv.autoresizingMask = [.width, .height]
        content.addSubview(dv)
        desktopView = dv
        window?.orderFront(nil)
    }
}

// MARK: - Desktop view (Toolchest + Icon Catalog windows + Shelf)

final class SGIDesktopView: NSView {
    private let cfg: DockThemeConfig.SGIDesktopConfig
    private let theme: ThemeBundle
    private var toolchestRect = NSRect(x: 6, y: 0, width: 96, height: 24)
    private var catalogWindows: [SGIWindowView] = []
    private var shelfItems: [ProgramItemView] = []

    init(cfg: DockThemeConfig.SGIDesktopConfig, theme: ThemeBundle, frame: NSRect) {
        self.cfg = cfg; self.theme = theme
        super.init(frame: frame)
        buildCatalog()
        buildShelf()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }

    private func buildCatalog() {
        var x: CGFloat = 60, top: CGFloat = 60
        for (i, group) in cfg.iconCatalog.enumerated() {
            let w = CGFloat(group.width ?? 360), h = CGFloat(group.height ?? 260)
            let y = bounds.height - top - h - CGFloat(i) * 30
            let win = SGIWindowView(group: group, theme: theme,
                                    frame: NSRect(x: x + CGFloat(i) * 30, y: max(40, y), width: w, height: h))
            win.onClose = { [weak win] in win?.isHidden = true }
            win.onMinimizeRequested = { [weak self, weak win] in self?.minimize(win) }
            addSubview(win); catalogWindows.append(win)
        }
    }

    private func buildShelf() {
        // Shelf icons run down the right edge of the desktop
        let cellW = ProgramItemView.cellWidth, cellH = ProgramItemView.cellHeight
        var y = bounds.height - cellH - 16
        for entry in cfg.shelf {
            let img = loadIcon(entry)
            let iv = ProgramItemView(entry: entry, image: img)
            iv.frame = NSRect(x: bounds.width - cellW - 16, y: y, width: cellW, height: cellH)
            iv.autoresizingMask = [.minXMargin, .maxYMargin]
            addSubview(iv); shelfItems.append(iv)
            y -= cellH + 6
        }
    }

    private func loadIcon(_ e: DockThemeConfig.DesktopIconEntry) -> NSImage? {
        let url = theme.iconsDirectory.appendingPathComponent(e.icon)
        if let img = NSImage(contentsOf: url) { return img }
        if e.type == "app", let bid = e.bundleID { return ThemeManager.shared.icon(for: bid, size: 48) }
        return nil
    }

    private var minReps: [SGIMinRep] = []

    private func minimize(_ win: SGIWindowView?) {
        guard let win = win else { return }
        win.isHidden = true
        let rep = SGIMinRep(title: win.group.name)
        rep.onRestore = { [weak self, weak win, weak rep] in
            win?.isHidden = false
            if let w = win { self?.superview?.addSubview(w) ; self?.addSubview(w) }
            if let r = rep { self?.minReps.removeAll { $0 === r }; r.removeFromSuperview() }
            self?.layoutMinReps()
        }
        addSubview(rep); minReps.append(rep)
        layoutMinReps()
    }

    private func layoutMinReps() {
        var x: CGFloat = 120
        for rep in minReps {
            rep.frame = NSRect(x: x, y: 8, width: 124, height: 26)
            x += 132
        }
    }

    // MARK: Toolchest

    override func draw(_ dirtyRect: NSRect) {
        // Toolchest button anchored top-left
        toolchestRect = NSRect(x: 6, y: bounds.height - 28, width: 100, height: 24)
        SGIChrome.face.setFill(); toolchestRect.fill()
        SGIChrome.drawRaised(toolchestRect, t: 2)
        SGIChrome.drawText("  Toolchest", in: toolchestRect, size: 12, color: .white)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard toolchestRect.contains(p) else { return }
        let items = cfg.toolchest.map { toMenuItem($0) }
        Win31Menu.present(items: items, topLeft: NSPoint(x: toolchestRect.minX, y: toolchestRect.minY),
                          in: self, style: .sgi, header: "Desk 1")
    }

    /// Recursively convert a Toolchest config entry to a retro menu item (with submenus).
    private func toMenuItem(_ e: DockThemeConfig.ToolchestEntry) -> Win31MenuItem {
        if let sub = e.submenu, !sub.isEmpty {
            return Win31MenuItem(e.title, submenu: sub.map { toMenuItem($0) })
        }
        if e.title == "Icon Catalog" {
            return Win31MenuItem(e.title) { [weak self] in self?.reopenCatalog() }
        }
        if let it = e.item {
            return Win31MenuItem(e.title) { DesktopLauncher.launch(it) }
        }
        return Win31MenuItem(e.title)
    }

    private func reopenCatalog() {
        for w in catalogWindows { w.isHidden = false; superview?.addSubview(w) }
    }
}

/// A minimized SGI window represented as a small rectangle on the desktop.
final class SGIMinRep: NSView {
    private let title: String
    var onRestore: (() -> Void)?
    init(title: String) { self.title = title; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        SGIChrome.face.setFill(); bounds.fill()
        SGIChrome.drawRaised(bounds, t: 2)
        SGIChrome.drawText(title, in: bounds.insetBy(dx: 6, dy: 0), size: 11, color: .black)
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { onRestore?() }
    }
}
