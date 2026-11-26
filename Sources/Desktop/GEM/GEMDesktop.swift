import AppKit

/// Atari TOS 4.04's GEM desktop on a Falcon030 (Lastenheft "Atari TOS 4.04 für RetroMac"): the
/// menu bar along the top edge, the drives and the trash on the coloured desktop, and APPS, the
/// RetroMac catalogue of every Mac app, as one more drive. Folders and documents go to the Finder.
///
/// The bar covers the Mac's menu bar only while the desktop is in front (the Finder or a click on
/// the bare desktop): when a Mac app is in front, its own menus are back (D5).
final class GEMDesktopController {
    static let shared = GEMDesktopController()
    private var bar: NSPanel?
    private var desk: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var clickMonitor: Any?
    private var trashTimer: Timer?
    private(set) var trashFull = false

    static var isActiveTheme: Bool { ThemeManager.shared.activeTheme?.config.chrome?.style == "gem" }

    func update() {
        guard AppSettings.shared.dockEnabled, !AppSettings.shared.dockOnly, Self.isActiveTheme else { hide(); return }
        show()
    }

    func hide() {
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); workspaceObservers = []
        DistributedNotificationCenter.default().removeObserver(self)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        trashTimer?.invalidate(); trashTimer = nil
        if PlatinumMenuController.shared.isOpen { PlatinumMenuController.shared.dismissAll() }
        GEMAppsWindowController.shared.close()
        bar?.orderOut(nil); desk?.orderOut(nil)
        bar = nil; desk = nil
    }

    var barView: GEMMenuBarView? { bar?.contentView as? GEMMenuBarView }
    var deskView: GEMDesktopView? { desk?.contentView as? GEMDesktopView }

    /// The keyboard launcher on TOS: APPS, where every program is.
    func openApps() -> Bool {
        guard desk != nil else { return false }
        GEMAppsWindowController.shared.show()
        return true
    }

    private func show() {
        if bar == nil {
            let b = TopEdgePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            b.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)   // over the Mac's menu bar, as the Amiga's screen bar
            b.isOpaque = true; b.hasShadow = false; b.hidesOnDeactivate = false
            b.acceptsMouseMovedEvents = true
            b.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            b.title = "Menu Bar"   // what VoiceOver calls it
            b.contentView = GEMMenuBarView(frame: .zero)
            bar = b

            let d = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            // Under the application windows, not at desktop level, where Sonoma takes a click as "show the desktop".
            d.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 4)
            d.isOpaque = false; d.backgroundColor = .clear; d.hasShadow = false; d.hidesOnDeactivate = false
            d.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            d.title = "Desktop"
            d.contentView = GEMDesktopView(frame: .zero)
            desk = d

            let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
            observers = [nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.layout() }]
            workspaceObservers = [
                ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.followFront() },
            ] + [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification].map {
                ws.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in self?.deskView?.reload() }
            }
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(trashChanged),
                                                                name: NSNotification.Name("com.apple.finder.trashdirectory.changed"), object: nil)
            trashTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshTrash() }
            // A click into another app's window gives that app its menus back.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                DispatchQueue.main.async { self?.followFront() }
            }
        }
        layout()
        desk?.orderFrontRegardless()
        followFront()
        refreshTrash()
    }

    /// The bar's height: the Atari's 19 points, or the Mac menu bar's when that is taller, so
    /// none of it shows below the rule (the strip under the rule is desktop).
    static func barHeight(on screen: NSScreen) -> CGFloat {
        max(GEMChrome.barHeight, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let h = Self.barHeight(on: screen)
        bar?.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h), display: true)
        desk?.setFrame(screen.frame, display: false)
        deskView?.top = h
        deskView?.reload()
    }

    /// The bar is up while the desktop is in front: the Finder, RetroMac, or right after a click on it.
    private func followFront() {
        let front = NSWorkspace.shared.frontmostApplication
        let deskInFront = front == nil || front?.bundleIdentifier == "com.apple.finder" || front?.processIdentifier == getpid()
        setBar(deskInFront)
    }

    func desktopClicked() { setBar(true) }

    private func setBar(_ up: Bool) {
        guard let bar else { return }
        if up { bar.orderFrontRegardless() } else {
            if PlatinumMenuController.shared.isOpen { PlatinumMenuController.shared.dismissAll() }
            bar.orderOut(nil)
        }
    }

    @objc private func trashChanged() { TrashState.invalidate(); refreshTrash() }
    private func refreshTrash() {
        TrashState.isEmpty { [weak self] empty in
            guard let self, self.trashFull == empty else { return }
            self.trashFull = !empty
            self.deskView?.needsDisplay = true
        }
    }

    // MARK: Actions the menus share

    /// The item a File command acts on: the APPS window's selection when it is in front, else the desktop's.
    func selectedURLsAndItems() -> (apps: [GEMApp], desk: [GEMDesktopView.Item]) {
        if let w = GEMAppsWindowController.shared.view, w.window?.isKeyWindow == true, let app = w.selectedApp { return ([app], []) }
        return ([], deskView?.selectedItems ?? [])
    }

    func openSelection() {
        let s = selectedURLsAndItems()
        s.apps.forEach(GEMApps.open)
        s.desk.forEach { deskView?.open($0) }
    }

    func showInfo() {
        let s = selectedURLsAndItems()
        if let app = s.apps.first { GEMDialog.info(for: app); return }
        if let item = s.desk.first { GEMDialog.info(for: item) }
    }

    /// Install Application: the chosen apps lie on the desktop as icons. Nothing is copied.
    func installApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the applications to install on the desktop"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        deskView?.pin(panel.urls, near: nil)
    }
}

