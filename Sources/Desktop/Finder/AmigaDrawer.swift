import AppKit
import UniformTypeIdentifiers

/// The Workbench's own drawer windows (Amiga Workbench 4.1, `"finder": "amiga"`): one window per
/// drawer, its icons standing where they were put, on the speckled grey of the 2008 requesters.
/// An object shows when it has an icon — a drawer, a tool, a project of a known kind, or anything
/// with an AmigaOS 4 `.info` (PNG) beside it, whose picture it then wears; "Show ▸ All files"
/// shows the rest with the type's icon. Snapshot keeps a window's place and its icons' places
/// (in RetroMac's settings, never as files in the drawer); Unsnapshot gives them back.
final class AmigaDrawer: NSObject {

    static var isEnabled: Bool { ThemeManager.shared.activeTheme?.config.finder == "amiga" }
    /// The System volume's own drawer, a fixed list mapped onto the Mac (`systemItems`).
    static let systemToken = "SYS:"

    /// One window per drawer, by path.
    private static var open: [String: AmigaDrawer] = [:]
    /// The drawer the Window and Icons menus work on: the one last used, while it is open.
    private(set) static weak var active: AmigaDrawer?
    static func deactivate() { active = nil }

    struct Item: Equatable {
        enum Kind: Equatable { case drawer, app, project, trash, clipboard }
        var name: String
        var url: URL?
        var kind: Kind
        /// The theme icon to wear (drawers of the System list have their own).
        var icon: String?
        /// A `.info` beside the object: its picture is the icon.
        var info: URL?
    }

    /// Opens the drawer at `path` ("SYS:" for the System list), or brings its window forward.
    static func show(_ path: String) {
        _ = observer
        let key = path == systemToken ? path : URL(fileURLWithPath: path).standardizedFileURL.path
        if let d = open[key] { d.panel?.makeKeyAndOrderFront(nil); active = d; return }
        let d = AmigaDrawer(key: key)
        open[key] = d
        d.present()
    }

