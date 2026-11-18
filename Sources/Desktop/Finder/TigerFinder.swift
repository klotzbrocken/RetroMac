import AppKit
import CoreImage

/// Mac OS X 10.4's Finder, rebuilt for the Tiger theme (`"finder": "tiger"` in a manifest): a
/// brushed-metal window with Back/Forward, the three views, the action menu and a search field
/// in its toolbar, the sidebar of places, and "9 items, 70.32 GB available" along the bottom.
/// Everything in it is the real file system: a double-click opens the file in its own app, the
/// Trash is macOS's Trash (nothing is ever deleted outright), a rename renames.
///
/// It hosts AppKit's own views (a collection view, an outline view, `NSBrowser`) inside the
/// themed window shell the web apps use, so the frame, title bar and traffic lights are the
/// ones every other Aqua window of the theme wears.
final class TigerFinder: NSObject {

    /// The active theme asks for it; otherwise folders go to the real Finder.
    static var isEnabled: Bool { ThemeManager.shared.activeTheme?.config.finder == "tiger" }

    private static var windows: [TigerFinder] = []

    /// A new window on `url` (a folder; a file opens its folder with the file selected).
    static func show(_ url: URL) {
        let f = TigerFinder()
        windows.append(f)
        f.present()
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        f.go(to: isDir ? url : url.deletingLastPathComponent(), record: false)
    }

    /// A new window showing what Spotlight finds for `text` (Spotlight's "Show All").
    static func showSearch(_ text: String) {
        let f = TigerFinder()
        windows.append(f)
        f.present()
        f.go(to: FileManager.default.homeDirectoryForCurrentUser, record: false)
        f.search.stringValue = text
        f.runSearch(text)
    }

