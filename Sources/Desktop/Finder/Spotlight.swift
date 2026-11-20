import AppKit

/// Asks the Mac's own Spotlight index (`NSMetadataQuery`) for files whose names contain the
/// text, and sorts what comes back into Tiger's groups. One search at a time: a new `run`
/// stops the last, and an answer that arrives for a search already replaced is dropped, so a
/// fast typist never sees the results for the letters before.
final class SpotlightSearch: NSObject {
    struct Hit { let url: URL; let name: String }
    struct Group { let name: String; var items: [Hit] }

    /// Tiger's order of the groups in its menu.
    static let order = ["Applications", "System Preferences", "Documents", "Folders", "Images",
                        "PDF Documents", "Movies", "Music", "Other"]

    private var query: NSMetadataQuery?
    private var token: NSObjectProtocol?
    private var generation = 0

    /// `done` runs on the main thread, once, unless another `run` or `cancel` comes first.
    func run(_ text: String, limit: Int, done: @escaping ([Group]) -> Void) {
        cancel()
        generation += 1
        let mine = generation
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemDisplayNameKey, "*\(text)*")
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        token = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            guard let self, self.generation == mine else { return }
            q.disableUpdates()
            let groups = Self.group((0..<min(q.resultCount, limit)).compactMap { q.result(at: $0) as? NSMetadataItem })
            self.cancel()
            done(groups)
        }
        query = q
        if !q.start() { cancel(); done([]) }
    }

    func cancel() {
        query?.stop()
        if let t = token { NotificationCenter.default.removeObserver(t) }
        query = nil; token = nil
    }

    static func group(_ items: [NSMetadataItem]) -> [Group] {
        var byName: [String: [Hit]] = [:]
        for i in items {
            guard let path = i.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let name = (i.value(forAttribute: NSMetadataItemDisplayNameKey) as? String) ?? (path as NSString).lastPathComponent
            let tree = (i.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String]) ?? []
            byName[category(tree), default: []].append(Hit(url: URL(fileURLWithPath: path), name: name))
        }
        return order.compactMap { n in byName[n].map { Group(name: n, items: $0) } }
    }

    static func category(_ tree: [String]) -> String {
        if tree.contains("com.apple.application") { return "Applications" }
        if tree.contains("com.apple.systempreference.prefpane") { return "System Preferences" }
        if tree.contains("public.folder") { return "Folders" }
        if tree.contains("com.adobe.pdf") { return "PDF Documents" }
        if tree.contains("public.image") { return "Images" }
        if tree.contains("public.movie") { return "Movies" }
        if tree.contains("public.audio") { return "Music" }
        if tree.contains("public.content") || tree.contains("public.text") { return "Documents" }
        return "Other"
    }
}

/// Tiger's Spotlight: the blue magnifier at the right of the menu bar. A click drops the menu
/// with the search field; typing fills it with the Top Hit and the groups, the arrows move, Return
/// opens, Escape closes. "Show All" opens the Finder's search window. Themes turn it on with
/// `"menuBar": { "spotlight": true }`. It has no shortcut: ⌘Space is the Mac's own Spotlight.
final class SpotlightMenuController: NSObject {
    static let shared = SpotlightMenuController()
    private var item: NSStatusItem?
    private var panel: SpotlightPanel?