// MARK: - Menu bar (D3, D4)

enum GEMMenus {
    static let titles = ["Desk", "File", "View", "Options"]

    static func items(_ title: String) -> [PlatinumMenuItem] {
        let c = GEMDesktopController.shared
        let apps = GEMAppsWindowController.shared
        let sel = c.selectedURLsAndItems()
        let none = sel.apps.isEmpty && sel.desk.isEmpty
        switch title {
        case "Desk":
            return [.action("Desktop Info...") { GEMDialog.desktopInfo() },
                    .separator(),
                    .action("RetroMac Applications...") { _ = c.openApps() }]
        case "File":
            return [.action("Open", dimmed: none) { c.openSelection() },
                    .action("Show Info...", dimmed: none) { c.showInfo() },
                    .separator(),
                    .action("Close Window", dimmed: !apps.isVisible) { apps.close() }]
        case "View":
            let s = GEMAppsSettings.self
            return [.action("Show as Icons", ticked: !s.asText) { s.asText = false },
                    .action("Show as Text", ticked: s.asText) { s.asText = true },
                    .separator(),
                    .action("Sort by Name", ticked: !s.byType) { s.byType = false },
                    .action("Sort by Type", ticked: s.byType) { s.byType = true },
                    .separator(),
                    .action("Size to Fit", ticked: s.sizeToFit) { s.sizeToFit.toggle() }]
        default:
            let pinned = sel.desk.contains { if case .app = $0.kind { return true }; return false }
            return [.action("Install Application...") { c.installApplication() },
                    .action("Remove Desktop Icon", dimmed: !pinned) { c.deskView?.unpinSelected() },
                    .separator(),
                    .action("Save Desktop") { c.deskView?.save() }]
        }
    }
}

final class GEMMenuBarView: NSView {
    private(set) var openTitle: Int? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Each title a space either side, from 16 in: " Desk " covers 16 … 63 in `_2.png`.
    static func titleRect(_ i: Int) -> NSRect {
        var x: CGFloat = 16
        for t in GEMMenus.titles.prefix(i) { x += GEMChrome.textWidth(" \(t) ") }
        return NSRect(x: x, y: 0, width: GEMChrome.textWidth(" \(GEMMenus.titles[i]) "), height: GEMChrome.barHeight - 1)
    }
    func titleIndex(at p: NSPoint) -> Int? { GEMMenus.titles.indices.first { Self.titleRect($0).contains(p) } }