    /// Every window closes with the theme: another theme has another Finder.
    @objc private static func themeChanged() { if !isEnabled { windows.forEach { $0.close() } } }
    private static let observer: Void = {
        NotificationCenter.default.addObserver(TigerFinder.self, selector: #selector(themeChanged), name: .dockThemeChanged, object: nil)
    }()

    // MARK: - State

    enum Mode: Int { case icons, list, columns }

    private var panel: FinderPanel?
    private var chrome: WebAppChromeView?
    let view = FinderView(frame: NSRect(x: 0, y: 0, width: 744, height: 430))
    private var current = FileManager.default.homeDirectoryForCurrentUser
    private var items: [FinderItem] = []
    private var back: [URL] = [], forward: [URL] = []
    private var mode: Mode = .icons
    private var searching: String?
    private var keyMonitor: Any?
    private let engine = SpotlightSearch()

    private var search: NSSearchField { view.toolbar.search }

    // MARK: - Window

    private func present() {
        _ = Self.observer
        let size = NSSize(width: 760, height: 470)
        let frame = NSRect(origin: .zero, size: size)
        let chrome = WebAppChromeView(frame: frame, title: "", showNav: false)
        chrome.onClose = { [weak self] in self?.close() }
        chrome.onZoom = { [weak self] in self?.toggleZoom() }
        chrome.onMinimize = { [weak self] in self?.panel?.miniaturize(nil) }
        chrome.windowControls = true
        chrome.embed(view)
        self.chrome = chrome

        let p = FinderPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .miniaturizable], backing: .buffered, defer: false)
        p.level = .normal
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false
        p.minSize = NSSize(width: 480, height: 260)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = chrome
        p.setAccessibilityTitle("Finder")
        // Cascade from the last one, as Finder did.
        if let last = Self.windows.dropLast().last?.panel {
            p.setFrameTopLeftPoint(NSPoint(x: last.frame.minX + 22, y: last.frame.maxY - 22))
        } else if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2 + 40))
        }
        panel = p
        wire()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            return self.handleKey(e) ? nil : e
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    private func close() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        engine.cancel()
        panel?.orderOut(nil); panel = nil
        Self.windows.removeAll { $0 === self }
    }

    private var preZoom: NSRect?
    private func toggleZoom() {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }
        if let f = preZoom { p.setFrame(f, display: true, animate: true); preZoom = nil }
        else { preZoom = p.frame; p.setFrame(screen.visibleFrame.insetBy(dx: 20, dy: 20), display: true, animate: true) }
    }

    func wire() {
        let tb = view.toolbar
        tb.onBack = { [weak self] in self?.goBack() }
        tb.onForward = { [weak self] in self?.goForward() }
        tb.onMode = { [weak self] m in self?.setMode(m) }
        tb.onAction = { [weak self] a in self?.perform(a) }
        tb.onSearch = { [weak self] text in self?.runSearch(text) }
        view.sidebar.onPick = { [weak self] url in self?.go(to: url) }
        view.icons.onOpen = { [weak self] in self?.openSelection() }
        view.icons.dataSource = self
        view.icons.delegate = self
        view.list.dataSource = self
        view.list.delegate = self
        view.list.target = self
        view.list.doubleAction = #selector(listDoubleClick)
        view.columns.delegate = self
        view.columns.target = self
        view.columns.doubleAction = #selector(columnDoubleClick)
        view.columns.action = #selector(columnClick)
        setMode(.icons)
    }

    // MARK: - Navigation

    func go(to url: URL, record: Bool = true) {
        if record, url != current { back.append(current); forward.removeAll() }
        current = url
        leaveSearch()
        reload()
    }

    private func goBack() { guard let u = back.popLast() else { return }; forward.append(current); current = u; leaveSearch(); reload() }
    private func goForward() { guard let u = forward.popLast() else { return }; back.append(current); current = u; leaveSearch(); reload() }
    private func goUp() {
        let parent = current.deletingLastPathComponent()
        if parent.path != current.path { go(to: parent) }
    }

    private func leaveSearch() {
        guard searching != nil else { return }
        searching = nil
        engine.cancel()
        search.stringValue = ""
    }

    private func reload() {
        if searching == nil { items = FinderItem.children(of: current) }
        let name = searching.map { "Searching \u{201C}\($0)\u{201D}" } ?? FinderItem.displayName(current)
        chrome?.title = name
        panel?.setAccessibilityTitle(name)
        view.toolbar.setNav(back: !back.isEmpty, forward: !forward.isEmpty)
        view.sidebar.select(searching == nil ? current : nil)
        view.icons.reloadData()
        view.list.reloadData()
        if mode == .columns { view.columns.setPath("/"); view.columns.loadColumnZero() }
        updateStatus()
    }

    private func updateStatus() {
        let n = searching == nil ? items.count : items.count
        let free = (try? current.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        var s = "\(n) item\(n == 1 ? "" : "s")"
        if let free { s += ", " + ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " available" }
        view.status.stringValue = s
    }

    func setMode(_ m: Mode) {
        // A search shows a flat list; the other views have no place for results from everywhere.
        mode = searching != nil && m != .list ? .list : m
        view.show(mode)
        view.toolbar.setMode(mode)
        if mode == .columns { view.columns.setPath("/"); view.columns.loadColumnZero() }
        panel?.makeFirstResponder(mode == .icons ? view.icons : mode == .list ? view.list : view.columns)
    }

    // MARK: - Search (the field in the toolbar)

    private func runSearch(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { leaveSearch(); reload(); return }
        searching = t
        items = []
        setMode(.list)
        reload()
        engine.run(t, limit: 500) { [weak self] groups in
            guard let self, self.searching == t else { return }   // a newer search owns the window
            self.items = groups.flatMap(\.items).map { FinderItem(url: $0.url) }
            self.view.list.reloadData()
            self.updateStatus()
        }
    }

    // MARK: - Selection and actions

    private var selection: [FinderItem] {
        switch mode {
        case .icons: return view.icons.selectionIndexPaths.map { items[$0.item] }
        case .list: return view.list.selectedRowIndexes.compactMap { view.list.item(atRow: $0) as? FinderItem }
        case .columns:
            let c = view.columns.selectedColumn
            guard c >= 0 else { return [] }
            return view.columns.selectedRowIndexes(inColumn: c)?.compactMap { view.columns.item(atRow: $0, inColumn: c) as? FinderItem } ?? []
        }
    }

    private func open(_ item: FinderItem) {
        if item.isFolder { go(to: item.url) } else { NSWorkspace.shared.open(item.url) }
    }

    private func openSelection() { selection.forEach(open) }

    @objc private func listDoubleClick() {
        guard let i = view.list.item(atRow: view.list.clickedRow) as? FinderItem else { return }
        open(i)
    }

    @objc private func columnDoubleClick() { selection.filter { !$0.isFolder }.forEach { NSWorkspace.shared.open($0.url) } }
    @objc private func columnClick() {
        if let f = selection.first(where: \.isFolder) { chrome?.title = FinderItem.displayName(f.url) }
    }

    enum Action { case newFolder, rename, duplicate, trash, revealInFinder }

    private func perform(_ a: Action) {
        let fm = FileManager.default
        switch a {
        case .newFolder:
            guard searching == nil else { return }
            let url = FinderItem.unusedURL(in: current, base: "untitled folder", ext: "")
            do { try fm.createDirectory(at: url, withIntermediateDirectories: false) } catch { report(error); return }
            reload()
        case .rename:
            guard let item = selection.first else { NSSound.beep(); return }
            rename(item)
        case .duplicate:
            for item in selection {
                let base = item.url.deletingPathExtension().lastPathComponent + " copy"
                let to = FinderItem.unusedURL(in: item.url.deletingLastPathComponent(), base: base, ext: item.url.pathExtension)
                do { try fm.copyItem(at: item.url, to: to) } catch { report(error) }
            }
            reload()
        case .trash:
            let urls = selection.map(\.url)
            guard !urls.isEmpty else { NSSound.beep(); return }
            NSWorkspace.shared.recycle(urls) { [weak self] _, error in
                if let error { self?.report(error) }
                if let self, self.searching != nil { self.items.removeAll { urls.contains($0.url) } }
                self?.reload()
            }
        case .revealInFinder:
            let urls = selection.map(\.url)
            NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [current] : urls)
        }
    }

    private func rename(_ item: FinderItem) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = "Rename \u{201C}\(item.name)\u{201D}"
        let field = NSTextField(string: item.url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: panel) { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains("/"), name != item.url.lastPathComponent else { return }
            let to = item.url.deletingLastPathComponent().appendingPathComponent(name)
            do { try FileManager.default.moveItem(at: item.url, to: to) } catch { self?.report(error); return }
            self?.reload()
        }
    }

    private func report(_ error: Error) {
        guard let panel else { return }
        NSAlert(error: error).beginSheetModal(for: panel)
    }

    // MARK: - Keys (Finder 10.4's)

    private func handleKey(_ e: NSEvent) -> Bool {
        if panel?.firstResponder is NSText { return false }   // typing in the search field or a sheet
        let cmd = e.modifierFlags.contains(.command)
        let ch = e.charactersIgnoringModifiers ?? ""
        switch (cmd, e.keyCode) {
        case (true, 126): goUp(); return true                         // ⌘↑
        case (true, 125): openSelection(); return true                // ⌘↓
        case (true, 51): perform(.trash); return true                 // ⌘⌫
        case (false, 36), (false, 76): perform(.rename); return true  // Return
        default: break
        }
        guard cmd else { return false }
        switch ch {
        case "1": setMode(.icons)
        case "2": setMode(.list)
        case "3": setMode(.columns)
        case "[": goBack()
        case "]": goForward()
        case "o": openSelection()
        case "d": perform(.duplicate)
        case "N": perform(.newFolder)   // ⇧⌘N; the shift is in the character
        case "f": panel?.makeFirstResponder(search)
        case "w": close()
        default: return false
        }
        return true
    }
}