    func update() {
        guard AppSettings.shared.dockEnabled, !AppSettings.shared.hideMenuBar,
              ThemeManager.shared.activeTheme?.config.menuBar?.spotlight == true else { hide(); return }
        guard item == nil else { return }
        // Tiger's Spotlight sat at the far right. macOS keeps a status item's place under its
        // autosave name, counted from the right edge: the first time, ask for the rightmost
        // place it gives an app (left of the clock and Control Center, which are the system's);
        // a ⌘-drag later is the user's and stays.
        let name = "RetroMacSpotlight", key = "NSStatusItem Preferred Position \(name)"
        if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(1, forKey: key) }
        let i = NSStatusBar.system.statusItem(withLength: 26)
        i.autosaveName = name
        i.button?.image = Self.magnifier
        i.button?.target = self
        i.button?.action = #selector(toggle)
        i.button?.setAccessibilityLabel("Spotlight")
        item = i
    }

    func hide() {
        panel?.close(); panel = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func toggle() {
        if let p = panel { p.close(); panel = nil; return }
        guard let button = item?.button, let win = button.window else { return }
        show(below: win.convertToScreen(button.convert(button.bounds, to: nil)))
    }

    /// The search field under `anchor` (right-aligned to it), or in the upper middle of the main
    /// screen without one: XP's Start ▸ Search opens it with no menu-bar item to hang from.
    func show(below anchor: NSRect? = nil) {
        panel?.close()
        let p = SpotlightPanel()
        p.onClose = { [weak self] in self?.panel = nil }
        if let anchor {
            p.setFrameTopLeftPoint(NSPoint(x: anchor.maxX - p.frame.width, y: anchor.minY - 1))
        } else if let vf = NSScreen.main?.visibleFrame {
            p.setFrameTopLeftPoint(NSPoint(x: vf.midX - p.frame.width / 2, y: vf.maxY - vf.height / 4))
        }
        panel = p
        p.makeKeyAndOrderFront(nil)
    }

    /// The blue disc with the white glass, as 10.4 drew it.
    static let magnifier: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let disc = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            NSGradient(colors: [NSColor(srgbRed: 0.45, green: 0.68, blue: 1, alpha: 1),
                                NSColor(srgbRed: 0.08, green: 0.36, blue: 0.86, alpha: 1)])?.draw(in: disc, angle: -90)
            NSColor.white.setStroke()
            let glass = NSBezierPath(ovalIn: NSRect(x: 5, y: 7, width: 6.5, height: 6.5))
            glass.lineWidth = 1.6; glass.stroke()
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 10.5, y: 7.5)); handle.line(to: NSPoint(x: 13.5, y: 4.5))
            handle.lineWidth = 2; handle.lineCapStyle = .round; handle.stroke()
            return true
        }
        img.isTemplate = false
        return img
    }()
}

