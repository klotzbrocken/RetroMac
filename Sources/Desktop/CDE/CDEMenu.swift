import AppKit
import Carbon.HIToolbox

/// One entry of a CDE menu. A separator has no title; a cascade has a submenu.
struct CDEMenuItem {
    var title = ""
    var icon: NSImage? = nil
    var enabled = true
    var submenu: [CDEMenuItem]? = nil
    var action: (() -> Void)? = nil
    var isSeparator: Bool { title.isEmpty }
    static let separator = CDEMenuItem()
}

/// Motif menus as dtwm drew them under Solaris 8 (Lastenheft 3.0, CDE-08 and CDE-09): the
/// Workspace Menu on the desktop, the window menu behind the box at the left of a title bar,
/// the menu of a minimised window's icon. Measured off the Workspace Menu in `solcdegeneral.png`:
/// a 1 pt bevel, a 20 pt title over a double rule, rows of 21 pt (23 pt with a 16 pt icon),
/// 2 pt etched separators, the armed row sunk in #9494A5, a cascade opening 4 pt below its row.
///
/// Click to post, click to choose: the menus live in one transparent panel over the screen, so
/// a click anywhere else closes them, and Esc does too.
enum CDEMenu {
    private static var panel: NSPanel?
    private static var outsideMonitor: Any?

    /// `topLeft` in screen coordinates. A click inside `anchor` within the double-click time
    /// runs `onAnchorDoubleClick` (dtwm: a double-click on the window-menu box closes the window).
    /// Whose menus these are: dtwm's (Solaris), or Photon's (QNX 6.2.1), which draws every entry
    /// as a bar of its own and every section as a box of its own.
    enum Look { case cde, photon }
    private(set) static var look: Look = .cde

    static func show(_ items: [CDEMenuItem], title: String? = nil, at topLeft: NSPoint, look: Look = .cde,
                     anchor: NSRect? = nil, onAnchorDoubleClick: (() -> Void)? = nil) {
        close()
        self.look = look
        CDESubpanel.closeAll()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(topLeft) }) ?? NSScreen.main else { return }
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        let view = CDEMenuView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.anchor = anchor.map { NSRect(x: $0.minX - screen.frame.minX, y: screen.frame.maxY - $0.maxY, width: $0.width, height: $0.height) }
        view.onAnchorDoubleClick = onAnchorDoubleClick
        view.open(items, title: title, at: NSPoint(x: topLeft.x - screen.frame.minX, y: screen.frame.maxY - topLeft.y), level: 0)
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
        // A click on another display or in another app's window closes it, as a click outside does.
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            DispatchQueue.main.async { close() }
        }
        CDEEscape.hold { close() }
    }

    static func close() {
        guard let p = panel else { return }
        panel = nil
        p.orderOut(nil)
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        CDEEscape.release()
    }

    static var isOpen: Bool { panel != nil }

    // MARK: Metrics

    static var font: NSFont { look == .photon ? PhotonColors.label : (NSFont(name: "LucidaGrande", size: 14) ?? .systemFont(ofSize: 14)) }
    static let titleH: CGFloat = 20, ruleH: CGFloat = 4, rowH: CGFloat = 21, iconRowH: CGFloat = 23, sepH: CGFloat = 2

    /// Photon, measured off the Launch menu in `qnx621about2.png`: a black edge, a #F1F1F1 light
    /// and 3 pt of #D8D8D8 inside it; bars of 17 pt with 2 pt between; a section ends in #BFBFBF
    /// and black and the next begins (7 pt); the label at 37 pt, a 16 pt icon at 12 pt.
    static let photonTop: CGFloat = 5, photonBottom: CGFloat = 3, photonSide: CGFloat = 4, photonRow: CGFloat = 19,
               photonBar: CGFloat = 17, photonSep: CGFloat = 7, photonLabel: CGFloat = 37

    /// A row with an icon is 2 pt taller than one without, side by side in the same menu.
    static func height(of item: CDEMenuItem) -> CGFloat {
        if look == .photon { return item.isSeparator ? photonSep : photonRow }
        return item.isSeparator ? sepH : item.icon == nil ? rowH : iconRowH
    }

    /// Size of a menu: the widest label, its icon column and cascade arrow, or the title.
    static func size(of items: [CDEMenuItem], title: String?) -> NSSize {
        let hasArrows = items.contains { $0.submenu != nil }
        if look == .photon {
            let w = items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            return NSSize(width: ceil(photonLabel + w + (hasArrows ? 26 : 14) + photonSide),
                          height: photonTop + items.reduce(0) { $0 + height(of: $1) } + photonBottom)
        }
        var w: CGFloat = 0, h: CGFloat = 2 + (title == nil ? 0 : titleH + ruleH)
        for it in items {
            h += height(of: it)
            if !it.isSeparator { w = max(w, (it.title as NSString).size(withAttributes: [.font: font]).width + (it.icon == nil ? 0 : 18)) }
        }
        w += 1 + 4 + (hasArrows ? 20 : 12) + 1
        if let title { w = max(w, (title as NSString).size(withAttributes: [.font: font]).width + 40) }
        return NSSize(width: ceil(w), height: h)
    }
}