// MARK: - Icon view

extension TigerFinder: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }
    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = cv.makeItem(withIdentifier: FinderIconCell.id, for: indexPath)
        (cell as? FinderIconCell)?.show(items[indexPath.item])
        return cell
    }
}

// MARK: - List view

extension TigerFinder: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? FinderItem else { return items.count }
        return item.loadedChildren.count
    }
    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? FinderItem else { return items[index] }
        return item.loadedChildren[index]
    }
    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        searching == nil && (item as? FinderItem)?.isFolder == true
    }
    func outlineView(_ ov: NSOutlineView, viewFor col: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? FinderItem, let col else { return nil }
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: "")
        text.font = .systemFont(ofSize: 11)
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text); cell.textField = text
        var leading = text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2)
        switch col.identifier.rawValue {
        case "name":
            let img = NSImageView(image: item.icon)
            img.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(img); cell.imageView = img
            NSLayoutConstraint.activate([img.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                                         img.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                         img.widthAnchor.constraint(equalToConstant: 16), img.heightAnchor.constraint(equalToConstant: 16)])
            leading = text.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 4)
            text.stringValue = item.name
        case "date": text.stringValue = item.modified.map { Self.dateFormat.string(from: $0) } ?? "--"
        case "size": text.stringValue = item.isFolder ? "--" : item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--"
        default: text.stringValue = item.kind
        }
        NSLayoutConstraint.activate([leading, text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                                     text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    func outlineView(_ ov: NSOutlineView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
        guard let d = ov.sortDescriptors.first, let key = d.key else { return }
        items = FinderItem.sorted(items, by: key, ascending: d.ascending)
        ov.reloadData()
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f
    }()
}

// MARK: - Column view

extension TigerFinder: NSBrowserDelegate {
    func rootItem(for browser: NSBrowser) -> Any? { FinderItem(url: current) }
    func browser(_ b: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? FinderItem)?.loadedChildren.count ?? 0
    }
    func browser(_ b: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        (item as! FinderItem).loadedChildren[index]
    }
    func browser(_ b: NSBrowser, isLeafItem item: Any?) -> Bool { (item as? FinderItem)?.isFolder != true }
    /// The small icon rides in front of the name: the item-based browser never asks to dress a cell.
    func browser(_ b: NSBrowser, objectValueForItem item: Any?) -> Any? {
        guard let item = item as? FinderItem else { return nil }
        let img = item.icon.copy() as! NSImage
        img.size = NSSize(width: 16, height: 16)
        let pic = NSTextAttachment(); pic.image = img
        pic.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
        let s = NSMutableAttributedString(attachment: pic)
        s.append(NSAttributedString(string: "  " + item.name, attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        return s
    }
}

// MARK: - The window and its parts

/// Borderless, key-taking: the keys and the search field need it.
final class FinderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The window's content: toolbar, sidebar, the three views, status line, all in metal.
final class FinderView: NSView {
    let toolbar = FinderToolbar(frame: .zero)
    let sidebar = FinderSidebar(frame: .zero)
    let icons = FinderIconView(frame: .zero)
    let list = NSOutlineView(frame: .zero)
    let columns = NSBrowser(frame: .zero)
    let status = NSTextField(labelWithString: "")
    private let iconScroll = NSScrollView(), listScroll = NSScrollView()
    private let sideScroll = NSScrollView()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 136, height: 100)   // 10.4's roomy grid
        layout.minimumInteritemSpacing = 6; layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        icons.collectionViewLayout = layout
        icons.isSelectable = true; icons.allowsMultipleSelection = true
        icons.backgroundColors = [.white]
        icons.register(FinderIconCell.self, forItemWithIdentifier: FinderIconCell.id)
        iconScroll.documentView = icons

        for (id, title, w) in [("name", "Name", 220.0), ("date", "Date Modified", 140.0), ("size", "Size", 64.0), ("kind", "Kind", 120.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = w
            c.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            list.addTableColumn(c)
            if id == "name" { list.outlineTableColumn = c }
        }
        list.rowHeight = 18
        list.usesAlternatingRowBackgroundColors = true   // Tiger's list: white and pale blue
        list.allowsMultipleSelection = true
        list.style = .plain
        listScroll.documentView = list
        listScroll.hasVerticalScroller = true; iconScroll.hasVerticalScroller = true

        columns.separatesColumns = true
        columns.takesTitleFromPreviousColumn = false
        columns.hasHorizontalScroller = true
        columns.setCellClass(NSBrowserCell.self)
        columns.allowsMultipleSelection = true
        columns.minColumnWidth = 180
        columns.isTitled = false

        sideScroll.documentView = sidebar
        sideScroll.hasVerticalScroller = true
        status.font = .systemFont(ofSize: 11)
        status.alignment = .center
        status.textColor = NSColor(white: 0.15, alpha: 1)

        for v in [toolbar, sideScroll, iconScroll, listScroll, columns, status] as [NSView] { addSubview(v) }
        for s in [sideScroll, iconScroll, listScroll] { s.borderType = .lineBorder; s.drawsBackground = true; s.backgroundColor = .white }
        columns.wantsLayer = true
        columns.layer?.borderColor = NSColor(white: 0.45, alpha: 1).cgColor
        columns.layer?.borderWidth = 1
        layoutParts()
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ m: TigerFinder.Mode) {
        iconScroll.isHidden = m != .icons
        listScroll.isHidden = m != .list
        columns.isHidden = m != .columns
    }

    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); layoutParts() }

    private func layoutParts() {
        let b = bounds, top: CGFloat = 38, bottom: CGFloat = 20, side: CGFloat = 150
        toolbar.frame = NSRect(x: 0, y: 0, width: b.width, height: top)
        sideScroll.frame = NSRect(x: 6, y: top, width: side, height: b.height - top - bottom)
        let main = NSRect(x: side + 10, y: top, width: b.width - side - 16, height: b.height - top - bottom)
        iconScroll.frame = main; listScroll.frame = main; columns.frame = main
        status.frame = NSRect(x: 0, y: b.height - bottom + 3, width: b.width, height: 15)
        sidebar.frame.size.width = sideScroll.contentSize.width
        sidebar.tableColumns.first?.width = sideScroll.contentSize.width - 4
    }

    /// The metal under everything: the title bar's profile, carried down the window.
    override func draw(_ dirtyRect: NSRect) {
        let profile = AquaChrome.metalProfile
        let colours = profile.map { NSColor(srgbRed: CGFloat($0.0) / 255, green: CGFloat($0.0) / 255, blue: CGFloat($0.0) / 255, alpha: 1) }
        NSGradient(colors: colours, atLocations: profile.map(\.1), colorSpace: .sRGB)?.draw(in: bounds, angle: 0)
    }
}

