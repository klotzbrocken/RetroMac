import AppKit

/// The NeXTSTEP Dock: a fixed, CURATED column of tiles pinned to the right screen edge — the
/// authentic NeXT look (Workspace mark, a live clock/calendar tile, a few app tiles, and the
/// Recycler pinned at the very bottom). Unlike RetroMac's normal DockView this is NOT a launcher
/// for the user's running apps (the NeXT theme sets `hidesDock`, so DockView is suppressed); it is
/// its own desktop-level panel, mirroring `NextMenuController`. Tiles are drawn with `NeXTChrome`
/// so the dock matches the menu and window chrome pixel-for-pixel.
final class NextDockController {

    static let shared = NextDockController()
    private var window: NSPanel?
    private var view: NextDockView?
    private init() {}

    func update() {
        guard let theme = ThemeManager.shared.activeTheme, theme.config.isNextStep else { hide(); return }
        show(theme: theme)
    }

    func hide() {
        NextAppsWindowController.shared.close()
        view?.stop()
        window?.orderOut(nil)
        window = nil
        view = nil
    }

    private func show(theme: ThemeBundle) {
        let firstShow = (window == nil)
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: NextDockView.width, height: 400),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: 5)   // NeXT app-icon tier
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            window = panel
        }
        let v = NextDockView(theme: theme)
        window?.contentView = v
        view = v
        reposition()
        window?.orderFront(nil)
        v.start()
        // On NeXTSTEP the Workspace File Viewer was always present — it opened at login and stayed
        // up. Mirror that: when the theme first activates, bring up the File Viewer once (the user
        // can still close it). Only on first show, so a later theme refresh doesn't steal focus.
        if firstShow { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NextAppsWindowController.shared.show() } }
    }

    private func reposition() {
        guard let window = window, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        // Full-height strip flush to the right edge.
        window.setFrame(NSRect(x: f.maxX - NextDockView.width, y: f.minY, width: NextDockView.width, height: f.height), display: true)
        view?.frame = NSRect(x: 0, y: 0, width: NextDockView.width, height: f.height)
        view?.needsDisplay = true
    }
}

// MARK: - View

final class NextDockView: NSView {
    static let width: CGFloat = 68
    private let tile: CGFloat = 64
    private let clockH: CGFloat = 96

    private let theme: ThemeBundle
    private var clockTimer: Timer?

    /// A curated tile. Every cell is painted on the silver NeXT dock tile; the icon art is then
    /// composited on top (edge-to-edge for shipped NeXT art, inset for custom images).
    /// `isClock` draws the live clock/calendar instead of an icon.
    private struct Tile {
        let icon: String?          // theme icon file; nil = clock tile
        var isClock: Bool = false
        var dots: Bool = false     // NeXT "…" mark shown on a docked app that isn't running
        let action: (() -> Void)?
        var rect: NSRect = .zero
    }
    private var tiles: [Tile] = []