/// While a subpanel or menu is open, Esc closes it (CDE-02). RetroMac stays in the background
/// (macOS no longer lets it take the keyboard from the app in front), so Esc is held as a
/// hotkey for that time only and let go on close. A hotkey needs no permission; an event tap
/// would need Input Monitoring.
enum CDEEscape {
    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    private static var onEscape: (() -> Void)?
    private static let signature = OSType(0x52434445)   // "RCDE"

    static func hold(_ action: @escaping () -> Void) {
        onEscape = action
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard id.signature == CDEEscape.signature else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { CDEEscape.onEscape?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        guard hotKey == nil else { return }
        var ref: EventHotKeyRef?
        // id 99: ids 1–11 are AppDelegate's hotkeys
        if RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: signature, id: 99), GetApplicationEventTarget(), 0, &ref) == noErr {
            hotKey = ref
        }
    }

    /// Whether Esc is held right now, for the leak check (PERF-06).
    static var isHeld: Bool { hotKey != nil }

    static func release() {
        onEscape = nil
        if let ref = hotKey { UnregisterEventHotKey(ref); hotKey = nil }
    }
}

/// The open menus of one posting: the first, and the cascades opened from it.
final class CDEMenuView: NSView {
    struct Level { var items: [CDEMenuItem]; var title: String?; var frame: NSRect; var armed: Int? }
    private var levels: [Level] = []
    var anchor: NSRect?
    var onAnchorDoubleClick: (() -> Void)?
    private let openedAt = Date()

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static let face = NSColor(srgbRed: 0xAD / 255, green: 0xB5 / 255, blue: 0xC6 / 255, alpha: 1)
    private static let light = NSColor(srgbRed: 0xDE / 255, green: 0xDE / 255, blue: 0xE7 / 255, alpha: 1)
    private static let dark = NSColor(srgbRed: 0x5A / 255, green: 0x63 / 255, blue: 0x6B / 255, alpha: 1)
    private static let armedFill = NSColor(srgbRed: 0x94 / 255, green: 0x94 / 255, blue: 0xA5 / 255, alpha: 1)
    private static let insensitive = NSColor(srgbRed: 0x6B / 255, green: 0x73 / 255, blue: 0x84 / 255, alpha: 1)