    override func draw(_ dirtyRect: NSRect) {
        GEMChrome.desk.setFill(); bounds.fill()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: GEMChrome.barHeight - 1).fill()
        NSColor.black.setFill(); NSRect(x: 0, y: GEMChrome.barHeight - 1, width: bounds.width, height: 1).fill()
        for (i, t) in GEMMenus.titles.enumerated() {
            let r = Self.titleRect(i)
            let open = openTitle == i
            if open { NSColor.black.setFill(); r.insetBy(dx: 1, dy: 0).offsetBy(dx: 0, dy: 1).intersection(NSRect(x: 0, y: 1, width: bounds.width, height: 17)).fill() }
            GEMChrome.text(t, at: NSPoint(x: r.minX + GEMChrome.charW, y: 1), color: open ? .white : .black)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    /// GEM opens a menu as the pointer reaches its title, and moves to the next title with it.
    override func mouseMoved(with event: NSEvent) {
        if let i = titleIndex(at: convert(event.locationInWindow, from: nil)) { open(i) }
    }
    override func mouseDown(with event: NSEvent) {
        if let i = titleIndex(at: convert(event.locationInWindow, from: nil)) { open(i) } else { PlatinumMenuController.shared.dismissAll() }
    }

    func open(_ i: Int) {
        guard openTitle != i, let window else { return }
        let menus = PlatinumMenuController.shared
        let r = Self.titleRect(i)
        // The pulldown's top line lies on the bar's rule, its left edge one point left of the title.
        let anchor = window.convertToScreen(convert(NSRect(x: r.minX - 1, y: 0, width: r.width, height: GEMChrome.barHeight - 1), to: nil))
        menus.ignoreClickWindow = window
        menus.show(GEMMenus.items(GEMMenus.titles[i]), below: anchor, look: .gem)
        openTitle = i
        menus.onDismiss = { [weak self] in self?.openTitle = nil }
    }

    /// VoiceOver: the four titles, each opening its menu.
    private var axParts: [AccessibleHotspot] = []
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .menuBar }
    override func accessibilityChildren() -> [Any]? {
        axParts = GEMMenus.titles.indices.map { i in
            AccessibleHotspot.make(in: self, label: GEMMenus.titles[i], rect: Self.titleRect(i), role: .menuBarItem) { [weak self] in self?.open(i) }
        }
        return axParts
    }
}

// MARK: - Desktop (D1, D2)

final class GEMDesktopView: NSView {
    enum Kind: Equatable { case boot(URL), apps, trash, volume(URL), app(URL) }
    struct Item { let id: String; let name: String; let kind: Kind; let letter: Character? }

    var top: CGFloat = GEMChrome.barHeight
    private(set) var items: [Item] = []
    private var cells: [String: (c: Int, r: Int)] = [:]
    private var selection: Set<String> = [] { didSet { needsDisplay = true } }
    private var custom = DesktopStore.ThemeCustom()
    private var themeKey: String { ThemeManager.shared.activeTheme?.config.settingsKey ?? "gem" }
    private var images: [String: NSImage] = [:]