    init(theme: ThemeBundle) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: NextDockView.width, height: 400))
        wantsLayer = true
        buildTiles()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }   // y-up; recycler pinned to the bottom

    private func openHome() { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory())) }
    private func openTrash() { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")) }

    private func buildTiles() {
        // Curated NeXT column (top→down). The nx_* icons are the authentic "Fleet" tiles that
        // already carry the grey bevel, so they are composited edge-to-edge on the silver cell.
        tiles = [
            Tile(icon: "nx_workspace.png", action: { NextAppsWindowController.shared.toggle() }),   // NeXT cube → File Viewer
            Tile(icon: nil, isClock: true, action: { ClockWidgetController.shared.show() }),  // Clock widget
            Tile(icon: "nx_media.png", action: { CPUMonitorController.shared.show() }),             // Processor Monitor widget
            Tile(icon: "nx_edit.png", action: { NotepadController.shared.show() }),                 // Notepad widget
            Tile(icon: "nx_home.png", action: { [weak self] in self?.openHome() }),
            Tile(icon: "nx_mail.png", dots: true, action: nil),
            Tile(icon: "nx_librarian.png", dots: true, action: nil),
        ]
    }

    func start() {
        stop()
        // Update the clock tile every 10s (minute display + date is plenty).
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.redrawClock() }
        RunLoop.main.add(t, forMode: .common)
        clockTimer = t
    }
    func stop() { clockTimer?.invalidate(); clockTimer = nil }
    private func redrawClock() { needsDisplay = true }

    // MARK: Layout

    /// Assign rects: main tiles stacked from the TOP, recycler pinned to the BOTTOM.
    private func layoutTiles() {
        var y = bounds.maxY - 4
        for i in tiles.indices {
            let h = tiles[i].isClock ? clockH : tile
            y -= h
            tiles[i].rect = NSRect(x: (bounds.width - tile) / 2, y: y, width: tile, height: h)
            y -= 2   // thin desktop gap between tiles
        }
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        layoutTiles()
        for t in tiles { drawTile(t, in: ctx) }
        drawRecycler(in: ctx)
    }

    private func drawTile(_ t: Tile, in ctx: CGContext) {
        // Every dock cell ALWAYS gets the silver NeXT tile as its background (as in the original).
        NeXTChrome.dockTile(t.rect, flipped: false, in: ctx)
        if t.isClock { drawClock(in: t.rect, ctx: ctx); return }
        guard let name = t.icon else { return }   // silver tile only
        // A user "Change Icon…" override (per tile icon name) wins over the shipped art.
        let overridePath = Self.iconOverride(name)
        let img = overridePath.flatMap { NSImage(contentsOfFile: $0) }
            ?? theme.iconResource(name).flatMap { NSImage(contentsOf: $0) }
        guard let img else { return }
        // Curated bundled nx_* art is a full silver tile (edge-to-edge). A "Change Icon…" pick
        // fills the whole cell when "Ganze Fläche füllen" was set (full-tile Fleet art), else it
        // sits inset on the silver tile (a motif or custom photo).
        let fillWhole = overridePath == nil || Self.iconFill(name)
        NextDockView.composite(img, on: t.rect, fillWhole: fillWhole, in: ctx)
        if t.dots { drawDots(in: t.rect, ctx: ctx) }
    }

    /// Composite an icon onto a dock cell whose silver tile is already painted. `fillWhole` draws
    /// it edge-to-edge (the art carries its own tile); otherwise it sits inset so the silver tile
    /// shows around it.
    static func composite(_ img: NSImage, on rect: NSRect, fillWhole: Bool, in ctx: CGContext) {
        let target = fillWhole ? rect : rect.insetBy(dx: 9, dy: 9)
        img.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    /// The NeXT "…" mark (three LIGHT dots, along the very bottom-left) shown on a docked app that
    /// isn't running. Sits low, clear of the icon art, in a light grey (as in the original).
    private func drawDots(in r: NSRect, ctx: CGContext) {
        NSColor(srgbRed: 0.87, green: 0.87, blue: 0.92, alpha: 1).setFill()
        let d: CGFloat = 3, gap: CGFloat = 5
        let y = r.minY + 3
        for i in 0..<3 {
            ctx.fillEllipse(in: NSRect(x: r.minX + 6 + CGFloat(i) * gap, y: y, width: d, height: d))
        }
    }

    /// Bottom-pinned Recycler tile. Uses the authentic full-tile NeXT recycler art (grey bevel
    /// already baked in), drawn edge-to-edge like the other dock tiles.
    private func drawRecycler(in ctx: CGContext) {
        let r = NSRect(x: (bounds.width - tile) / 2, y: bounds.minY + 4, width: tile, height: tile)
        NeXTChrome.dockTile(r, flipped: false, in: ctx)   // silver base, like every dock cell
        if let img = theme.iconResource("nx_recycler.png").flatMap({ NSImage(contentsOf: $0) }) {
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                     hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
    }

    private func trashEmpty() -> Bool {
        let trash = URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")
        let items = (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []
        return items.filter { $0 != ".DS_Store" }.isEmpty
    }

    /// The iconic NeXT clock/calendar tile: green digital time on a dark LCD, a white calendar
    /// leaf below with weekday, big day number and month. Drawn natively (no logo/trademark).
    private func drawClock(in r: NSRect, ctx: CGContext) {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .weekday, .day, .month], from: now)
        let hour24 = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let pm = hour24 >= 12
        var h12 = hour24 % 12; if h12 == 0 { h12 = 12 }
        let timeStr = String(format: "%d:%02d", h12, minute)
        let weekday = cal.shortWeekdaySymbols[(comps.weekday ?? 1) - 1].uppercased()
        let day = comps.day ?? 1
        let month = cal.shortMonthSymbols[(comps.month ?? 1) - 1].uppercased()

        // LCD panel (top ~38%) — black with green digits.
        let lcd = NSRect(x: r.minX + 4, y: r.maxY - 34, width: r.width - 8, height: 26)
        NeXTChrome.black.setFill(); ctx.fill(lcd)
        NeXTChrome.bevel(lcd, raised: false, flipped: false, in: ctx)
        let green = NSColor(srgbRed: 0.20, green: 0.95, blue: 0.35, alpha: 1)
        // NeXT rendered its clock in Helvetica (its main UI font), not a monospace/LCD face.
        let tFont = NeXTChrome.titleFont(16)
        drawStr(timeStr, in: lcd.insetBy(dx: 4, dy: 3), font: tFont, color: green, align: .left)
        drawStr(pm ? "PM" : "AM", in: lcd.insetBy(dx: 4, dy: 6), font: NeXTChrome.titleFont(9), color: green, align: .right)

        // Calendar leaf (below) — white with black text.
        let leaf = NSRect(x: r.minX + 10, y: r.minY + 6, width: r.width - 20, height: r.height - 44)
        NSColor.white.setFill(); ctx.fill(leaf)
        NeXTChrome.bevel(leaf, raised: true, flipped: false, in: ctx)
        drawStr(weekday, in: NSRect(x: leaf.minX, y: leaf.maxY - 14, width: leaf.width, height: 12),
                font: NeXTChrome.titleFont(9), color: .black, align: .center)
        drawStr("\(day)", in: NSRect(x: leaf.minX, y: leaf.minY + 12, width: leaf.width, height: leaf.height - 26),
                font: NeXTChrome.titleFont(22), color: .black, align: .center)
        drawStr(month, in: NSRect(x: leaf.minX, y: leaf.minY + 1, width: leaf.width, height: 12),
                font: NeXTChrome.titleFont(9), color: .black, align: .center)
    }

    private func drawStr(_ s: String, in r: NSRect, font: NSFont, color: NSColor, align: NSTextAlignment) {
        let p = NSMutableParagraphStyle(); p.alignment = align
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        let h = (s as NSString).size(withAttributes: a).height
        (s as NSString).draw(in: NSRect(x: r.minX, y: r.midY - h/2, width: r.width, height: h), withAttributes: a)
    }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        layoutTiles()
        // Recycler first (bottom).
        let rr = NSRect(x: (bounds.width - tile) / 2, y: bounds.minY + 4, width: tile, height: tile)
        if rr.contains(p) { openTrash(); return }
        for t in tiles where t.rect.contains(p) { t.action?(); return }
    }

    // MARK: Context menu (right-click) — "Change Icon…" per dock tile.

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        layoutTiles()
        guard let t = tiles.first(where: { $0.rect.contains(p) }), let name = t.icon, !t.isClock else { return }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Change Icon\u{2026}", action: #selector(changeIcon(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = name
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func changeIcon(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        NextDockView.pickIcon { path, fill in
            var d = (UserDefaults.standard.dictionary(forKey: "nextDockIconOverrides") as? [String: String]) ?? [:]
            d[name] = path
            UserDefaults.standard.set(d, forKey: "nextDockIconOverrides")
            var f = (UserDefaults.standard.dictionary(forKey: "nextDockIconFill") as? [String: Bool]) ?? [:]
            f[name] = fill
            UserDefaults.standard.set(f, forKey: "nextDockIconFill")
            self.needsDisplay = true
        }
    }

    static func iconOverride(_ name: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: "nextDockIconOverrides") as? [String: String])?[name]
    }
    /// Whether a "Change Icon…" pick should fill the whole cell (true) or sit inset (false).
    static func iconFill(_ name: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: "nextDockIconFill") as? [String: Bool])?[name] ?? true
    }

    /// Shared icon picker used by both docks' and the running-app tiles' "Change Icon…": shows the
    /// bundled NeXT "Fleet" set in a grid, with a "Ganze Fläche füllen" checkbox and an "Eigene…"
    /// file-picker fallback. `done(path, fillWhole)`.
    static func pickIcon(_ done: @escaping (String, Bool) -> Void) {
        NextIconPickerController.shared.present(done: done)
    }
}