    func open(_ items: [CDEMenuItem], title: String?, at topLeft: NSPoint, level: Int) {
        levels = Array(levels.prefix(level))
        let s = CDEMenu.size(of: items, title: title)
        var f = NSRect(origin: topLeft, size: s)
        // Kept on screen; a cascade with no room on the right opens to the left of its parent.
        if f.maxX > bounds.maxX {
            f.origin.x = level > 0 ? levels[level - 1].frame.minX - s.width + 2 : bounds.maxX - s.width
        }
        f.origin.x = max(0, f.origin.x)
        f.origin.y = max(0, min(f.origin.y, bounds.maxY - s.height))
        levels.append(Level(items: items, title: title, frame: f, armed: nil))
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    /// Row rectangles of a level, in view coordinates, with the item index.
    private func rows(_ l: Level) -> [(NSRect, Int)] {
        let photon = CDEMenu.look == .photon
        var y = l.frame.minY + (photon ? CDEMenu.photonTop : 1 + (l.title == nil ? 0 : CDEMenu.titleH + CDEMenu.ruleH))
        let inset = photon ? CDEMenu.photonSide : 1
        var out: [(NSRect, Int)] = []
        for (i, it) in l.items.enumerated() {
            let h = CDEMenu.height(of: it)
            out.append((NSRect(x: l.frame.minX + inset, y: y, width: l.frame.width - inset * 2, height: h), i))
            y += h
        }
        return out
    }

    private func hit(_ p: NSPoint) -> (level: Int, item: Int?)? {
        for li in levels.indices.reversed() where levels[li].frame.contains(p) {
            let row = rows(levels[li]).first { $0.0.contains(p) }
            if let row, !levels[li].items[row.1].isSeparator, levels[li].items[row.1].enabled { return (li, row.1) }
            return (li, nil)
        }
        return nil
    }

    /// Arm the row under the pointer; a cascade opens as soon as its row is armed.
    private func track(_ p: NSPoint) {
        guard let h = hit(p) else { return }
        if levels[h.level].armed == h.item { return }
        levels[h.level].armed = h.item
        levels = Array(levels.prefix(h.level + 1))
        if let i = h.item, let sub = levels[h.level].items[i].submenu,
           let row = rows(levels[h.level]).first(where: { $0.1 == i })?.0 {
            if CDEMenu.look == .photon {   // Photon: the cascade's first bar level with its entry, edges shared
                open(sub, title: nil, at: NSPoint(x: levels[h.level].frame.maxX - 1, y: row.minY - CDEMenu.photonTop), level: h.level + 1)
            } else {
                open(sub, title: levels[h.level].items[i].title, at: NSPoint(x: levels[h.level].frame.maxX - 2, y: row.minY + 4), level: h.level + 1)
            }
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) { track(convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { track(convert(event.locationInWindow, from: nil)) }
    override func rightMouseDragged(with event: NSEvent) { track(convert(event.locationInWindow, from: nil)) }

    override func mouseDown(with event: NSEvent) { press(event) }
    override func rightMouseDown(with event: NSEvent) { press(event) }
    override func mouseUp(with event: NSEvent) { release(event) }
    override func rightMouseUp(with event: NSEvent) { release(event) }

    private func press(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hit(p) != nil { track(p); return }
        if let anchor, anchor.contains(p), Date().timeIntervalSince(openedAt) < NSEvent.doubleClickInterval, let action = onAnchorDoubleClick {
            CDEMenu.close(); action(); return
        }
        CDEMenu.close()
    }

    private func release(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let h = hit(p), let i = h.item else { return }
        let item = levels[h.level].items[i]
        guard item.submenu == nil, let action = item.action else { return }
        CDEMenu.close()
        action()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        for l in levels { draw(l) }
    }

    private func bevel(_ r: NSRect, sunken: Bool) {
        (sunken ? Self.dark : Self.light).setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        (sunken ? Self.light : Self.dark).setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }

    private func drawPhoton(_ l: Level, isLast: Bool) {
        let f = l.frame
        NSColor.fromHex("#D8D8D8").setFill(); f.fill()
        NSColor.black.setFill(); f.frame()
        PhotonColors.bevel(f.insetBy(dx: 1, dy: 1), NSColor.fromHex("#F1F1F1"), NSColor.fromHex("#BFBFBF"))
        for (r, i) in rows(l) {
            let it = l.items[i]
            if it.isSeparator {
                NSColor.fromHex("#BFBFBF").setFill(); NSRect(x: f.minX + 1, y: r.minY + 1, width: f.width - 2, height: 1).fill()
                NSColor.black.setFill(); NSRect(x: f.minX, y: r.minY + 2, width: f.width, height: 1).fill()
                NSColor.fromHex("#F1F1F1").setFill(); NSRect(x: f.minX + 1, y: r.minY + 3, width: f.width - 2, height: 1).fill()
                continue
            }
            let bar = NSRect(x: r.minX + 1, y: r.minY, width: r.width - 2, height: CDEMenu.photonBar)
            let posted = l.armed == i && it.submenu != nil && !isLast
            (l.armed == i ? NSColor.fromHex(posted ? "#B3B3B3" : "#9BA9C9") : PhotonColors.well).setFill(); bar.fill()
            if let icon = it.icon {
                icon.draw(in: NSRect(x: f.minX + 12, y: bar.midY - 8, width: 16, height: 16), from: .zero,
                          operation: .sourceOver, fraction: it.enabled ? 1 : 0.5, respectFlipped: true, hints: nil)
            }
            text(it.title, NSRect(x: f.minX + CDEMenu.photonLabel, y: bar.minY, width: bar.maxX - f.minX - CDEMenu.photonLabel, height: bar.height),
                 centred: false, color: it.enabled ? .black : NSColor.fromHex("#8A8A8A"))
            if it.submenu != nil {
                let a = NSBezierPath(), x = bar.maxX - 12, y = bar.midY
                a.move(to: NSPoint(x: x, y: y - 4.5)); a.line(to: NSPoint(x: x + 5, y: y)); a.line(to: NSPoint(x: x, y: y + 4.5)); a.close()
                NSColor.black.setFill(); a.fill()
            }
        }
    }

    private func draw(_ l: Level) {
        if CDEMenu.look == .photon { drawPhoton(l, isLast: l.frame == levels.last?.frame); return }
        let f = l.frame
        Self.face.setFill(); f.fill()
        bevel(f, sunken: false)
        if let title = l.title {
            text(title, NSRect(x: f.minX, y: f.minY + 1, width: f.width, height: CDEMenu.titleH), centred: true, color: .black)
            NSColor.black.setFill()
            let ry = f.minY + 1 + CDEMenu.titleH
            NSRect(x: f.minX + 1, y: ry, width: f.width - 2, height: 1).fill()
            NSRect(x: f.minX + 1, y: ry + 2, width: f.width - 2, height: 1).fill()
        }
        for (r, i) in rows(l) {
            let it = l.items[i]
            if it.isSeparator {
                Self.dark.setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
                Self.light.setFill(); NSRect(x: r.minX, y: r.minY + 1, width: r.width, height: 1).fill()
                continue
            }
            if l.armed == i {
                Self.armedFill.setFill(); r.fill()
                bevel(r, sunken: true)
            }
            if let icon = it.icon {
                icon.draw(in: NSRect(x: r.minX + 3, y: r.minY + 3, width: 16, height: 16), from: .zero,
                          operation: .sourceOver, fraction: it.enabled ? 1 : 0.5, respectFlipped: true, hints: nil)
            }
            let tx = r.minX + 4 + (it.icon == nil ? 0 : 18)
            text(it.title, NSRect(x: tx, y: r.minY, width: r.maxX - tx, height: r.height), centred: false,
                 color: it.enabled ? .black : Self.insensitive)
            if it.submenu != nil { arrow(at: NSPoint(x: r.maxX - 13, y: r.midY - 5)) }
        }
    }

    private func text(_ s: String, _ r: NSRect, centred: Bool, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: CDEMenu.font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: attrs)
        let x = centred ? r.midX - size.width / 2 : r.minX
        (s as NSString).draw(at: NSPoint(x: x.rounded(), y: (r.midY - size.height / 2).rounded()), withAttributes: attrs)
    }

    /// The cascade arrow: a raised triangle, 8 × 10, lit along its upper edge.
    private func arrow(at o: NSPoint) {
        let tip = NSPoint(x: o.x + 8, y: o.y + 5)
        let upper = NSBezierPath(); upper.move(to: NSPoint(x: o.x + 0.5, y: o.y + 10)); upper.line(to: NSPoint(x: o.x + 0.5, y: o.y + 0.5)); upper.line(to: tip)
        Self.dark.setStroke(); upper.lineWidth = 1; upper.stroke()
        let lower = NSBezierPath(); lower.move(to: tip); lower.line(to: NSPoint(x: o.x + 1, y: o.y + 10))
        Self.light.setStroke(); lower.lineWidth = 1; lower.stroke()
    }
}