/// The dropped menu: the field on a blue band, the rows under it.
final class SpotlightPanel: NSPanel, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onClose: (() -> Void)?
    private let field = NSSearchField()
    private let table = NSTableView()
    private let engine = SpotlightSearch()
    private var rows: [Row] = []
    private var pending: DispatchWorkItem?
    private var resignToken: NSObjectProtocol?

    enum Row { case showAll(Int), hit(group: String?, SpotlightSearch.Hit), searching, none }

    override var canBecomeKey: Bool { true }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 40), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 40))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 1, alpha: 0.97).cgColor
        root.layer?.cornerRadius = 4
        let band = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 40))
        band.wantsLayer = true
        band.layer?.backgroundColor = NSColor(srgbRed: 0.84, green: 0.89, blue: 0.97, alpha: 1).cgColor
        band.autoresizingMask = [.minYMargin, .width]
        let title = NSTextField(labelWithString: "Spotlight")
        title.font = .boldSystemFont(ofSize: 13)
        title.frame = NSRect(x: 12, y: 11, width: 76, height: 18)
        field.frame = NSRect(x: 88, y: 9, width: 260, height: 22)
        field.delegate = self
        field.setAccessibilityLabel("Spotlight")
        band.addSubview(title); band.addSubview(field)
        let scroll = NSScrollView(frame: .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        table.addTableColumn(col)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 20
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(click)
        scroll.documentView = table
        root.addSubview(scroll); root.addSubview(band)
        contentView = root
        resignToken = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
            self?.close()
        }
        makeFirstResponder(field)
    }

    override func close() {
        engine.cancel(); pending?.cancel()
        if let t = resignToken { NotificationCenter.default.removeObserver(t) }
        resignToken = nil
        super.close()
        onClose?(); onClose = nil
    }

    // MARK: Typing

    func controlTextDidChange(_ n: Notification) {
        pending?.cancel()
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { engine.cancel(); setRows([]); return }
        setRows([.searching])
        let w = DispatchWorkItem { [weak self] in
            self?.engine.run(text, limit: 200) { groups in self?.show(groups) }
        }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): openSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)): close(); return true
        default: return false
        }
    }

    /// The menu shows the Top Hit and at most five of each group, as 10.4's did.
    private func show(_ groups: [SpotlightSearch.Group]) {
        let total = groups.reduce(0) { $0 + $1.items.count }
        guard total > 0 else { setRows([.none]); return }
        var r: [Row] = [.showAll(total)]
        let top = groups.first!.items.first!
        r.append(.hit(group: "Top Hit", top))
        for g in groups {
            for (k, h) in g.items.prefix(5).enumerated() where h.url != top.url {
                r.append(.hit(group: k == 0 ? g.name : nil, h))
            }
        }
        setRows(r)
        if let i = rows.firstIndex(where: { if case .hit = $0 { return true }; return false }) {
            table.selectRowIndexes([i], byExtendingSelection: false)
        }
        NSAccessibility.post(element: table, notification: .announcementRequested,
                             userInfo: [.announcement: "\(total) results", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func setRows(_ r: [Row]) {
        rows = r
        table.reloadData()
        let h = 40 + CGFloat(min(r.count, 22)) * table.rowHeight + (r.isEmpty ? 0 : 8)
        var f = frame
        f.origin.y += f.height - h; f.size.height = h
        setFrame(f, display: true)
        contentView?.subviews.first?.frame = NSRect(x: 0, y: 4, width: f.width, height: h - 44)
    }

    private func move(_ d: Int) {
        guard !rows.isEmpty else { return }
        var i = table.selectedRow + d
        while i >= 0, i < rows.count, !isSelectable(i) { i += d }
        guard i >= 0, i < rows.count else { return }
        table.selectRowIndexes([i], byExtendingSelection: false)
        table.scrollRowToVisible(i)
    }

    private func isSelectable(_ i: Int) -> Bool {
        switch rows[i] { case .hit, .showAll: return true; default: return false }
    }

    @objc private func click() { openSelected(table.clickedRow) }

    private func openSelected(_ row: Int? = nil) {
        let i = row ?? table.selectedRow
        guard i >= 0, i < rows.count else { return }
        let text = field.stringValue
        switch rows[i] {
        case .hit(_, let h): close(); NSWorkspace.shared.open(h.url)
        case .showAll:
            close()
            if TigerFinder.isEnabled { TigerFinder.showSearch(text) }
        default: break
        }
    }

    // MARK: Rows

    func numberOfRows(in t: NSTableView) -> Int { rows.count }
    func tableView(_ t: NSTableView, shouldSelectRow row: Int) -> Bool { isSelectable(row) }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSView()
        let label = NSTextField(labelWithString: ""), group = NSTextField(labelWithString: "")
        group.alignment = .right
        group.textColor = .secondaryLabelColor
        group.font = .systemFont(ofSize: 11)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        group.frame = NSRect(x: 0, y: 2, width: 110, height: 16)
        label.frame = NSRect(x: 140, y: 2, width: 210, height: 16)
        cell.addSubview(group); cell.addSubview(label)
        switch rows[row] {
        case .showAll(let n): label.stringValue = "Show All (\(n))"; label.font = .boldSystemFont(ofSize: 12)
        case .searching: label.stringValue = "Searching\u{2026}"; label.textColor = .secondaryLabelColor
        case .none: label.stringValue = "No results"; label.textColor = .secondaryLabelColor
        case .hit(let g, let h):
            group.stringValue = g ?? ""
            label.stringValue = h.name
            let img = NSImageView(frame: NSRect(x: 118, y: 2, width: 16, height: 16))
            img.image = NSWorkspace.shared.icon(forFile: h.url.path)
            cell.addSubview(img)
            cell.setAccessibilityLabel((g.map { $0 + ": " } ?? "") + h.name)
        }
        return cell
    }
}