    @objc private static func themeChanged() { if !isEnabled { open.values.forEach { $0.close() } } }
    private static let observer: Void = {
        NotificationCenter.default.addObserver(AmigaDrawer.self, selector: #selector(themeChanged), name: .dockThemeChanged, object: nil)
    }()

    // MARK: - What a drawer shows

    /// The kinds a project may be without a `.info`: what the Workbench of 2008 had DefIcons for.
    private static let knownKinds: [UTType] = [.text, .image, .audio, .movie, .pdf, .archive, .sourceCode, .html]

    /// The objects in `dir`, sorted by name: never hidden files, never the `.info` files
    /// themselves; without `allFiles` only those with an icon (see the type's comment).
    static func items(in dir: URL, allFiles: Bool) -> [Item] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey, .isHiddenKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let names = Set(urls.map(\.lastPathComponent))
        var out: [Item] = []
        for u in urls {
            let name = u.lastPathComponent
            if name.lowercased().hasSuffix(".info") { continue }
            let v = try? u.resourceValues(forKeys: Set(keys))
            let info = names.contains(name + ".info") ? u.appendingPathExtension("info") : nil
            let kind: Item.Kind
            if u.pathExtension == "app" { kind = .app }
            else if v?.isDirectory == true && v?.isPackage != true { kind = .drawer }
            else { kind = .project }
            if !allFiles, kind == .project, info == nil {
                guard let t = v?.contentType, knownKinds.contains(where: { t.conforms(to: $0) }) else { continue }
            }
            out.append(Item(name: kind == .app ? u.deletingPathExtension().lastPathComponent : name, url: u, kind: kind, icon: nil, info: info))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The System drawer: the Workbench's own drawers, each mapped onto the Mac's counterpart.
    static func systemItems() -> [Item] {
        let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences")
        let disk = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
        return [
            Item(name: "Prefs", url: settings, kind: .app, icon: "drawer-prefs.png"),
            Item(name: "Utilities", url: URL(fileURLWithPath: "/Applications/Utilities"), kind: .drawer, icon: "drawer-utilities.png"),
            Item(name: "Tools", url: URL(fileURLWithPath: "/Applications"), kind: .drawer, icon: "drawer.png"),
            Item(name: "Fonts", url: URL(fileURLWithPath: "/Library/Fonts"), kind: .drawer, icon: "drawer-fonts.png"),
            Item(name: "Trashcan", url: nil, kind: .trash, icon: "trashcan.png"),
            Item(name: disk, url: URL(fileURLWithPath: "/"), kind: .drawer, icon: "harddrive.png"),
        ]
    }

    // MARK: - Snapshot

    struct Snapshot: Codable, Equatable {
        var frame: [CGFloat]? = nil          // x, y, width, height
        var icons: [String: [CGFloat]] = [:]  // name → x, y (the drawer's own coordinates)
        var allFiles = false
    }
    static func defaultsKey(_ key: String) -> String { "amigaDrawer." + key }
    static func loadSnapshot(_ key: String, _ d: UserDefaults = .standard) -> Snapshot {
        guard let data = d.data(forKey: defaultsKey(key)), let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Snapshot() }
        return s
    }
    static func saveSnapshot(_ s: Snapshot, _ key: String, _ d: UserDefaults = .standard) {
        if s == Snapshot() { d.removeObject(forKey: defaultsKey(key)) } else if let data = try? JSONEncoder().encode(s) { d.set(data, forKey: defaultsKey(key)) }
    }

    // MARK: - The window

    let key: String
    private var panel: DrawerPanel?
    private var chrome: WebAppChromeView?
    private let surface = DrawerSurface(frame: NSRect(x: 0, y: 0, width: 400, height: 260))
    private let scroll = NSScrollView()
    private var snap: Snapshot
    private var items: [Item] = []
    private var iconViews: [DesktopIconView] = []
    /// Where icons stand now; Snapshot writes it down, Clean up and Unsnapshot rearrange.
    private var placed: [String: NSPoint] = [:]

    private init(key: String) {
        self.key = key
        snap = Self.loadSnapshot(key)
        super.init()
    }

    var isSystem: Bool { key == Self.systemToken }
    var url: URL? { isSystem ? nil : URL(fileURLWithPath: key) }
    var showsAllFiles: Bool { snap.allFiles }

    private var title: String {
        guard let url else { return "System" }
        let v = try? url.resourceValues(forKeys: [.isVolumeKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        // A volume's window says how full it is, as the Workbench's did ("AmigaOS41  9% full").
        if v?.isVolume == true, let total = v?.volumeTotalCapacity, let free = v?.volumeAvailableCapacity, total > 0 {
            return "\(v?.volumeName ?? url.lastPathComponent)  \(Int((Double(total - free) / Double(total) * 100).rounded()))% full"
        }
        if url.path == AmigaRAMDisk.url.path { return "Ram Disk" }
        return url.path == NSHomeDirectory() ? "Work" : url.lastPathComponent
    }

    private func present() {
        let size = NSSize(width: 440, height: 300)
        let frame = NSRect(origin: .zero, size: size)
        let chrome = WebAppChromeView(frame: frame, title: title)
        chrome.windowControls = true
        chrome.onClose = { [weak self] in self?.close() }
        chrome.onZoom = { [weak self] in self?.toggleZoom() }
        chrome.onMinimize = { [weak self] in self?.panel?.miniaturize(nil) }
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = surface
        surface.drawer = self
        chrome.embed(scroll)
        self.chrome = chrome

        let p = DrawerPanel(contentRect: frame, styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false   // a panel hides with its app otherwise, and RetroMac is rarely the active one
        p.minSize = NSSize(width: 160, height: 110)
        p.contentView = chrome
        p.setAccessibilityTitle(title)
        p.onKey = { [weak self] in Self.active = self }
        if let f = snap.frame, f.count == 4 {
            p.setFrame(NSRect(x: f[0], y: f[1], width: f[2], height: f[3]), display: false)
        } else if let screen = NSScreen.main {
            // Cascade down and right from the top left of the work area, as drawers opened.
            let vf = DesktopIconsController.iconArea(of: screen, bar: DockController.shared.barScreenFrame)
            let n = CGFloat(Self.open.count - 1)
            p.setFrameTopLeftPoint(NSPoint(x: vf.minX + 140 + n * 24, y: vf.maxY - 40 - n * 24))
        }
        panel = p
        reload()
        Self.active = self
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil); panel = nil
        Self.open.removeValue(forKey: key)
        if Self.active === self { Self.active = nil }
    }

    private var preZoom: NSRect?
    private func toggleZoom() {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }
        if let f = preZoom { p.setFrame(f, display: true, animate: true); preZoom = nil }
        else { preZoom = p.frame; p.setFrame(DesktopIconsController.iconArea(of: screen, bar: DockController.shared.barScreenFrame).insetBy(dx: 20, dy: 20), display: true, animate: true) }
    }

    // MARK: - Icons

    private static let cell = NSSize(width: 92, height: 84)
    private static let iconSize: CGFloat = 40

    /// Reads the drawer again (Update) and lays the icons out: snapshot places first, then the
    /// rest in rows, left to right.
    func reload() {
        items = isSystem ? Self.systemItems() : (url.map { Self.items(in: $0, allFiles: snap.allFiles) } ?? [])
        // RAM:Clipboards holds unit 0, the clipboard, shown from memory and never written to disk:
        // it is where passwords pass through.
        if url?.standardizedFileURL.path == AmigaRAMDisk.url.appendingPathComponent("Clipboards").standardizedFileURL.path,
           AmigaClipboardViewer.hasContent {
            items.insert(Item(name: "0", url: nil, kind: .clipboard), at: 0)
        }
        chrome?.title = title
        iconViews.forEach { $0.removeFromSuperview() }
        iconViews = []
        let theme = ThemeManager.shared.activeTheme
        let label = theme?.config.desktopLabel
        for item in items {
            var e = DockThemeConfig.DesktopIconEntry(name: item.name, icon: item.icon ?? "", type: "amigaItem")
            e.path = item.url?.path
            let (image, selected) = picture(for: item, theme: theme)
            let v = DesktopIconView(entry: e, image: image, fullImage: nil, iconSize: Self.iconSize, isPixelated: false, labelStyle: label)
            v.selectedImage = selected
            v.target = self
            v.action = #selector(openIcon(_:))
            v.onMoved = { [weak self] v in self?.placed[v.entry.name] = v.frame.origin }
            iconViews.append(v)
            surface.addSubview(v)
        }
        layoutIcons()
    }

    private func layoutIcons() {
        let width = max(scroll.contentSize.width, Self.cell.width + 12)
        let columns = max(1, Int((width - 12) / Self.cell.width))
        var maxY: CGFloat = 0, maxX: CGFloat = 0
        // Icons with a place keep it; the others take the next cell in the rows that no icon
        // stands in (a file shown by "All files" used to land on top of the first drawer).
        func known(_ name: String) -> NSPoint? {
            if let p = placed[name] { return p }
            if let s = snap.icons[name], s.count == 2 { return NSPoint(x: s[0], y: s[1]) }
            return nil
        }
        var taken = iconViews.compactMap { known($0.entry.name).map { NSRect(origin: $0, size: Self.cell).insetBy(dx: 4, dy: 4) } }
        var slot = 0
        for v in iconViews {
            let name = v.entry.name
            let origin: NSPoint
            if let p = known(name) { origin = p }
            else {
                var cell: NSRect
                repeat {
                    cell = NSRect(x: 6 + CGFloat(slot % columns) * Self.cell.width, y: 6 + CGFloat(slot / columns) * Self.cell.height,
                                  width: Self.cell.width, height: Self.cell.height)
                    slot += 1
                } while taken.contains { $0.intersects(cell) }
                taken.append(cell.insetBy(dx: 4, dy: 4))
                origin = cell.origin
            }
            placed[name] = origin
            v.frame = NSRect(origin: origin, size: Self.cell)
            maxX = max(maxX, v.frame.maxX); maxY = max(maxY, v.frame.maxY)
        }
        surface.frame = NSRect(x: 0, y: 0, width: max(scroll.contentSize.width, maxX + 6), height: max(scroll.contentSize.height, maxY + 6))
    }

    private func picture(for item: Item, theme: ThemeBundle?) -> (NSImage, NSImage?) {
        // An AmigaOS 4 icon beside the object: its picture (PNG icons read as images; the
        // older formats do not, and the type's icon stands in).
        if let info = item.info, let img = NSImage(contentsOf: info) { return (img, nil) }
        let name: String
        switch item.kind {
        case .drawer: name = item.icon ?? "drawer.png"
        case .trash: name = "trashcan.png"
        case .project, .clipboard: name = "project.png"
        case .app:
            let bid = item.url.flatMap { Bundle(url: $0)?.bundleIdentifier }
            name = item.icon ?? bid.flatMap { theme?.config.iconMappings[$0] } ?? "tool.png"
        }
        func load(_ n: String) -> NSImage? { theme?.iconResource(n).flatMap { NSImage(contentsOf: $0) } }
        let image = load(name) ?? NSWorkspace.shared.icon(forFile: item.url?.path ?? "/")
        return (image, load((name as NSString).deletingPathExtension + "-sel.png"))
    }

    @objc private func openIcon(_ v: DesktopIconView) {
        Self.active = self
        guard let item = items.first(where: { $0.name == v.entry.name }) else { return }
        open(item)
    }

    private func open(_ item: Item) {
        switch item.kind {
        case .drawer: if let u = item.url { Self.show(u.path) }
        case .trash: DesktopLauncher.launch(DockThemeConfig.DesktopIconEntry(name: "Trashcan", icon: "", type: "trash"))
        case .app: if let u = item.url { NSWorkspace.shared.open(u) }
        case .project:
            guard let u = item.url else { return }
            // A file no app claims opens as text, as MultiView showed anything (macOS asked which
            // app instead, for a file with no known type).
            if NSWorkspace.shared.urlForApplication(toOpen: u) == nil,
               let edit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                NSWorkspace.shared.open([u], withApplicationAt: edit, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(u)
            }
        case .clipboard: AmigaClipboardViewer.show()
        }
    }

    private var selectedViews: [DesktopIconView] { iconViews.filter(\.selected) }
    var hasSelection: Bool { !selectedViews.isEmpty }
    var canChange: Bool { !isSystem && url.map { FileManager.default.isWritableFile(atPath: $0.path) } == true }

    // MARK: - The menus' work (Window and Icons)

    func openParent() {
        guard let u = url, u.path != "/" else { return }
        Self.show(u.deletingLastPathComponent().path)
    }
    func newDrawer() {
        guard let u = url, canChange else { return }
        var n = 1
        while FileManager.default.fileExists(atPath: u.appendingPathComponent("Unnamed\(n)").path) { n += 1 }
        try? FileManager.default.createDirectory(at: u.appendingPathComponent("Unnamed\(n)"), withIntermediateDirectories: false)
        reload()
    }
    func selectContents() { iconViews.forEach { $0.select() } }
    /// Clean up: the icons back into rows, keeping their order; the snapshot stays until Snapshot.
    func cleanUp() {
        placed = [:]
        let saved = snap.icons; snap.icons = [:]; layoutIcons(); snap.icons = saved
    }
    func setAllFiles(_ all: Bool) {
        snap.allFiles = all
        Self.saveSnapshot(snap, key)
        reload()
    }
    /// Snapshot ▸ Window: where the window stands and how big; ▸ All: and every icon's place.
    func snapshot(all: Bool) {
        guard let f = panel?.frame else { return }
        snap.frame = [f.minX, f.minY, f.width, f.height]
        if all { for v in iconViews { snap.icons[v.entry.name] = [v.frame.minX, v.frame.minY] } }
        Self.saveSnapshot(snap, key)
    }
    /// Icons ▸ Snapshot / Unsnapshot: the selected icons keep their place, or give it back.
    func snapshotSelected() {
        for v in selectedViews { snap.icons[v.entry.name] = [v.frame.minX, v.frame.minY] }
        Self.saveSnapshot(snap, key)
    }
    func unsnapshotSelected() {
        for v in selectedViews { snap.icons.removeValue(forKey: v.entry.name); placed.removeValue(forKey: v.entry.name) }
        Self.saveSnapshot(snap, key)
        layoutIcons()
    }
    func openSelected() { for v in selectedViews { openIcon(v) } }
    /// Delete: the selected objects go to the Mac's Trash (recoverable there), after asking.
    func deleteSelected() {
        let urls = selectedViews.compactMap { v in items.first { $0.name == v.entry.name }?.url }
        guard canChange, !urls.isEmpty else { return }
        let a = NSAlert()
        a.messageText = urls.count == 1 ? "Delete \u{201C}\(urls[0].lastPathComponent)\u{201D}?" : "Delete \(urls.count) objects?"
        a.informativeText = "They go to the Trash, where they can be taken back out."
        a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.recycle(urls) { [weak self] _, _ in DispatchQueue.main.async { self?.reload() } }
    }
}

final class DrawerPanel: NSPanel {
    var onKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func becomeKey() { super.becomeKey(); onKey?() }
}

/// The drawer's inside: the speckled grey tile, the icons on it; a click on the empty space
/// clears the selection, the right button opens the Workbench menus.
final class DrawerSurface: NSView {
    weak var drawer: AmigaDrawer?
    private lazy var tile: NSColor? = {
        guard let u = ThemeManager.shared.activeTheme?.rootResource("drawer-pattern.png"), let img = NSImage(contentsOf: u) else { return nil }
        img.size = NSSize(width: 64, height: 64)
        return NSColor(patternImage: img)
    }()
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (tile ?? AmigaChrome.rgb(0xE9E8E8)).setFill()
        dirtyRect.fill()
    }
    override func mouseDown(with event: NSEvent) { subviews.compactMap { $0 as? DesktopIconView }.forEach { $0.deselect() } }
    override func rightMouseDown(with event: NSEvent) { AmigaScreenBarController.shared.beginMenus() }
}

/// Clipboard unit 0, as RAM:Clipboards/0 held it: what is on the Mac's clipboard now, text or a
/// picture, in a Workbench window. Read when opened, kept in memory only.
enum AmigaClipboardViewer {
    private static var panel: NSPanel?