    private var dragStart: NSPoint?, dragOffset: NSSize?
    private var bandStart: NSPoint?, band: NSRect?
    private var dropTarget: String? { didSet { if dropTarget != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var selectedItems: [Item] { items.filter { selection.contains($0.id) } }

    // MARK: Model

    var columns: Int { max(1, Int(bounds.width / GEMChrome.cellW)) }
    var rows: Int { max(2, Int((bounds.height - top) / GEMChrome.cellH)) }

    /// The drives in their letters (C the startup disk, D APPS as in `_2.png`, then the mounted
    /// volumes), the trash, and the apps installed on the desktop.
    func reload() {
        custom = DesktopStore.load(theme: themeKey)
        let boot = URL(fileURLWithPath: "/")
        let bootName = (try? boot.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Hard Disk"
        var list = [Item(id: "boot", name: bootName, kind: .boot(boot), letter: "C"),
                    Item(id: "apps", name: "APPS", kind: .apps, letter: "D")]
        let letters = Array("EFGHIJKLMNOPQRSTUVWXYZ")
        for (n, v) in DesktopIconsController.mountedVolumes().enumerated() {
            list.append(Item(id: "vol:" + v.path, name: v.lastPathComponent, kind: .volume(v), letter: n < letters.count ? letters[n] : nil))
        }
        list.append(Item(id: "trash", name: "TRASH", kind: .trash, letter: nil))
        for e in custom.added where e.type == "app" {
            guard let path = e.path, FileManager.default.fileExists(atPath: path) else { continue }
            list.append(Item(id: "app:" + path, name: e.name, kind: .app(URL(fileURLWithPath: path)), letter: nil))
        }
        items = list
        cells = Self.layout(items.map(\.id), saved: custom.positions, columns: columns, rows: rows)
        selection = selection.filter { id in items.contains { $0.id == id } }
        needsDisplay = true
    }

    /// Where every icon goes: its saved cell if that is on screen and free; the drives down the
    /// left from the top, TRASH in the bottom left corner, installed apps down the right edge.
    static func layout(_ ids: [String], saved: [String: [CGFloat]], columns: Int, rows: Int) -> [String: (c: Int, r: Int)] {
        var out: [String: (c: Int, r: Int)] = [:]
        var taken = Set<Int>()
        func key(_ c: Int, _ r: Int) -> Int { c * 10_000 + r }
        func place(_ id: String, _ c: Int, _ r: Int) { out[id] = (c, r); taken.insert(key(c, r)) }
        for id in ids {
            if let p = saved[id], p.count == 2, Int(p[0]) < columns, Int(p[1]) < rows, Int(p[0]) >= 0, Int(p[1]) >= 0,
               !taken.contains(key(Int(p[0]), Int(p[1]))) { place(id, Int(p[0]), Int(p[1])) }
        }
        func free(fromRight: Bool) -> (Int, Int) {
            for c in (fromRight ? Array((0..<columns).reversed()) : Array(0..<columns)) {
                for r in 0..<rows where !taken.contains(key(c, r)) { return (c, r) }
            }
            return (0, 0)
        }
        if out["trash"] == nil, ids.contains("trash") {
            if !taken.contains(key(0, rows - 1)) { place("trash", 0, rows - 1) } else { let f = free(fromRight: false); place("trash", f.0, f.1) }
        }
        for id in ids where out[id] == nil {
            let f = free(fromRight: id.hasPrefix("app:"))
            place(id, f.0, f.1)
        }
        return out
    }

    func save() {
        custom.positions = cells.mapValues { [CGFloat($0.c), CGFloat($0.r)] }
        DesktopStore.save(custom, theme: themeKey)
    }

    func pin(_ urls: [URL], near cell: (c: Int, r: Int)?) {
        for url in urls where url.pathExtension == "app" {
            let path = url.path
            guard !custom.added.contains(where: { $0.path == path }) else { continue }
            let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            var e = DockThemeConfig.DesktopIconEntry(name: name, icon: "", type: "app")
            e.path = path
            custom.added.append(e)
            if let cell, !cells.values.contains(where: { $0 == cell }) { custom.positions["app:" + path] = [CGFloat(cell.c), CGFloat(cell.r)] }
        }
        DesktopStore.save(custom, theme: themeKey)
        reload()
    }

    /// Remove Desktop Icon: only the icon goes; the app stays where it is (D2).
    func unpinSelected() {
        let paths = Set(selectedItems.compactMap { if case .app(let u) = $0.kind { return u.path }; return nil })
        guard !paths.isEmpty else { return }
        custom.added.removeAll { paths.contains($0.path ?? "") }
        for p in paths { custom.positions["app:" + p] = nil }
        DesktopStore.save(custom, theme: themeKey)
        reload()
        save()
    }

    func open(_ item: Item) {
        switch item.kind {
        case .boot(let u), .volume(let u): NSWorkspace.shared.open(u)
        case .apps: GEMAppsWindowController.shared.show()
        case .trash: NSWorkspace.shared.open(CDEActions.trash)
        case .app(let u): GEMApps.open(GEMApp(url: u, name: item.name, bundleID: Bundle(url: u)?.bundleIdentifier, category: ""))
        }
    }

    // MARK: Geometry

    func cellOrigin(_ c: Int, _ r: Int) -> NSPoint { NSPoint(x: CGFloat(c) * GEMChrome.cellW, y: top + CGFloat(r) * GEMChrome.cellH) }
    func iconRect(_ id: String) -> NSRect? {
        cells[id].map { let o = cellOrigin($0.c, $0.r); return NSRect(x: o.x + GEMChrome.iconInset, y: o.y, width: 32, height: 32) }
    }
    func labelRect(_ id: String) -> NSRect? {
        cells[id].map { let o = cellOrigin($0.c, $0.r); return NSRect(x: o.x, y: o.y + 32, width: GEMChrome.labelW, height: GEMChrome.labelH) }
    }
    private func hit(_ p: NSPoint) -> Item? {
        items.last { (iconRect($0.id)?.contains(p) ?? false) || (labelRect($0.id)?.contains(p) ?? false) }
    }
    private func cell(at p: NSPoint) -> (c: Int, r: Int) {
        (min(columns - 1, max(0, Int(p.x / GEMChrome.cellW))), min(rows - 1, max(0, Int((p.y - top) / GEMChrome.cellH))))
    }

    // MARK: Drawing

    private func image(_ file: String) -> NSImage? {
        if let i = images[file] { return i }
        let i = ThemeManager.shared.activeTheme?.iconResource(file).flatMap { NSImage(contentsOf: $0) }
        images[file] = i
        return i
    }

    /// The picture of an item, in its selected form when there is one: the originals' second
    /// bitmaps from DESKICON.RSC, the new app icons' stippled state.
    func picture(_ item: Item, selected: Bool) -> NSImage? {
        let s = selected ? "_sel" : ""
        switch item.kind {
        case .boot, .volume, .apps: return image("gem_disk\(s).png")
        case .trash: return image((GEMDesktopController.shared.trashFull ? "gem_trash_full" : "gem_trash") + "\(s).png")
        case .app(let u): return GEMApps.icon(bundleID: Bundle(url: u)?.bundleIdentifier, selected: selected)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        for item in items {
            guard let ir = iconRect(item.id), let lr = labelRect(item.id) else { continue }
            let sel = selection.contains(item.id) || dropTarget == item.id
            GEMDesktopView.drawIcon(picture(item, selected: sel), letter: item.letter, name: item.name, icon: ir, labelBox: lr, selected: sel)
        }
        // The outlines GEM drags across the desktop, and the rubber band.
        if let off = dragOffset {
            for item in selectedItems {
                guard let ir = iconRect(item.id), let lr = labelRect(item.id) else { continue }
                GEMChrome.outline(ir.offsetBy(dx: off.width, dy: off.height))
                GEMChrome.outline(lr.offsetBy(dx: off.width, dy: off.height))
            }
        }
        if let band { GEMChrome.outline(band) }
    }

    /// An icon as GEM put it down: the picture, the drive letter in its window, the white label
    /// box under it with the name in the small font, white on black when selected.
    static func drawIcon(_ picture: NSImage?, letter: Character?, name: String, icon ir: NSRect, labelBox lr: NSRect, selected: Bool) {
        picture?.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        if let letter { GEMChrome.smallText(String(letter), at: NSPoint(x: ir.minX + 13, y: ir.minY + 19), color: .black) }
        (selected ? NSColor.black : NSColor.white).setFill(); lr.fill()
        let text = GEMChrome.smallLabel(name)
        GEMChrome.smallText(text, at: NSPoint(x: lr.minX + ((lr.width - CGFloat(text.count * 6)) / 2).rounded(.down), y: lr.minY + 1),
                            color: selected ? .white : .black)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        GEMDesktopController.shared.desktopClicked()
        let p = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)
        if let item = hit(p) {
            if event.clickCount == 2 { open(item); return }
            if shift { if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) } }
            else if !selection.contains(item.id) { selection = [item.id] }
            dragStart = p
        } else {
            if !shift { selection = [] }
            bandStart = p
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let s = dragStart, !selection.isEmpty {
            if dragOffset != nil || hypot(p.x - s.x, p.y - s.y) > 3 { dragOffset = NSSize(width: p.x - s.x, height: p.y - s.y) }
            dropTarget = hit(p).flatMap { $0.kind == .trash && !selection.contains($0.id) ? $0.id : nil }
            needsDisplay = true
        } else if let s = bandStart {
            let r = NSRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
            band = r
            selection = Set(items.filter { (iconRect($0.id)?.intersects(r) ?? false) || (labelRect($0.id)?.intersects(r) ?? false) }.map(\.id))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragOffset = nil; bandStart = nil; band = nil; dropTarget = nil; needsDisplay = true }
        guard let off = dragOffset else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let target = hit(p), target.kind == .trash, !selection.contains(target.id) {
            // Icons dropped on TRASH: an installed app loses its icon only; drives are not thrown away.
            unpinSelected()
            return
        }
        let dc = Int((off.width / GEMChrome.cellW).rounded()), dr = Int((off.height / GEMChrome.cellH).rounded())
        guard dc != 0 || dr != 0 else { return }
        let moving = selection
        let others = Set(cells.filter { !moving.contains($0.key) }.values.map { $0.c * 10_000 + $0.r })
        for id in moving {
            guard let old = cells[id] else { continue }
            let n = (c: min(columns - 1, max(0, old.c + dc)), r: min(rows - 1, max(0, old.r + dr)))
            if !others.contains(n.c * 10_000 + n.r) { cells[id] = n }
        }
        save()
    }

    // MARK: Drops from the Finder and from APPS

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { draggingUpdated(info) }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        let p = convert(info.draggingLocation, from: nil)
        if let t = hit(p), t.kind == .trash { dropTarget = t.id; return .delete }
        dropTarget = nil
        return fileURLs(info).contains { $0.pathExtension == "app" } && hit(p) == nil ? .link : []
    }
    override func draggingExited(_ info: NSDraggingInfo?) { dropTarget = nil }
    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let p = convert(info.draggingLocation, from: nil)
        let urls = fileURLs(info)
        dropTarget = nil
        guard !urls.isEmpty else { return false }
        if let t = hit(p), t.kind == .trash {
            // Into the Mac's own trash, where it can be put back from; TOS asked first, so does this.
            let what = urls.count == 1 ? "\"\(urls[0].lastPathComponent)\"" : "\(urls.count) items"
            GEMDialog.show([.text("Move \(what)"), .text("to the Trash?")], buttons: ["OK", "Cancel"]) { choice in
                guard choice == 0 else { return }
                NSWorkspace.shared.recycle(urls) { _, error in
                    if error != nil { DispatchQueue.main.async { GEMDialog.show([.text("The items could not"), .text("be moved to the Trash.")], buttons: ["OK"]) } }
                }
            }
            return true
        }
        pin(urls, near: cell(at: p))
        return true
    }

    // MARK: VoiceOver

    private var axParts: [AccessibleHotspot] = []
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        axParts = items.compactMap { item in
            guard let ir = iconRect(item.id), let lr = labelRect(item.id) else { return nil }
            let name = item.kind == .apps ? "APPS, all applications" : item.name
            return AccessibleHotspot.make(in: self, label: name, rect: ir.union(lr)) { [weak self] in self?.open(item) }
        }
        return axParts
    }
}
