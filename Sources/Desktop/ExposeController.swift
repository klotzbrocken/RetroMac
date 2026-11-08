import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Exposé: a dimmed sheet holding every window on the current desktop, shrunk so none overlap.
/// Mac OS X 10.3 to 10.6 had it on F9/F10/F11; Lion folded it into Mission Control and the
/// separate view was gone by Catalina, so this is a rebuild rather than a hook into anything the
/// system still offers.
///
/// The window list comes from `CGWindowListCopyWindowInfo`, which answers instantly, so the sheet
/// is laid out and animating before a single thumbnail exists. The thumbnails come separately from
/// ScreenCaptureKit and drop into their cards as they arrive. Doing it the other way round meant
/// staring at an unchanged screen for as long as the capture took, which reads as a dropped
/// keypress rather than as a feature starting up.
final class ExposeController {

    static let shared = ExposeController()

    enum Mode {
        /// Every window on this desktop, the old F9.
        case allWindows
        /// Only the frontmost app's windows, the old F10.
        case applicationWindows
        /// One named app's windows — what 10.6 showed when you held its dock icon.
        case application(pid_t)
    }

    /// One window, in Cocoa screen coordinates.
    struct Item {
        let windowID: CGWindowID
        let pid: pid_t
        let title: String
        let appName: String
        let icon: NSImage?
        let frame: NSRect
        /// In the Dock, shown in the row along the bottom (10.6's application Exposé).
        var minimized = false
        /// The window as Accessibility sees it, when it came from there (the minimised ones).
        var ax: AXUIElement? = nil
    }

    private var windows: [NSWindow] = []
    private var cards: [CGWindowID: ExposeCardView] = [:]
    /// The card under the pointer or picked with the arrow keys.
    private weak var selected: ExposeCardView?
    /// Space blew this card up to life size; Space or Esc puts it back into its slot.
    private var preview: (card: ExposeCardView, slot: NSRect)?
    /// What ScreenCaptureKit handed out, for a sharper picture when Space enlarges a card.
    private var captured: [CGWindowID: SCWindow] = [:]
    private(set) var isOpen = false
    /// Bumped on every show/hide so a capture that lands after the sheet closed is dropped
    /// instead of being pushed into a card that no longer belongs to anything.
    private var generation = 0

    private init() {}

    // MARK: - Show / hide

    func toggle(_ mode: Mode = .allWindows) { isOpen ? hide() : show(mode) }

    func show(_ mode: Mode = .allWindows) {
        guard !isOpen else { return }

        // Read the frontmost app before we activate ourselves, or "the frontmost app's windows"
        // becomes RetroMac's own the moment the sheet opens.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        var items = currentWindows()
        switch mode {
        case .allWindows: break
        case .applicationWindows: if let pid = frontPID { items = items.filter { $0.pid == pid } }
        case .application(let pid): items = items.filter { $0.pid == pid }
        }
        // 10.6 put an application's minimised windows in a row of their own along the bottom.
        // Only the application views had it; the all-windows view showed the desktop as it was.
        switch mode {
        case .allWindows: break
        case .applicationWindows: if let pid = frontPID { items += minimizedWindows(of: pid) }
        case .application(let pid): items += minimizedWindows(of: pid)
        }

        isOpen = true
        generation += 1
        let gen = generation
        cards.removeAll()
        captured.removeAll()
        preview = nil

        for (n, screen) in NSScreen.screens.enumerated() {
            // The minimised row goes on the main display, where the Dock they sit in is.
            let mine = items.filter {
                $0.minimized ? n == 0 : screen.frame.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY))
            }