    static var hasContent: Bool {
        let pb = NSPasteboard.general
        return pb.string(forType: .string) != nil || NSImage(pasteboard: pb) != nil
    }

    static func show() {
        panel?.orderOut(nil)
        let size = NSSize(width: 440, height: 300)
        let chrome = WebAppChromeView(frame: NSRect(origin: .zero, size: size), title: "Clipboard unit 0")
        let pb = NSPasteboard.general
        let content: NSView
        if let text = pb.string(forType: .string) {
            let scroll = NSTextView.scrollableTextView()
            if let tv = scroll.documentView as? NSTextView {
                tv.string = text
                tv.isEditable = false
                tv.font = AmigaChrome.titleFont()
                tv.backgroundColor = AmigaChrome.rgb(0xE9E8E8)
            }
            content = scroll
        } else if let image = NSImage(pasteboard: pb) {
            let iv = NSImageView(image: image)
            iv.imageScaling = .scaleProportionallyDown
            content = iv
        } else {
            let label = NSTextField(labelWithString: "The clipboard is empty.")
            label.font = AmigaChrome.titleFont(); label.alignment = .center
            content = label
        }
        chrome.embed(content)
        let p = DrawerPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = chrome
        p.setAccessibilityTitle("Clipboard unit 0")
        chrome.onClose = { p.orderOut(nil); if panel === p { panel = nil } }
        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }
}