/// Back/Forward, the three views, the action menu and the search field, as 10.4 drew them.
final class FinderToolbar: NSView {
    var onBack: (() -> Void)?, onForward: (() -> Void)?
    var onMode: ((TigerFinder.Mode) -> Void)?
    var onAction: ((TigerFinder.Action) -> Void)?
    var onSearch: ((String) -> Void)?
    let search = NSSearchField()
    private let nav = MetalSegments(glyphs: [.back, .forward], label: "Back and Forward")
    private let views = MetalSegments(glyphs: [.icons, .list, .columns], label: "View")
    private let action = MetalSegments(glyphs: [.gear], label: "Action")
    private let actionMenu = NSMenu()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        nav.onPick = { [weak self] i in i == 0 ? self?.onBack?() : self?.onForward?() }
        views.selectable = true
        views.onPick = { [weak self] i in TigerFinder.Mode(rawValue: i).map { self?.onMode?($0) } }
        views.toolTips = ["Icons", "List", "Columns"]
        for (t, a) in [("New Folder", TigerFinder.Action.newFolder), ("Rename\u{2026}", .rename), ("Duplicate", .duplicate),
                       ("Move to Trash", .trash), ("Show in the Mac\u{2019}s Finder", .revealInFinder)] {
            let item = NSMenuItem(title: t, action: #selector(actionPick(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = a
            actionMenu.addItem(item)
        }
        action.onPick = { [weak self] _ in
            guard let self else { return }
            self.actionMenu.popUp(positioning: nil, at: NSPoint(x: self.action.frame.minX, y: self.action.frame.maxY + 2), in: self)
        }
        search.target = self; search.action = #selector(searchChange)
        search.sendsSearchStringImmediately = false
        search.sendsWholeSearchString = true
        search.controlSize = .small
        for v in [nav, views, action, search] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func setFrameSize(_ s: NSSize) {
        super.setFrameSize(s)
        nav.frame = NSRect(x: 9, y: 8, width: 52, height: 23)
        views.frame = NSRect(x: 70, y: 8, width: 80, height: 23)
        action.frame = NSRect(x: 159, y: 8, width: 45, height: 23)
        search.frame = NSRect(x: max(220, s.width - 186), y: 9, width: 176, height: 21)
    }

    func setNav(back: Bool, forward: Bool) { nav.enabled = [back, forward] }
    func setMode(_ m: TigerFinder.Mode) { views.selected = m.rawValue }

    @objc private func actionPick(_ i: NSMenuItem) { (i.representedObject as? TigerFinder.Action).map { onAction?($0) } }
    @objc private func searchChange() { onSearch?(search.stringValue) }
}

/// 10.4's toolbar button: a rounded rectangle, glossy white over light grey, a grey rim, the
/// segments split by fine lines, the chosen one pale Aqua blue. The glyphs are drawn, small and
/// black (grey when the segment cannot be used), as Tiger's were.
final class MetalSegments: NSView {
    enum Glyph { case back, forward, icons, list, columns, gear }
    let glyphs: [Glyph]
    var selectable = false
    var selected: Int? { didSet { needsDisplay = true } }
    var enabled: [Bool] { didSet { needsDisplay = true } }
    var toolTips: [String] = [] { didSet { updateToolTips() } }
    var onPick: ((Int) -> Void)?
    private var pressed: Int?

