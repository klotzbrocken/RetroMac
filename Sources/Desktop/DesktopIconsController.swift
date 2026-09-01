import AppKit
import Combine
import UniformTypeIdentifiers

/// Manages a transparent overlay window that displays theme-defined desktop icons
/// (Trash, app shortcuts, folders) arranged in a classic grid on the desktop.
final class DesktopIconsController {

    static let shared = DesktopIconsController()

    private var window: NSPanel?
    private var iconViews: [DesktopIconView] = []
    private var isVisible = false
    private var trashObserver: Any?
    private var screenObserver: Any?
    private var trashPollTimer: Timer?
    private var custom = DesktopStore.ThemeCustom()
    /// Storage key for everything this controller persists per theme (desktop layout via
    /// `DesktopStore`, wallpaper overrides). This is the theme's stable id, not its display name,
    /// so renaming a theme keeps its desktop arrangement — see `DockThemeConfig.settingsKey`.
    private var themeName: String { ThemeManager.shared.activeTheme?.config.settingsKey ?? "?" }

    // Computed grid layout — the dock leads (unless the desktop slider is unlocked).
    private var iconSize: CGFloat {
        let scale = CGFloat(AppSettings.shared.effectiveDesktopIconScale)
        let cfg = ThemeManager.shared.activeTheme?.config
        // An explicit per-theme desktop size wins (e.g. Win98's 40); otherwise desktop
        // icons match the theme's DOCK icon size so they're identical. Either way the
        // icon-size slider (dockIconScale) applies — the old fixed 64/48 ignored it.
        if let s = cfg?.desktopIconSize, s > 8 { return s * scale }
        if let dockSize = cfg?.dock.iconSize, dockSize > 8 { return dockSize * scale }
        let bs = NSScreen.main?.backingScaleFactor ?? 2.0
        return (bs >= 2.0 ? 64 : 48) * scale
    }
    private var cellWidth: CGFloat { iconSize + 46 }      // breathing room between columns (fits longer labels like "My Computer")
    /// Windows stacks its desktop icons down the left edge, the Mac down the right.
    private var iconsFromLeft: Bool {
        ThemeManager.shared.activeTheme?.config.desktopIconsSide == "left"
    }
    private var cellHeight: CGFloat { iconSize + 66 }     // … and between rows (2-line labels + a comfortable gap)
    private var marginX: CGFloat { 16 }
    private var marginY: CGFloat { 8 }
    private var scaleObserver: AnyCancellable?

    private init() {
        // Desktop icons rebuild live when either the dock slider (while linked), the
        // independent desktop slider, or the link toggle changes.
        let s = AppSettings.shared
        scaleObserver = Publishers.MergeMany(
            s.$dockIconScale.map { _ in () }.eraseToAnyPublisher(),
            s.$desktopIconScale.map { _ in () }.eraseToAnyPublisher(),
            s.$desktopIconScaleLinked.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst()
        .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self = self, self.isVisible else { return }
            self.update()
        }
    }

    // MARK: - Public API

    /// Show desktop icons for the active theme (call on theme change).
    func update() {
        // Dock-only changes nothing but the dock — no themed desktop icons.
        if AppSettings.shared.dockOnly { hide(); return }
        var entries = ThemeManager.shared.activeTheme?.config.desktopIcons ?? []
        // Add a "Read Me" shortcut that opens the theme's About readme, for any theme that both
        // ships a readme.html AND shows a themed desktop (skips NeXT, whose desktop has no icons).
        if !entries.isEmpty, let theme = ThemeManager.shared.activeTheme, ThemeReadmeController.activeThemeHasReadme() {
            let col0Rows = entries.compactMap { ($0.gridX ?? 0) == 0 ? ($0.gridY ?? 0) : nil }
            var e = DockThemeConfig.DesktopIconEntry(name: "Read Me", icon: readmeIconName(for: theme), type: "readme")
            e.gridX = 0
            e.gridY = (col0Rows.max() ?? -1) + 1
            entries.append(e)
        }
        if entries.isEmpty {
            hide()
            return
        }
        show(entries: entries)
    }