            // KeyableWindow so Escape reaches us: a borderless NSWindow reports canBecomeKey false.
            let win = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless],
                                    backing: .buffered, defer: false)
            win.acceptsMouseMovedEvents = true
            // Below the retro dock (24) and the CRT overlay (25), like the Dashboard layer.
            // Exposé kept the Dock visible too.
            win.level = NSWindow.Level(rawValue: 23)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            win.hasShadow = false

            let root = ExposeBackdropView(frame: NSRect(origin: .zero, size: screen.frame.size))
            root.onBackgroundClick = { [weak self] in
                guard let self else { return }
                if self.preview != nil { self.endPreview() } else { self.hide() }
            }
            root.onKey = { [weak self] code in self?.key(code) ?? false }
            // Only when there is nothing anywhere. With a second display attached, the screen
            // that happens to hold no windows used to announce "No windows" while the other one
            // was showing them all.
            root.isEmpty = items.isEmpty
            win.contentView = root
            win.alphaValue = 0
            win.orderFrontRegardless()
            windows.append(win)

            place(mine, on: root, screen: screen)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                win.animator().alphaValue = 1
            }
            win.makeKey()
            win.makeFirstResponder(root)
        }
        NSApp.activate(ignoringOtherApps: true)

        fetchThumbnails(for: items, generation: gen)
    }

    func hide() {
        guard isOpen else { return }
        isOpen = false
        generation += 1
        let closing = windows
        let flying = Array(cards.values)
        windows.removeAll()
        cards.removeAll()
        captured.removeAll()
        preview = nil
        // The way back is the way in: every card returns to where its window is while the sheet
        // fades, and the minimised ones simply go.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            closing.forEach { $0.animator().alphaValue = 0 }
            for card in flying {
                if let home = card.home { card.animator().frame = home }
            }
        }, completionHandler: { closing.forEach { $0.orderOut(nil) } })
    }

    // MARK: - Building the sheet

    private func place(_ items: [Item], on root: ExposeBackdropView, screen: NSScreen) {
        guard !items.isEmpty else { return }
        // Reading order, so where a card lands still has something to do with where its window is.
        let sorted = items.filter { !$0.minimized }.sorted {
            abs($0.frame.maxY - $1.frame.maxY) > 12 ? $0.frame.maxY > $1.frame.maxY
                                                    : $0.frame.minX < $1.frame.minX
        }
        let docked = items.filter(\.minimized)
        let inset = bottomInset(on: screen)
        var area = NSRect(x: 40, y: inset + 40,
                          width: root.bounds.width - 80,
                          height: root.bounds.height - 80 - inset - menuBarInset(on: screen))
        var rowSlots: [NSRect] = []
        if !docked.isEmpty {
            // A strip under a hairline, the open windows above it.
            let rowH = min(150, area.height * 0.22)
            let row = NSRect(x: area.minX, y: area.minY, width: area.width, height: rowH)
            rowSlots = layout(docked, in: row, columns: docked.count)
            root.separatorY = row.maxY + 14
            area.origin.y = row.maxY + 28
            area.size.height -= rowH + 28
        }
        let slots = layout(sorted, in: area) + rowSlots

        for (item, slot) in zip(sorted + docked, slots) {
            let card = ExposeCardView(frame: slot)
            card.item = item
            card.targetSize = card.contentRect.size   // frame is still the slot at this point
            card.onPick = { [weak self] in
                self?.hide()
                self?.raise(item)
            }
            card.onHover = { [weak self, weak card] inside in
                guard let self, let card else { return }
                if inside { self.select(card) } else if self.selected === card { self.select(nil) }
            }
            root.addSubview(card)
            cards[item.windowID] = card
            card.wantsLayer = true

            guard !item.minimized else {
                // Out of the Dock there is no window to fly from; the row fades up instead.
                card.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.26
                    card.animator().alphaValue = 1
                }
                continue
            }
            // The move that makes it Exposé: the card starts exactly where the window is and
            // travels to its slot. Everything needed for that is already in `item.frame`.
            let from = NSRect(x: item.frame.minX - screen.frame.minX,
                              y: item.frame.minY - screen.frame.minY,
                              width: item.frame.width, height: item.frame.height)
            card.home = from
            card.frame = from
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                card.animator().frame = slot
            }
        }
    }

    // MARK: - Keys

    /// The arrows move to the nearest card that way, Return picks it, Space shows it at life
    /// size (10.6: "press the Space bar to see a larger preview"), Esc steps back out.
    private func key(_ code: UInt16) -> Bool {
        switch code {
        case 53:                                   // Esc
            if preview != nil { endPreview() } else { hide() }
        case 49:                                   // Space
            if preview != nil { endPreview() } else if let card = selected { beginPreview(card) }
        case 36, 76:                               // Return, Enter
            if let card = selected { endPreview(); card.onPick?() }
        case 123: move(dx: -1, dy: 0)
        case 124: move(dx: 1, dy: 0)
        case 125: move(dx: 0, dy: -1)
        case 126: move(dx: 0, dy: 1)
        default: return false
        }
        return true
    }

    private func select(_ card: ExposeCardView?) {
        guard preview == nil else { return }
        selected = card
        cards.values.forEach { $0.hot = $0 === card }
    }

    /// The card whose centre lies most directly in that direction, across displays.
    private func move(dx: CGFloat, dy: CGFloat) {
        guard preview == nil else { return }
        func centre(_ c: ExposeCardView) -> NSPoint {
            let f = c.window?.convertToScreen(c.frame) ?? c.frame
            return NSPoint(x: f.midX, y: f.midY)
        }
        let all = Array(cards.values)
        guard let from = selected else {
            // Nothing picked yet: start top left, where reading starts.
            select(all.max { let a = centre($0), b = centre($1); return (a.y - a.x) < (b.y - b.x) })
            return
        }
        let o = centre(from)
        let best = all.filter { $0 !== from }.compactMap { c -> (ExposeCardView, CGFloat)? in
            let p = centre(c)
            let along = (p.x - o.x) * dx + (p.y - o.y) * dy
            guard along > 1 else { return nil }
            let across = abs((p.x - o.x) * dy) + abs((p.y - o.y) * dx)
            return (c, along + across * 2)
        }.min { $0.1 < $1.1 }
        if let best { select(best.0) }
    }

    private func beginPreview(_ card: ExposeCardView) {
        guard let root = card.superview, let item = card.item else { return }
        let slot = card.frame
        let room = root.bounds.insetBy(dx: 60, dy: 60)
        let s = min(room.width / item.frame.width, room.height / item.frame.height, 1)
        let size = NSSize(width: item.frame.width * s, height: item.frame.height * s)
        let big = NSRect(x: room.midX - size.width / 2, y: room.midY - size.height / 2,
                         width: size.width, height: size.height)
        preview = (card, slot)
        root.addSubview(card, positioned: .above, relativeTo: nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            card.animator().frame = big
        }
        // The slot-sized capture would be blurry this big; ask for one at the new size.
        guard let win = captured[item.windowID] else { return }
        let gen = generation, scale = card.window?.backingScaleFactor ?? 2
        Task { @MainActor in
            let img = await ScreenCaptureManager.captureThumbnail(win, points: size, scale: scale)
            if gen == self.generation, let img { card.image = img }
        }
    }

    private func endPreview() {
        guard let (card, slot) = preview else { return }
        preview = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            card.animator().frame = slot
        }
    }

    /// A grid whose short last row is centred, with every card kept at its window's aspect ratio
    /// and never enlarged past life size — Exposé only ever shrank.
    private func layout(_ items: [Item], in area: NSRect, columns: Int? = nil) -> [NSRect] {
        let n = items.count
        guard n > 0, area.width > 40, area.height > 40 else { return [] }
        let cols = columns ?? Int(ceil(Double(n).squareRoot()))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let gap: CGFloat = 26
        let cellW = (area.width - gap * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH = (area.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        guard cellW > 24, cellH > 24 else { return items.map { _ in area } }

        var out: [NSRect] = []
        for (i, it) in items.enumerated() {
            let r = i / cols, c = i % cols
            let inRow = min(cols, n - r * cols)
            let rowW = CGFloat(inRow) * cellW + CGFloat(inRow - 1) * gap
            let x0 = area.minX + (area.width - rowW) / 2
            let cell = NSRect(x: x0 + CGFloat(c) * (cellW + gap),
                              y: area.maxY - gap - CGFloat(r + 1) * cellH - CGFloat(r) * gap,
                              width: cellW, height: cellH)
            let s = min(cellW / it.frame.width, cellH / it.frame.height, 1)
            let w = it.frame.width * s, h = it.frame.height * s
            out.append(NSRect(x: cell.midX - w / 2, y: cell.midY - h / 2, width: w, height: h))
        }
        return out
    }

    private func bottomInset(on screen: NSScreen) -> CGFloat {
        guard let dock = DockController.shared.visibleDockFrame(on: screen) else { return 0 }
        guard dock.minY <= screen.frame.minY + 2 else { return 0 }
        return dock.height
    }

    private func menuBarInset(on screen: NSScreen) -> CGFloat {
        max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    // MARK: - The window list

    /// Straight from the window server, so it answers on the same turn of the run loop.
    private func currentWindows() -> [Item] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        // The system's own furniture is not a window anybody wants to Exposé to.
        let shells: Set<String> = ["Dock", "Window Manager", "Control Center",
                                   "Notification Center", "Spotlight", "SystemUIServer"]
        guard let primary = NSScreen.screens.first else { return [] }

        var out: [Item] = []
        var icons: [pid_t: NSImage?] = [:]
        for w in info {
            // Our own windows are NOT skipped, and skipping them was the bug: on a retro desktop
            // a good share of what you see — Television, the CPU monitor, Notepad, Calculator, an
            // App Folder — belongs to RetroMac, and Exposé reported "No windows" over a screen
            // full of them. Nothing of ours leaks in as a result: every piece of theme furniture
            // (dock 24, Dashboard and this sheet 23, the pet 25, menus 26, desktop icons at the
            // desktop-icon level) sits above layer 0 and is dropped here, and the sheet's own
            // windows do not exist yet when this list is taken.
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pidValue = w[kCGWindowOwnerPID as String] as? pid_t,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width > 80, height > 80 else { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            guard !shells.contains(owner) else { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }

            // CGWindow bounds are top-left origin off the primary display; Cocoa counts up from
            // the bottom of that same display.
            let frame = NSRect(x: x, y: primary.frame.maxY - (y + height), width: width, height: height)
            if icons[pidValue] == nil {
                let app = NSRunningApplication(processIdentifier: pidValue)
                icons[pidValue] = app?.bundleIdentifier.map { ThemeManager.shared.icon(for: $0, size: 64) } ?? app?.icon
            }
            out.append(Item(windowID: id,
                            pid: pidValue,
                            title: w[kCGWindowName as String] as? String ?? "",
                            appName: owner,
                            icon: icons[pidValue] ?? nil,
                            frame: frame))
        }
        return out
    }

    /// An app's minimised windows, through Accessibility. Without it they stay out, as before.
    /// The window server lists them too (off screen), which gives each its id for a thumbnail;
    /// they are matched by size, since their titles need Screen Recording to read there.
    private func minimizedWindows(of pid: pid_t) -> [Item] {
        guard AXIsProcessTrusted(), let primary = NSScreen.screens.first else { return [] }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        let offscreen = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                         as? [[String: Any]] ?? []).filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                && ($0[kCGWindowLayer as String] as? Int) == 0
                && ($0[kCGWindowIsOnscreen as String] as? Bool) != true
        }
        var used = Set<CGWindowID>()
        var synthetic = CGWindowID.max
        let running = NSRunningApplication(processIdentifier: pid)
        let icon = running?.bundleIdentifier.map { ThemeManager.shared.icon(for: $0, size: 64) } ?? running?.icon
        var out: [Item] = []
        for w in list {
            var m: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &m) == .success,
                  (m as? Bool) == true else { continue }
            var posRef: CFTypeRef?, sizeRef: CFTypeRef?
            var origin = CGPoint.zero, size = CGSize(width: 400, height: 300)
            if AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success {
                AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
            }
            if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success {
                AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
            }
            let id = offscreen.first { info in
                guard let id = info[kCGWindowNumber as String] as? CGWindowID, !used.contains(id),
                      let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
                return abs((b["Width"] ?? 0) - size.width) < 3 && abs((b["Height"] ?? 0) - size.height) < 3
            }?[kCGWindowNumber as String] as? CGWindowID
            let windowID = id ?? { synthetic -= 1; return synthetic }()
            used.insert(windowID)
            out.append(Item(windowID: windowID, pid: pid, title: title(of: w),
                            appName: running?.localizedName ?? "", icon: icon,
                            frame: NSRect(x: origin.x, y: primary.frame.maxY - origin.y - size.height,
                                          width: size.width, height: size.height),
                            minimized: true, ax: w))
        }
        return out
    }

    // MARK: - Thumbnails

    private func fetchThumbnails(for items: [Item], generation gen: Int) {
        let wanted = Set(items.map { $0.windowID })
        let offscreen = items.contains(where: \.minimized)
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: !offscreen) else { return }
            guard gen == self.generation else { return }
            let targets = content.windows.filter { wanted.contains($0.windowID) }
            for w in targets { self.captured[w.windowID] = w }
            // Concurrently: a dozen windows one after another is a visible stagger, and each
            // card can take its own image the moment that one is ready.
            await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
                for win in targets {
                    let card = self.cards[win.windowID]
                    let points = card?.targetSize ?? NSSize(width: 480, height: 300)
                    let scale = card?.window?.backingScaleFactor ?? 2
                    group.addTask {
                        (win.windowID,
                         await ScreenCaptureManager.captureThumbnail(win, points: points, scale: scale))
                    }
                }
                for await (id, img) in group {
                    guard gen == self.generation, let img = img else { continue }
                    self.cards[id]?.image = img
                }
            }
        }
    }

    // MARK: - Picking a window

    /// Bring the picked window forward. If it lives on another desktop, macOS animates over to it
    /// on its own — which is also the only reliable way to change space without private calls.
    private func raise(_ item: Item) {
        NSRunningApplication(processIdentifier: item.pid)?
            .activate(options: [.activateIgnoringOtherApps])
        guard AXIsProcessTrusted() else { return }
        if let win = item.ax {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            return
        }

        let app = AXUIElementCreateApplication(item.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return }

        // Match on geometry first. Titles are duplicated, empty, or localised often enough that
        // matching on them alone picks the wrong window of a multi-window app.
        let target = list.first { matches($0, item) } ?? list.first { title(of: $0) == item.title }
        guard let win = target else { return }
        AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
    }

    private func matches(_ element: AXUIElement, _ item: Item) -> Bool {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return false }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // AX reports top-left origin, like CGWindow — compare in that space.
        guard let primary = NSScreen.screens.first else { return false }
        let cgY = primary.frame.maxY - item.frame.maxY
        return abs(origin.x - item.frame.minX) < 3 && abs(origin.y - cgY) < 3
            && abs(size.width - item.frame.width) < 3 && abs(size.height - item.frame.height) < 3
    }

    private func title(of element: AXUIElement) -> String {
        var t: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &t)
        return t as? String ?? ""
    }
}