    init(glyphs: [Glyph], label: String) {
        self.glyphs = glyphs
        enabled = glyphs.map { _ in true }
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    private func segment(_ i: Int) -> NSRect {
        let w = bounds.width / CGFloat(glyphs.count)
        return NSRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height)
    }
    private func updateToolTips() {
        removeAllToolTips()
        for (i, t) in toolTips.enumerated() where i < glyphs.count { addToolTip(segment(i), owner: t as NSString, userData: nil) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
        func gloss(_ c: [Int]) -> NSGradient? {
            NSGradient(colors: c.map { NSColor(srgbRed: CGFloat($0 >> 16) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1) },
                       atLocations: [0, 0.5, 0.5, 1], colorSpace: .sRGB)
        }
        gloss([0xFFFFFF, 0xF1F1F1, 0xE2E2E2, 0xF5F5F5])?.draw(in: shape, angle: 90)
        for i in glyphs.indices where i == selected || i == pressed {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            let colours = i == pressed && i != selected ? [0xD4D4D4, 0xC6C6C6, 0xB8B8B8, 0xCDCDCD] : [0xD9ECFC, 0xACD2F8, 0x8FC0F3, 0xBDDFFB]
            gloss(colours)?.draw(in: segment(i), angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(white: 0.6, alpha: 1).setFill()
        for i in 1..<max(1, glyphs.count) { NSRect(x: segment(i).minX, y: 1, width: 1, height: bounds.height - 2).fill() }
        NSColor(white: 0.52, alpha: 1).setStroke()
        shape.lineWidth = 1; shape.stroke()
        for (i, g) in glyphs.enumerated() { draw(g, in: segment(i), on: enabled[i]) }
    }

    private func draw(_ g: Glyph, in r: NSRect, on: Bool) {
        (on ? NSColor(white: 0.1, alpha: 1) : NSColor(white: 0.62, alpha: 1)).set()
        let c = NSPoint(x: r.midX.rounded(), y: r.midY.rounded())
        switch g {
        case .back, .forward:
            let d: CGFloat = g == .back ? -1 : 1, p = NSBezierPath()
            p.move(to: NSPoint(x: c.x + 4 * d, y: c.y)); p.line(to: NSPoint(x: c.x - 4 * d, y: c.y - 5)); p.line(to: NSPoint(x: c.x - 4 * d, y: c.y + 5))
            p.close(); p.fill()
        case .icons:
            for dx in [-4.0, 2.0] { for dy in [-4.0, 2.0] { NSBezierPath(rect: NSRect(x: c.x + dx, y: c.y + dy, width: 3, height: 3)).stroke() } }
        case .list:
            for dy in [-4.5, -1.5, 1.5, 4.5] { NSRect(x: c.x - 7, y: c.y + dy - 0.5, width: 14, height: 1.2).fill() }
        case .columns:
            let box = NSRect(x: c.x - 8, y: c.y - 5.5, width: 16, height: 11)
            NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)).stroke()
            for x in [box.minX + 5.5, box.minX + 10.5] { NSRect(x: x, y: box.minY, width: 1, height: box.height).fill() }
        case .gear:
            if let gear = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) {
                let tinted = NSImage(size: gear.size, flipped: false) { rr in
                    gear.draw(in: rr); (on ? NSColor(white: 0.15, alpha: 1) : NSColor.gray).set(); rr.fill(using: .sourceAtop); return true
                }
                tinted.draw(in: NSRect(x: c.x - 11, y: c.y - gear.size.height / 2, width: gear.size.width, height: gear.size.height))
            }
            let t = NSBezierPath()
            t.move(to: NSPoint(x: c.x + 6, y: c.y - 1)); t.line(to: NSPoint(x: c.x + 12, y: c.y - 1)); t.line(to: NSPoint(x: c.x + 9, y: c.y + 2.5))
            t.close(); t.fill()
        }
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let i = glyphs.indices.first(where: { segment($0).contains(p) }), enabled[i] else { return }
        pressed = i; needsDisplay = true
    }
    override func mouseUp(with e: NSEvent) {
        defer { pressed = nil; needsDisplay = true }
        guard let i = pressed, segment(i).contains(convert(e.locationInWindow, from: nil)) else { return }
        if selectable { selected = i }
        onPick?(i)
    }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); updateToolTips() }
}

