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
    }

    private var windows: [NSWindow] = []
    private var cards: [CGWindowID: ExposeCardView] = [:]
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

        isOpen = true
        generation += 1
        let gen = generation
        cards.removeAll()

        for screen in NSScreen.screens {
            let mine = items.filter { screen.frame.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) }

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
            root.onBackgroundClick = { [weak self] in self?.hide() }
            root.onEscape = { [weak self] in self?.hide() }
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
        windows.removeAll()
        cards.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { closing.forEach { $0.orderOut(nil) } })
    }

    // MARK: - Building the sheet

    private func place(_ items: [Item], on root: ExposeBackdropView, screen: NSScreen) {
        guard !items.isEmpty else { return }
        // Reading order, so where a card lands still has something to do with where its window is.
        let sorted = items.sorted {
            abs($0.frame.maxY - $1.frame.maxY) > 12 ? $0.frame.maxY > $1.frame.maxY
                                                    : $0.frame.minX < $1.frame.minX
        }
        let inset = bottomInset(on: screen)
        let area = NSRect(x: 40, y: inset + 40,
                          width: root.bounds.width - 80,
                          height: root.bounds.height - 80 - inset - menuBarInset(on: screen))
        let slots = layout(sorted, in: area)

        for (item, slot) in zip(sorted, slots) {
            let card = ExposeCardView(frame: slot)
            card.item = item
            card.targetSize = card.contentRect.size   // frame is still the slot at this point
            card.onPick = { [weak self] in
                self?.hide()
                self?.raise(item)
            }
            root.addSubview(card)
            cards[item.windowID] = card

            // The move that makes it Exposé: the card starts exactly where the window is and
            // travels to its slot. Everything needed for that is already in `item.frame`.
            let from = NSRect(x: item.frame.minX - screen.frame.minX,
                              y: item.frame.minY - screen.frame.minY,
                              width: item.frame.width, height: item.frame.height)
            card.frame = from
            card.wantsLayer = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                card.animator().frame = slot
            }
        }
    }

    /// A grid whose short last row is centred, with every card kept at its window's aspect ratio
    /// and never enlarged past life size — Exposé only ever shrank.
    private func layout(_ items: [Item], in area: NSRect) -> [NSRect] {
        let n = items.count
        guard n > 0, area.width > 40, area.height > 40 else { return [] }
        let cols = Int(ceil(Double(n).squareRoot()))
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
                icons[pidValue] = NSRunningApplication(processIdentifier: pidValue)?.icon
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

    // MARK: - Thumbnails

    private func fetchThumbnails(for items: [Item], generation gen: Int) {
        let wanted = Set(items.map { $0.windowID })
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: true) else { return }
            guard gen == self.generation else { return }
            let targets = content.windows.filter { wanted.contains($0.windowID) }
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
    var onEscape: (() -> Void)?
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
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

/// One window's thumbnail on the sheet.
final class ExposeCardView: NSView {
    var item: ExposeController.Item!
    var image: NSImage? { didSet { needsDisplay = true } }
    var onPick: (() -> Void)?
    /// How large the thumbnail ends up on screen, so it can be captured at exactly that.
    /// Taken from `contentRect` rather than restated, so it cannot drift from what draw uses.
    var targetSize: NSSize = .zero
    /// The thumbnail's rect. The margin is where the hover rim goes.
    var contentRect: NSRect { bounds.insetBy(dx: 3, dy: 3) }

    // Without this the first click into the sheet is spent making its window key and the pick
    // needs a second one — which is what a hold-opened Exposé did every single time.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var hot = false { didSet { needsDisplay = true } }
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

    override func mouseEntered(with event: NSEvent) { hot = true }
    override func mouseExited(with event: NSEvent) { hot = false }
    override func mouseDown(with event: NSEvent) { onPick?() }
}