// MARK: - Views

/// The dimmed sheet behind the cards.
final class ExposeBackdropView: NSView {
    var onBackgroundClick: (() -> Void)?
    /// A key went down; true when it was one of Exposé's.
    var onKey: ((UInt16) -> Bool)?
    /// The hairline over the row of minimised windows, when there is one.
    var separatorY: CGFloat? { didSet { needsDisplay = true } }
    /// Drawn with a note when the desktop has nothing to show, rather than looking like a
    /// dimmed screen that failed to do anything.
    var isEmpty = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Exposé replaced the desktop with graphite rather than merely dimming it.
        NSGradient(starting: NSColor(white: 0.22, alpha: 0.88),
                   ending: NSColor(white: 0.09, alpha: 0.92))?
            .draw(in: bounds, angle: -90)
        if let y = separatorY {
            NSColor(white: 1, alpha: 0.25).setFill()
            NSRect(x: 40, y: y, width: bounds.width - 80, height: 1).fill()
        }
        guard isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Lucida Grande", size: 15) ?? .systemFont(ofSize: 15),
            .foregroundColor: NSColor(white: 1, alpha: 0.5)]
        let s = "No windows" as NSString
        let size = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
               withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { onBackgroundClick?() }

    override func keyDown(with event: NSEvent) {
        if onKey?(event.keyCode) != true { super.keyDown(with: event) }
    }
}