/// The places down the left: the startup disk, then the folders of the home.
final class FinderSidebar: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
    var onPick: ((URL) -> Void)?
    private let places: [(String, URL, String)?]

    override init(frame: NSRect) {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        func dir(_ d: FileManager.SearchPathDirectory) -> URL { fm.urls(for: d, in: .userDomainMask).first ?? home }
        // 10.4's sidebar, in its order. Network has no folder of its own any more: it shows the
        // mounted volumes, shares among them.
        places = [("Network", URL(fileURLWithPath: "/Volumes"), "network"), ("Macintosh HD", URL(fileURLWithPath: "/"), "disk"), nil,
                  ("Desktop", dir(.desktopDirectory), "desktop"), (NSUserName(), home, "home"),
                  ("Applications", URL(fileURLWithPath: "/Applications"), "applications"), ("Documents", dir(.documentDirectory), "documents"),
                  ("Movies", dir(.moviesDirectory), "movies"), ("Music", dir(.musicDirectory), "music"), ("Pictures", dir(.picturesDirectory), "pictures")]
        super.init(frame: frame)
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("place"))
        addTableColumn(c)
        headerView = nil
        columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        rowHeight = 34   // 10.4's: 32-point pictures
        dataSource = self; delegate = self
        target = self; action = #selector(pick)
        setAccessibilityLabel("Places")
        reloadData()
    }
    required init?(coder: NSCoder) { fatalError() }

    func select(_ url: URL?) {
        guard let url, let row = places.firstIndex(where: { $0?.1.standardizedFileURL == url.standardizedFileURL && $0?.2 != "network" }) else {
            deselectAll(nil); return
        }
        selectRowIndexes([row], byExtendingSelection: false)
    }

    func numberOfRows(in t: NSTableView) -> Int { places.count }
    func tableView(_ t: NSTableView, heightOfRow row: Int) -> CGFloat { places[row] == nil ? 9 : 34 }
    func tableView(_ t: NSTableView, shouldSelectRow row: Int) -> Bool { places[row] != nil }
    func tableView(_ t: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { TigerSelectionRow() }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let (name, url, picture) = places[row] else {
            let line = NSBox(); line.boxType = .separator; return line
        }
        let cell = NSTableCellView()
        let img = NSImageView(image: Self.icon(picture, for: url))
        let text = NSTextField(labelWithString: name)
        text.font = .systemFont(ofSize: 12)
        for v in [img, text] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        cell.imageView = img; cell.textField = text
        NSLayoutConstraint.activate([img.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                                     img.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                     img.widthAnchor.constraint(equalToConstant: 30), img.heightAnchor.constraint(equalToConstant: 30),
                                     text.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 5),
                                     text.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                                     text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
    @objc private func pick() {
        guard clickedRow >= 0, let (_, url, _) = places[clickedRow] else { return }
        onPick?(url)
    }

    /// 10.4's own sidebar pictures (the theme's `sidebar/` folder, cut from 10.4 screenshots);
    /// the Mac's, paled to Tiger's blue, where a theme has none.
    static func icon(_ picture: String, for url: URL) -> NSImage {
        if let u = ThemeManager.shared.activeTheme?.rootResource("sidebar/\(picture).png"), let img = NSImage(contentsOf: u) { return img }
        return FinderItem.tigerTint(NSWorkspace.shared.icon(forFile: url.path))
    }
}

/// 10.4's sidebar selection: a blue gradient the width of the row, the name in white.
final class TigerSelectionRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let r = bounds
        let top = isEmphasized ? NSColor(srgbRed: 0.42, green: 0.62, blue: 0.89, alpha: 1) : NSColor(white: 0.74, alpha: 1)
        let bottom = isEmphasized ? NSColor(srgbRed: 0.16, green: 0.40, blue: 0.80, alpha: 1) : NSColor(white: 0.58, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: r, angle: isFlipped ? 90 : -90)
        (isEmphasized ? NSColor(srgbRed: 0.33, green: 0.55, blue: 0.86, alpha: 1) : NSColor(white: 0.66, alpha: 1)).setFill()
        NSRect(x: r.minX, y: isFlipped ? r.minY : r.maxY - 1, width: r.width, height: 1).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }
}