    /// A period-appropriate document icon for the "Read Me" shortcut: the first of these that the
    /// active theme actually ships (SimpleText/TextEdit on Mac, Notepad on Windows, …). Empty
    /// string falls back to a generic document glyph (Amiga/SGI ship no text-document icon).
    private func readmeIconName(for theme: ThemeBundle) -> String {
        let candidates = ["simpletext.png", "textedit.png", "win7_notepad.png", "notepad98.png",
                          "notepadclassic.png", "notepad.png", "write.png", "new-text.png",
                          "document.png", "documents.png", "notes.png", "file.png"]
        let dir = theme.url.appendingPathComponent("icons")
        for c in candidates where FileManager.default.fileExists(atPath: dir.appendingPathComponent(c).path) {
            return c
        }
        return ""
    }

    /// Remove desktop icons window.
    func hide() {
        if let obs = trashObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            trashObserver = nil
        }
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        trashPollTimer?.invalidate(); trashPollTimer = nil
        window?.orderOut(nil)
        window = nil
        iconViews.removeAll()
        isVisible = false
    }

    // MARK: - Window Setup

    private func show(entries: [DockThemeConfig.DesktopIconEntry]) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame

        if window == nil {
            let panel = NSPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            // Sit just BELOW normal app windows (behind every app) but NOT at the desktop /
            // desktop-icon level: at desktop level macOS Sonoma treats a click here as a
            // "click wallpaper to reveal desktop" gesture and slides all windows off-screen.
            // A sub-normal level keeps the icons behind apps while a click is consumed as a
            // normal window click, so the reveal gesture no longer fires.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 1)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = false
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = false

            let contentView = DesktopIconsContentView(frame: NSRect(origin: .zero, size: screenFrame.size))
            contentView.wantsLayer = true
            contentView.controller = self
            panel.contentView = contentView

            self.window = panel
        }

        guard let contentView = window?.contentView else { return }
        window?.setFrame(screenFrame, display: true)
        contentView.frame = NSRect(origin: .zero, size: screenFrame.size)

        // Remove old icons
        iconViews.forEach { $0.removeFromSuperview() }
        iconViews.removeAll()

        let theme = ThemeManager.shared.activeTheme
        let isPixelated = theme?.config.isPixelated ?? false
        let iSize = iconSize

        // Apply user customizations (added shortcuts, removals, drag positions, icon overrides)
        custom = DesktopStore.load(theme: themeName)
        // When the theme's DEFAULT icon layout changes (new/renamed/re-gridded entries),
        // stale user-dragged positions would stack old and new icons on top of each
        // other — drop saved positions once and re-align to the fresh grid.
        let layoutHash = entries.map { "\($0.name):\($0.gridX ?? -1):\($0.gridY ?? -1)" }.joined(separator: "|")
        if custom.layoutHash != layoutHash {
            custom.positions.removeAll()
            custom.layoutHash = layoutHash
            DesktopStore.save(custom, theme: themeName)
        }
        let effective = entries.filter { !custom.removed.contains($0.name) } + custom.added.filter { !custom.removed.contains($0.name) }

        // Where an icon with no grid position goes. `index` was the old answer, and it put the
        // sixteenth icon on row sixteen — below the bottom of any screen. Added shortcuts now
        // take the first cell nothing else claims, walking down column 0 and then across.
        var taken = Set<[Int]>()
        for e in effective {
            if let y = e.gridY { taken.insert([e.gridX ?? 0, y]) }
        }
        let rowsPerColumn = max(4, Int((visibleFrame.height - marginY * 2) / cellHeight))
        func firstFreeCell() -> (Int, Int) {
            var col = 0
            while col < 12 {
                for row in 0..<rowsPerColumn where !taken.contains([col, row]) {
                    taken.insert([col, row])
                    return (col, row)
                }
                col += 1
            }
            return (0, 0)
        }

        let cw = cellWidth, ch = cellHeight
        for entry in effective {
            var iconImage = loadIconImage(for: entry, theme: theme, size: iSize)
            if let ov = custom.iconOverrides[entry.name], let o = NSImage(contentsOfFile: ov) { iconImage = o }
            let fullImage: NSImage? = (entry.type == "trash" && entry.iconFull != nil)
                ? loadIconImageByName(entry.iconFull!, theme: theme, size: iSize) : nil

            let view = DesktopIconView(entry: entry, image: iconImage, fullImage: fullImage,
                                       iconSize: iSize, isPixelated: isPixelated)
            view.target = self
            view.action = #selector(iconDoubleClicked(_:))
            view.onMoved = { [weak self] v in self?.iconMoved(v) }
            view.onContextMenu = { [weak self] v, e in self?.showIconMenu(v, e) }

            if let pos = custom.positions[entry.name] {
                view.frame = NSRect(x: pos[0], y: pos[1], width: cw, height: ch)
            } else {
                let placed: (col: Int, row: Int)
                if let y = entry.gridY {
                    placed = (entry.gridX ?? 0, y)
                } else {
                    let free = firstFreeCell()
                    placed = (free.0, free.1)
                }
                let col = placed.col
                let row = placed.row
                let x = iconsFromLeft
                    ? visibleFrame.minX + marginX + (CGFloat(col) * cw) - screenFrame.origin.x
                    : visibleFrame.maxX - marginX - cw - (CGFloat(col) * cw) - screenFrame.origin.x
                let y = visibleFrame.maxY - marginY - ch - (CGFloat(row) * ch) - screenFrame.origin.y
                view.frame = NSRect(x: x, y: y, width: cw, height: ch)
            }
            contentView.addSubview(view)
            iconViews.append(view)
        }

        // Observe trash changes + poll periodically (notification can be unreliable)
        if trashObserver == nil {
            trashObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.finder.trashdirectory.changed"),
                object: nil, queue: .main
            ) { [weak self] _ in self?.updateTrashState() }
            trashPollTimer?.invalidate()
            trashPollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
                self?.updateTrashState()
            }
            updateTrashState()
        }
        // Re-frame + rebuild when the display configuration changes. On a headless Mac (e.g.
        // Mac mini with one external 1080p monitor) the screen's final frame is sometimes
        // reported a beat after launch/wake; without this the panel keeps a stale frame,
        // showing a transparent border around the desktop and icons that only paint after a
        // click forces a redraw.
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                guard let self = self, self.isVisible else { return }
                self.update()
            }
        }
        // Always refresh after a (re)build so a freshly created trash icon (e.g. after a
        // theme switch) immediately reflects full/empty instead of waiting for the next poll.
        updateTrashState()

        window?.orderFront(nil)
        window?.displayIfNeeded()   // paint immediately — don't wait for a desktop click
        isVisible = true
    }

    // MARK: - Trash State

    private func updateTrashState() {
        // ~/.Trash is TCC-gated on modern macOS, so compute off-main (direct read with Full
        // Disk Access, else Finder's item count via AppleScript) and update the icon on main.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let hasItems = !DesktopIconsController.trashEmpty()
            DispatchQueue.main.async {
                guard let self = self else { return }
                for view in self.iconViews where view.entry.type == "trash" {
                    view.setTrashFull(hasItems)
                }
            }
        }
    }

    private static func trashEmpty() -> Bool {
        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first,
           let contents = try? FileManager.default.contentsOfDirectory(atPath: trashURL.path) {
            return !contents.contains(where: { !$0.hasPrefix(".") })
        }
        guard let script = NSAppleScript(source: "tell application \"Finder\" to return (count of items of trash)") else { return true }
        var err: NSDictionary?
        let r = script.executeAndReturnError(&err)
        return err == nil ? (Int(r.int32Value) == 0) : true
    }

    /// Deselect all desktop icons (called when clicking on empty area).
    func deselectAll() {
        for view in iconViews {
            view.deselect()
        }
    }

    // MARK: - Icon Loading

    private func loadIconImage(for entry: DockThemeConfig.DesktopIconEntry, theme: ThemeBundle?, size: CGFloat) -> NSImage {
        // sheep.exe: prefer the ORIGINAL eSheep icon (fetched at runtime like the sprite —
        // never bundled); the theme's own sheep.png is the offline fallback.
        if entry.type == "sheep", let img = NSImage(contentsOf: DesktopPetController.sheepIconCacheURL) {
            return img
        }
        if let theme = theme, let iconURL = theme.iconResource(entry.icon) {
            if let img = NSImage(contentsOf: iconURL) {
                return img
            }
        }

        // Fallback for "app" type — use system icon
        if entry.type == "app", let bid = entry.bundleID {
            return ThemeManager.shared.icon(for: bid, size: size)
        }

        // Widget shortcut types (TV / Clock / CPU): a system glyph when the theme ships no art.
        let widgetGlyph: [String: String] = ["tvfolder": "tv", "clock": "clock", "cpumonitor": "cpu", "nyanochrome": "cat", "readme": "doc.text.fill"]
        if let sym = widgetGlyph[entry.type] {
            let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.6, weight: .regular)
            if let img = NSImage(systemSymbolName: sym, accessibilityDescription: entry.name)?
                .withSymbolConfiguration(cfg) {
                return img
            }
        }

        // Native-game shortcut types (Setup Assistant): use the bundled per-game icon, else a
        // game-controller glyph.
        if ["doom", "doom2", "duke3d", "quake", "quake2", "warcraft2", "warcraft1", "heretic", "pacman"].contains(entry.type) {
            // Doom II rides on Doom's icon: the box art differs, the shell icon never did.
            let art = entry.type == "doom2" ? "doom" : entry.type
            if let url = Bundle.main.resourceURL?.appendingPathComponent("GameIcons/\(art).png"),
               let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: size, height: size)
                return img
            }
            let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.66, weight: .regular)
            if let img = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: entry.name)?
                .withSymbolConfiguration(cfg) {
                return img
            }
        }

        // Fallback for "trash" type
        if entry.type == "trash" {
            return NSImage(systemSymbolName: "trash", accessibilityDescription: "Trash")
                ?? NSImage(size: NSSize(width: size, height: size))
        }

        // Fallback for "folder" type — use the real icon for that path (e.g. "/" = Macintosh HD)
        if entry.type == "folder" {
            let path = NSString(string: entry.path ?? "/").expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: size, height: size)
                return icon
            }
            return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
        }

        return NSImage(size: NSSize(width: size, height: size))
    }

    private func loadIconImageByName(_ name: String, theme: ThemeBundle?, size: CGFloat) -> NSImage? {
        guard let theme = theme, let iconURL = theme.iconResource(name) else { return nil }
        return NSImage(contentsOf: iconURL)
    }

    // MARK: - Actions

    @objc private func iconDoubleClicked(_ sender: DesktopIconView) {
        DesktopLauncher.launch(sender.entry)
    }

    // MARK: - Customization (drag, context menus, persistence)

    private func persist() { DesktopStore.save(custom, theme: themeName) }

    private func iconMoved(_ v: DesktopIconView) {
        custom.positions[v.entry.name] = [v.frame.minX, v.frame.minY]
        persist()
    }

    /// Align each icon to the NEAREST grid cell of its current position (Clean Up).
    /// (Previously this cleared all free positions, snapping every icon back to its
    /// default column/row — i.e. the origin — instead of tidying it in place.)
    func snapToGrid() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame
        let cw = cellWidth, ch = cellHeight
        let baseX = iconsFromLeft
            ? visibleFrame.minX + marginX - screenFrame.origin.x
            : visibleFrame.maxX - marginX - cw - screenFrame.origin.x   // x of column 0
        let baseY = visibleFrame.maxY - marginY - ch - screenFrame.origin.y   // y of row 0
        for v in iconViews {
            let dx = iconsFromLeft ? (v.frame.minX - baseX) : (baseX - v.frame.minX)
            let col = max(0, (dx / cw).rounded())
            let row = max(0, ((baseY - v.frame.minY) / ch).rounded())
            custom.positions[v.entry.name] = [iconsFromLeft ? baseX + col * cw : baseX - col * cw,
                                              baseY - row * ch]
        }
        persist()
        update()
    }

    /// Right-click on an icon.
    private func showIconMenu(_ v: DesktopIconView, _ event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(menuOpen(_:)), keyEquivalent: "").representedObject = v
        menu.addItem(withTitle: "Change Icon…", action: #selector(menuChangeIcon(_:)), keyEquivalent: "").representedObject = v
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove", action: #selector(menuRemove(_:)), keyEquivalent: "").representedObject = v
        for it in menu.items { it.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: v)
    }

    /// Right-click on empty desktop.
    func showDesktopMenu(at event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        let newItem = menu.addItem(withTitle: "New Shortcut…", action: #selector(menuNewShortcut), keyEquivalent: "")
        newItem.target = self

        let wallItem = menu.addItem(withTitle: "Change Wallpaper", action: nil, keyEquivalent: "")
        let wallMenu = NSMenu()
        if let theme = ThemeManager.shared.activeTheme {
            for wp in theme.wallpaperOptions() {
                let mi = wallMenu.addItem(withTitle: wp.name, action: #selector(menuPickWallpaper(_:)), keyEquivalent: "")
                mi.target = self; mi.representedObject = wp.url.lastPathComponent
            }
            if !theme.wallpaperOptions().isEmpty { wallMenu.addItem(.separator()) }
        }
        let browse = wallMenu.addItem(withTitle: "Browse…", action: #selector(menuBrowseWallpaper), keyEquivalent: "")
        browse.target = self
        wallItem.submenu = wallMenu

        menu.addItem(.separator())
        let clean = menu.addItem(withTitle: "Clean Up Icons (snap to grid)", action: #selector(menuSnapGrid), keyEquivalent: "")
        clean.target = self

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func menuOpen(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? DesktopIconView { DesktopLauncher.launch(v.entry) }
    }
    @objc private func menuChangeIcon(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? DesktopIconView else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns, .image]
        panel.message = "Choose an icon image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        custom.iconOverrides[v.entry.name] = url.path
        persist(); update()
    }
    @objc private func menuRemove(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? DesktopIconView else { return }
        custom.added.removeAll { $0.name == v.entry.name }
        custom.removed.append(v.entry.name)
        custom.positions[v.entry.name] = nil
        persist(); update()
    }
    @objc private func menuNewShortcut() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an application for the new shortcut"
        guard panel.runModal() == .OK, let url = panel.url, let bid = Bundle(url: url)?.bundleIdentifier else { return }
        let name = url.deletingPathExtension().lastPathComponent
        var entry = DockThemeConfig.DesktopIconEntry(name: name, icon: "", type: "app")
        entry.bundleID = bid
        custom.added.append(entry)
        custom.removed.removeAll { $0 == name }
        persist(); update()
    }
    @objc private func menuPickWallpaper(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? String else { return }
        AppSettings.shared.themeCustomWallpaper[themeName] = nil
        AppSettings.shared.themeWallpaperOverrides[themeName] = file
        ThemeManager.shared.applyWallpaper()
    }
    @objc private func menuBrowseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a wallpaper image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppSettings.shared.themeCustomWallpaper[themeName] = url.path
        ThemeManager.shared.applyWallpaper()
    }
    @objc private func menuSnapGrid() { snapToGrid() }
}

// MARK: - Content View (handles click-on-empty to deselect + desktop context menu)

private final class DesktopIconsContentView: NSView {
    weak var controller: DesktopIconsController?

    override func mouseDown(with event: NSEvent) {
        controller?.deselectAll()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.showDesktopMenu(at: event, in: self)
    }
}