/// One window's thumbnail on the sheet.
final class ExposeCardView: NSView {
    var item: ExposeController.Item!
    var image: NSImage? { didSet { needsDisplay = true } }
    var onPick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    /// Where its window is, in the sheet's coordinates: the card flies back there on close.
    var home: NSRect?
    /// How large the thumbnail ends up on screen, so it can be captured at exactly that.
    /// Taken from `contentRect` rather than restated, so it cannot drift from what draw uses.
    var targetSize: NSSize = .zero
    /// The thumbnail's rect. The margin is where the hover rim goes.
    var contentRect: NSRect { bounds.insetBy(dx: 3, dy: 3) }

    // Without this the first click into the sheet is spent making its window key and the pick
    // needs a second one — which is what a hold-opened Exposé did every single time.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Highlighted, by the pointer or the arrow keys.
    var hot = false { didSet { if hot != oldValue { needsDisplay = true } } }
    private var tracker: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracker { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracker = t
    }

    override func draw(_ dirtyRect: NSRect) {
        let content = contentRect
        guard content.width > 4, content.height > 4 else { return }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        if let img = image {
            img.draw(in: content, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            // The capture has not landed yet, or the window refused to be captured. A plate with
            // the app's icon still says which window this is.
            NSColor(white: 0.32, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: content, xRadius: 5, yRadius: 5).fill()
            if let icon = item?.icon {
                let side = min(56, min(content.width, content.height) * 0.5)
                icon.draw(in: NSRect(x: content.midX - side / 2, y: content.midY - side / 2,
                                     width: side, height: side))
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        guard hot else { return }
        NSColor(white: 1, alpha: 0.95).setStroke()
        let rim = NSBezierPath(rect: content.insetBy(dx: -1.5, dy: -1.5))
        rim.lineWidth = 3
        rim.stroke()
        drawTitleChip()
    }

    /// App icon plus window title on a dark plate, centred over the thumbnail — where 10.6 put it.
    private func drawTitleChip() {
        let text = (item?.title.isEmpty == false ? item!.title : item?.appName) ?? ""
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Lucida Grande", size: 13) ?? .systemFont(ofSize: 13),
            .foregroundColor: NSColor.white]
        let iconSide: CGFloat = 22, pad: CGFloat = 10, gap: CGFloat = 7
        var size = (text as NSString).size(withAttributes: attrs)
        // Long titles get cut rather than pushing the plate past the card.
        let maxText = max(40, bounds.width - pad * 2 - iconSide - gap - 12)
        var shown = text as NSString
        if size.width > maxText {
            var s = text
            while !s.isEmpty && (s + "…" as NSString).size(withAttributes: attrs).width > maxText {
                s.removeLast()
            }
            shown = (s + "…") as NSString
            size = shown.size(withAttributes: attrs)
        }
        let w = pad * 2 + iconSide + gap + size.width
        let h: CGFloat = 32
        let plate = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        NSColor(white: 0, alpha: 0.74).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 7, yRadius: 7).fill()
        item?.icon?.draw(in: NSRect(x: plate.minX + pad, y: plate.midY - iconSide / 2,
                                    width: iconSide, height: iconSide))
        shown.draw(at: NSPoint(x: plate.minX + pad + iconSide + gap, y: plate.midY - size.height / 2),
                   withAttributes: attrs)
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onPick?() }
}