/// The icon view: a double-click opens, which a collection view does not do by itself.
final class FinderIconView: NSCollectionView {
    var onOpen: (() -> Void)?
    override func mouseDown(with e: NSEvent) {
        super.mouseDown(with: e)
        if e.clickCount == 2, !selectionIndexPaths.isEmpty { onOpen?() }
    }
}

/// One icon: 64 points of picture over its name, the name in a pale capsule when selected.
final class FinderIconCell: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("FinderIconCell")
    private let picture = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 136, height: 100))
        picture.frame = NSRect(x: 36, y: 32, width: 64, height: 64)
        picture.imageScaling = .scaleProportionallyUpOrDown
        label.frame = NSRect(x: 4, y: 0, width: 128, height: 30)
        label.alignment = .center
        label.font = .systemFont(ofSize: 11)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.wantsLayer = true
        label.layer?.cornerRadius = 7
        view.addSubview(picture); view.addSubview(label)
        imageView = picture; textField = label
    }

    func show(_ item: FinderItem) {
        picture.image = item.icon
        label.stringValue = item.name
        view.setAccessibilityLabel(item.name)
        updateSelection()
    }

    override var isSelected: Bool { didSet { updateSelection() } }
    private func updateSelection() {
        label.layer?.backgroundColor = isSelected ? NSColor(srgbRed: 0.22, green: 0.46, blue: 0.84, alpha: 1).cgColor : nil
        label.textColor = isSelected ? .white : .black
        picture.layer?.backgroundColor = nil
    }
}

