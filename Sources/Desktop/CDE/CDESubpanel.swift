import AppKit

/// A CDE subpanel (Lastenheft 3.0, CDE-02, CDE-05): the column that slides up out of a Front
/// Panel arrow — a small titled window, "Install Icon" at the top, then one row per launcher.
/// Esc or a click elsewhere closes it. Apps dropped on "Install Icon" are added to that
/// subpanel and kept per theme; removing one (right-click) never touches the app itself.
final class CDESubpanel: NSView {

    enum Kind: String, CaseIterable {
        case links, cards, files, applications, mail, printers, tools, hosts, help, trash
        var title: String {
            switch self {
            case .links: "Links"; case .cards: "Cards"; case .files: "Files"
            case .applications: "Applications"; case .mail: "Mail"; case .printers: "Personal Printers"
            case .tools: "Tools"; case .hosts: "Hosts"; case .help: "Help"; case .trash: "Trash"
            }
        }
    }

    struct Item {
        let title: String
        let icon: NSImage?
        let action: () -> Void
        var personalPath: String? = nil   // set for launchers the user installed
    }

    // MARK: Showing

    private static var window: NSPanel?
    private static var openKind: Kind?

    static func toggle(_ kind: Kind, above cell: NSRect, in panelView: NSView) {
        if openKind == kind { closeAll(); return }
        closeAll()
        guard let theme = ThemeManager.shared.activeTheme, let host = panelView.window else { return }
        let view = CDESubpanel(kind: kind, theme: theme)
        let size = view.frame.size
        // Centred over its control, standing on the panel's top edge.
        let cellOnScreen = host.convertToScreen(panelView.convert(cell, to: nil))
        var origin = NSPoint(x: (cellOnScreen.midX - size.width / 2).rounded(), y: host.frame.maxY)
        if let screen = host.screen { origin.x = min(max(origin.x, screen.frame.minX), screen.frame.maxX - size.width) }
        let p = KeyableWidgetPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: 6)
        p.hasShadow = true
        p.contentView = view
        p.hidesOnDeactivate = false
        window = p; openKind = kind
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        // A click in another app closes it too: the panel only resigns key if it became key.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            DispatchQueue.main.async { closeAll() }
        }
        CDEEscape.hold { closeAll() }   // Esc closes it (CDE-02)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { _ in
            closeAll()   // a click anywhere else closes it
        }
    }
    private static var resignObserver: NSObjectProtocol?
    private static var outsideMonitor: Any?

    static func closeAll() {
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        guard let w = window else { return }
        window = nil; openKind = nil
        w.orderOut(nil)
        CDEEscape.release()
    }

    // MARK: Content

    private let kind: Kind
    private let theme: ThemeBundle
    private var items: [Item] = []
    private var pressedRow: Int?
    private static let width: CGFloat = 208, titleH: CGFloat = 17, rowH: CGFloat = 45, installH: CGFloat = 50

    init(kind: Kind, theme: ThemeBundle) {
        self.kind = kind
        self.theme = theme
        super.init(frame: .zero)
        items = Self.items(for: kind, theme: theme)
        setFrameSize(NSSize(width: Self.width, height: Self.titleH + 2 + Self.installH + 2 + CGFloat(items.count) * Self.rowH + 4))
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static func icon(_ theme: ThemeBundle, _ name: String) -> NSImage? {
        theme.iconResource(name).flatMap { NSImage(contentsOf: $0) }
    }
    private static func appIcon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
    private static func app(_ title: String, _ bundleID: String, icon: NSImage? = nil) -> Item {
        Item(title: title, icon: icon ?? appIcon(bundleID), action: CDEActions.app(bundleID))
    }
    private static func folder(_ title: String, _ url: URL, _ icon: NSImage?) -> Item {
        Item(title: title, icon: icon ?? NSWorkspace.shared.icon(forFile: url.path), action: CDEActions.open(url))
    }

    /// The Solaris 8 subpanels, with Mac targets. Icons from the reference where the screenshots
    /// show one; otherwise the app's own (ICO-07, the native fallback).
    static func items(for kind: Kind, theme t: ThemeBundle) -> [Item] {
        let fm = FileManager.default
        var list: [Item]
        switch kind {
        case .links:
            list = [Item(title: "Web Browser", icon: icon(t, "sp_web.png"), action: CDEActions.defaultApp(for: "https://")),
                    Item(title: "Personal Bookmarks", icon: icon(t, "sp_bookmarks.png"), action: CDEActions.defaultApp(for: "https://"))]
        case .cards:
            list = [app("Calendar", "com.apple.iCal", icon: icon(t, "sp_card.png")),
                    app("Find Card", "com.apple.AddressBook", icon: icon(t, "sp_findcard.png"))]
        case .files:
            let files = icon(t, "cde_files.png")
            list = [folder("Home Folder", CDEActions.home, files),
                    folder("Applications", URL(fileURLWithPath: "/Applications"), nil),
                    folder("Downloads", fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? CDEActions.home, nil)]
        case .applications:
            list = [app("Text Editor", "com.apple.TextEdit", icon: icon(t, "cde_texteditor.png")),
                    app("Terminal", "com.apple.Terminal"),
                    app("Calculator", "com.apple.calculator"),
                    Item(title: "Application Manager", icon: NSWorkspace.shared.icon(forFile: "/Applications"),
                         action: { AppFolderController.shared.show() })]
        case .mail:
            list = [Item(title: "Mail", icon: icon(t, "sp_mail.png"), action: CDEActions.defaultApp(for: "mailto:")),
                    Item(title: "Suggestion Box", icon: icon(t, "sp_suggest.png"),
                         action: CDEActions.open(URL(string: "https://github.com/klotzbrocken/RetroMac/issues")!))]
        case .printers:
            list = [Item(title: "Default Printer", icon: icon(t, "cde_printer.png"),
                         action: CDEActions.settings("com.apple.Print-Scan-Settings.extension"))]
        case .tools:
            list = [Item(title: "Desktop Style", icon: icon(t, "cde_style.png"),
                         action: CDEActions.settings("com.apple.Appearance-Settings.extension")),
                    Item(title: "RetroMac Settings", icon: NSApplication.shared.applicationIconImage,
                         action: { AppDelegate.shared?.launcherOpenSettings() }),
                    Item(title: "Workspaces", icon: appIcon("com.apple.exposelauncher"), action: CDEActions.missionControl)]
        case .hosts:
            list = [app("Performance Meter", "com.apple.ActivityMonitor"),
                    app("This Host", "com.apple.Terminal"),
                    app("System Info", "com.apple.SystemProfiler")]
        case .help:
            list = [Item(title: "Help Manager", icon: icon(t, "sp_helpmgr.png"), action: { ThemeReadmeController.shared.showForActiveTheme() }),
                    Item(title: "Desktop Introduction", icon: icon(t, "sp_intro.png"),
                         action: CDEActions.open(URL(string: "https://docs.oracle.com/cd/E19455-01/806-1360/index.html")!)),
                    Item(title: "Front Panel Help", icon: icon(t, "sp_fphelp.png"),
                         action: CDEActions.open(URL(string: "https://docs.oracle.com/cd/E19455-01/806-1360/6jalch31b/index.html")!)),
                    Item(title: "AnswerBook2", icon: icon(t, "sp_answerbook.png"),
                         action: CDEActions.open(URL(string: "https://docs.oracle.com/cd/E19455-01/")!))]
        case .trash:
            list = [folder("Open Trash", CDEActions.trash, icon(t, "cde_trash.png"))]
        }
        // The user's own launchers, after the built-in ones.
        for path in personal(kind) {
            let url = URL(fileURLWithPath: path)
            list.append(Item(title: fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""),
                             icon: NSWorkspace.shared.icon(forFile: path),
                             action: { NSWorkspace.shared.open(url) }, personalPath: path))
        }
        return list
    }

    // MARK: Personal launchers (UserDefaults "cdeSubpanelExtras", per subpanel)

    private static let extrasKey = "cdeSubpanelExtras"
    static func personal(_ kind: Kind) -> [String] {
        ((UserDefaults.standard.dictionary(forKey: extrasKey) as? [String: [String]]) ?? [:])[kind.rawValue] ?? []
    }
    static func setPersonal(_ kind: Kind, _ paths: [String]) {
        var all = (UserDefaults.standard.dictionary(forKey: extrasKey) as? [String: [String]]) ?? [:]
        all[kind.rawValue] = paths
        UserDefaults.standard.set(all, forKey: extrasKey)
    }

    // MARK: Drawing (CDE palette, measured)

    static let face = NSColor(srgbRed: 0xAD / 255, green: 0xB5 / 255, blue: 0xC6 / 255, alpha: 1)
    static let light = NSColor(srgbRed: 0xDE / 255, green: 0xDE / 255, blue: 0xE7 / 255, alpha: 1)
    static let dark = NSColor(srgbRed: 0x5A / 255, green: 0x63 / 255, blue: 0x6B / 255, alpha: 1)

    private static func bevel(_ r: NSRect, raised: Bool, width w: CGFloat = 1) {
        (raised ? light : dark).setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: w).fill()
        NSRect(x: r.minX, y: r.minY, width: w, height: r.height).fill()
        (raised ? dark : light).setFill()
        NSRect(x: r.minX, y: r.maxY - w, width: r.width, height: w).fill()
        NSRect(x: r.maxX - w, y: r.minY, width: w, height: r.height).fill()
    }

    private var font: NSFont { NSFont(name: "LucidaGrande", size: 13) ?? .systemFont(ofSize: 13) }

    /// Measured off the Solaris 8 Help subpanel: a 15 px title bar inside a 2 px bevel, the
    /// Install Icon row 50 px high over an etched line, then flat 45 px rows; icons at x 8,
    /// labels white over a dark shadow.
    private func rowRect(_ i: Int) -> NSRect {   // row 0 = Install Icon
        i == 0 ? NSRect(x: 2, y: Self.titleH + 2, width: bounds.width - 4, height: Self.installH)
               : NSRect(x: 2, y: Self.titleH + 2 + Self.installH + 2 + CGFloat(i - 1) * Self.rowH, width: bounds.width - 4, height: Self.rowH)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        Self.face.setFill(); bounds.fill()
        Self.bevel(bounds, raised: true, width: 2)
        // Title bar: the window-menu box on the left, the name centred, a 2 px shadow under it.
        let title = NSRect(x: 2, y: 2, width: bounds.width - 4, height: Self.titleH - 2)
        Self.dark.setFill(); NSRect(x: 2, y: title.maxY, width: bounds.width - 4, height: 2).fill()
        let box = NSRect(x: title.minX, y: title.minY, width: title.height, height: title.height)
        Self.bevel(box, raised: true)
        Self.dark.setFill(); NSRect(x: box.minX + 3, y: box.midY - 1, width: box.width - 6, height: 2).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let name = kind.title as NSString
        let nw = name.size(withAttributes: attrs).width
        name.draw(at: NSPoint(x: title.midX - nw / 2, y: title.minY), withAttributes: attrs)
        // Etched line under Install Icon.
        let sep = rowRect(0).maxY
        Self.dark.setFill(); NSRect(x: 2, y: sep, width: bounds.width - 4, height: 1).fill()
        Self.light.setFill(); NSRect(x: 2, y: sep + 1, width: bounds.width - 4, height: 1).fill()

        let rows = [Item(title: "Install Icon", icon: Self.icon(theme, "sp_install.png"), action: {})] + items
        for (i, item) in rows.enumerated() {
            let r = rowRect(i)
            if pressedRow == i { Self.bevel(r.insetBy(dx: 2, dy: 2), raised: false) }
            if let icon = item.icon {
                // The reference's own icons at their pixel size; a Mac app's icon at 32.
                let s = icon.size.width <= 40 && icon.size.width > 0 ? icon.size : NSSize(width: 32, height: 32)
                icon.draw(in: NSRect(x: r.minX + 6, y: (r.midY - s.height / 2).rounded(), width: s.width, height: s.height),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            let label = item.title as NSString
            let at = NSPoint(x: r.minX + 44, y: r.midY - 8)
            label.draw(at: NSPoint(x: at.x + 1, y: at.y + 1), withAttributes: [.font: font, .foregroundColor: Self.dark])
            label.draw(at: at, withAttributes: [.font: font, .foregroundColor: NSColor.white])
        }
    }

    // MARK: Interaction

    private func row(at p: NSPoint) -> Int? {
        (0...items.count).first { rowRect($0).contains(p) }
    }
    override func mouseDown(with event: NSEvent) {
        pressedRow = row(at: convert(event.locationInWindow, from: nil)).flatMap { $0 > 0 ? $0 : nil }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let was = pressedRow; pressedRow = nil; needsDisplay = true
        guard let r = row(at: convert(event.locationInWindow, from: nil)), r > 0, r == was else { return }
        let item = items[r - 1]
        Self.closeAll()
        item.action()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let r = row(at: convert(event.locationInWindow, from: nil)), r > 0,
              let path = items[r - 1].personalPath else { return }
        let menu = NSMenu()
        let remove = NSMenuItem(title: "Delete from Subpanel", action: #selector(removeItem(_:)), keyEquivalent: "")
        remove.target = self; remove.representedObject = path
        menu.addItem(remove)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func removeItem(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        Self.setPersonal(kind, Self.personal(kind).filter { $0 != path })
        Self.closeAll()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { Self.closeAll() } else { super.keyDown(with: event) }   // Esc
    }

    // Install Icon: an app dropped on the top row becomes a launcher here (CDE-05).
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropOp(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropOp(sender) }
    private func dropOp(_ sender: NSDraggingInfo) -> NSDragOperation {
        rowRect(0).contains(convert(sender.draggingLocation, from: nil)) && !droppedApps(sender).isEmpty ? .link : []
    }
    private func droppedApps(_ sender: NSDraggingInfo) -> [String] {
        ((sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? [])
            .filter { $0.pathExtension == "app" }.map(\.path)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let apps = droppedApps(sender)
        guard rowRect(0).contains(convert(sender.draggingLocation, from: nil)), !apps.isEmpty else { return false }
        Self.setPersonal(kind, Self.personal(kind) + apps.filter { !Self.personal(kind).contains($0) })
        Self.closeAll()
        return true
    }
}