// MARK: - The file model

/// One file or folder, read once with the properties the views show.
final class FinderItem: NSObject {
    let url: URL
    let name: String
    let isFolder: Bool
    let size: Int64?
    let modified: Date?
    let kind: String
    private var cachedChildren: [FinderItem]?

    init(url: URL) {
        self.url = url
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey,
                                                  .localizedTypeDescriptionKey, .localizedNameKey])
        isFolder = v?.isDirectory == true && v?.isPackage != true
        name = v?.localizedName ?? url.lastPathComponent
        size = v?.fileSize.map(Int64.init)
        modified = v?.contentModificationDate
        kind = v?.localizedTypeDescription ?? ""
        super.init()
    }

    /// An app wears the theme's picture of it (Tiger's Safari, Mail…); the rest the Mac's.
    lazy var icon: NSImage = {
        if url.pathExtension == "app", let id = Bundle(url: url)?.bundleIdentifier,
           let u = ThemeManager.shared.activeTheme?.iconURL(for: id), let img = NSImage(contentsOf: u) { return img }
        let mac = NSWorkspace.shared.icon(forFile: url.path)
        return isFolder ? Self.tigerTint(mac) : mac
    }()

    /// shortcut: Tiger's own folder pictures are not among the theme's assets, so today's
    /// folders are paled to 10.4's light translucent blue; replace with the real icons when there.
    static func tigerTint(_ img: NSImage) -> NSImage {
        guard let tiff = img.tiffRepresentation, let ci = CIImage(data: tiff),
              let f = CIFilter(name: "CIColorControls") else { return img }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(0.55, forKey: kCIInputSaturationKey)
        f.setValue(0.18, forKey: kCIInputBrightnessKey)
        guard let pale = f.outputImage, let hue = CIFilter(name: "CIHueAdjust") else { return img }
        hue.setValue(pale, forKey: kCIInputImageKey)
        hue.setValue(-0.28, forKey: kCIInputAngleKey)   // from today's violet-blue toward 10.4's sky blue
        guard let out = hue.outputImage else { return img }
        let rep = NSCIImageRep(ciImage: out)
        let tinted = NSImage(size: img.size); tinted.addRepresentation(rep)
        return tinted
    }

    var loadedChildren: [FinderItem] {
        if cachedChildren == nil { cachedChildren = Self.children(of: url) }
        return cachedChildren ?? []
    }

    /// A folder's visible contents, sorted the way Finder sorts names. Unreadable → empty.
    static func children(of url: URL) -> [FinderItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey, .localizedNameKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return sorted(urls.map(FinderItem.init), by: "name", ascending: true)
    }

    static func sorted(_ items: [FinderItem], by key: String, ascending: Bool) -> [FinderItem] {
        let s = items.sorted { a, b in
            switch key {
            case "date": return (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            case "size": return (a.size ?? -1) < (b.size ?? -1)
            case "kind": return a.kind.localizedStandardCompare(b.kind) == .orderedAscending
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        return ascending ? s : s.reversed()
    }

    static func displayName(_ url: URL) -> String {
        url.path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: url.path)
    }

    /// "untitled folder", "untitled folder 2"… — the first name not taken in `dir`.
    static func unusedURL(in dir: URL, base: String, ext: String) -> URL {
        func make(_ n: String) -> URL { ext.isEmpty ? dir.appendingPathComponent(n) : dir.appendingPathComponent(n).appendingPathExtension(ext) }
        var u = make(base), i = 2
        while FileManager.default.fileExists(atPath: u.path) { u = make("\(base) \(i)"); i += 1 }
        return u
    }
}
