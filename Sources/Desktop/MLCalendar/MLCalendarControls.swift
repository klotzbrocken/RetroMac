import AppKit

// Aqua-10.8-style controls and the popover bubble. These are real-size (not 1.5×-scaled) because
// popovers and the settings window are separate windows.

/// Real-size font for popovers/settings (mlFont is calibrated for the scaled main window).
func mlPF(_ size: CGFloat, bold: Bool = false) -> NSFont { mlFont(size * 1.2, bold: bold) }

class MLFlip: NSView { override var isFlipped: Bool { true } }

final class MLClosure: NSObject {
    let f: () -> Void
    init(_ f: @escaping () -> Void) { self.f = f }
    @objc func run() { f() }
}

// MARK: - Popover

final class MLPopoverPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private final class MLBubble: NSView {
    var arrowOnLeft = true
    var arrowY: CGFloat = 40
    var footerH: CGFloat = 0
    static let arrowW: CGFloat = 11
    override var isFlipped: Bool { true }

    var bodyRect: NSRect {
        NSRect(x: arrowOnLeft ? Self.arrowW : 0, y: 0, width: bounds.width - Self.arrowW, height: bounds.height)
    }

    override func draw(_ dirty: NSRect) {
        let r = bodyRect.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        let ay = arrowY, aw = Self.arrowW
        let tip = arrowOnLeft ? r.minX - aw + 0.5 : r.maxX + aw - 0.5
        let base = arrowOnLeft ? r.minX : r.maxX
        path.move(to: NSPoint(x: base, y: ay - 9)); path.line(to: NSPoint(x: tip, y: ay)); path.line(to: NSPoint(x: base, y: ay + 9)); path.close()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        mlGradient(bounds, [(0, mlRGB(254, 254, 254)), (0.45, mlRGB(248, 248, 248)), (1, mlRGB(236, 236, 237))])
        if footerH > 0 {
            let f = NSRect(x: 0, y: bounds.height - footerH, width: bounds.width, height: footerH)
            mlGradient(f, [(0, mlRGB(240, 240, 241)), (1, mlRGB(228, 228, 230))])
            mlLine(NSRect(x: f.minX, y: f.minY, width: f.width, height: 1), mlRGB(218, 218, 220))
        }
        NSGraphicsContext.restoreGraphicsState()
        mlRGB(176, 176, 180, 0.9).setStroke(); path.lineWidth = 1; path.stroke()
    }
}

/// A bubble with an arrow, like Calendar's event popover. Closes on a click outside, on Esc and when the app deactivates.
final class MLPopover: NSObject {
    enum Preferred { case side, below }
    private var panel: MLPopoverPanel?
    private var monitors: [Any] = []
    var onClose: (() -> Void)?
    var isShown: Bool { panel?.isVisible == true }

    func show(_ content: NSView, footer: CGFloat, relativeTo rect: NSRect, of view: NSView, preferred: Preferred = .side) {
        guard let host = view.window else { return }
        let anchor = host.convertToScreen(view.convert(rect, to: nil))
        let vf = host.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let aw = MLBubble.arrowW
        let size = NSSize(width: content.frame.width + aw, height: content.frame.height)
        let rightRoom = vf.maxX - anchor.maxX, leftRoom = anchor.minX - vf.minX
        let onRight = preferred == .below ? true : rightRoom >= size.width + 4 || rightRoom >= leftRoom
        var origin = NSPoint(x: onRight ? anchor.maxX + 1 : anchor.minX - size.width - 1, y: 0)
        origin.y = min(max(anchor.midY - size.height / 2, vf.minY + 4), vf.maxY - size.height - 4)
        if preferred == .below { origin.y = min(max(anchor.minY - size.height - 4, vf.minY + 4), vf.maxY - size.height - 4); origin.x = max(vf.minX + 4, min(anchor.midX - aw - 24, vf.maxX - size.width - 4)) }

        let bubble = MLBubble(frame: NSRect(origin: .zero, size: size))
        bubble.arrowOnLeft = onRight
        bubble.footerH = footer
        // arrow measured from the bubble's top (flipped), pointing at the anchor
        bubble.arrowY = preferred == .below ? 22 : min(max(size.height - (anchor.midY - origin.y), 22), size.height - 22)
        content.frame.origin = NSPoint(x: onRight ? aw : 0, y: 0)
        bubble.addSubview(content)

        let p = MLPopoverPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.appearance = NSAppearance(named: .aqua)
        p.contentView = bubble
        p.onEscape = { [weak self] in self?.close() }
        p.level = host.level
        host.addChildWindow(p, ordered: .above)
        p.makeKeyAndOrderFront(nil)
        panel = p

        let outside: (NSEvent) -> Void = { [weak self] e in
            guard let self, let w = self.panel, e.window !== w else { return }
            // pop-up menus (repeat / calendar choices) are separate windows above the panel: clicks there are not "outside"
            if let ew = e.window, ew.level.rawValue >= NSWindow.Level.popUpMenu.rawValue || ew.parent === w || w.childWindows?.contains(ew) == true { return }
            self.close()
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { e in outside(e); return e }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.close() }) { monitors.append(m) }
        monitors.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.close() })
    }

    func close() {
        guard let p = panel else { return }
        panel = nil
        for m in monitors { if m is NSObjectProtocol, !(m is NSEvent) { NotificationCenter.default.removeObserver(m) } else { NSEvent.removeMonitor(m) } }
        monitors = []
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
        onClose?()
    }
}

// MARK: - Controls

class MLControl: NSControl {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var pressed = false { didSet { needsDisplay = true } }

    /// Highlight while held; the action fires on release inside the control.
    func track(_ e: NSEvent, _ done: (Bool) -> Void) {
        pressed = true
        var inside = true
        while let ev = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            inside = bounds.contains(convert(ev.locationInWindow, from: nil))
            if pressed != inside { pressed = inside }
            if ev.type == .leftMouseUp { break }
        }
        pressed = false
        done(inside)
    }
    override func accessibilityPerformPress() -> Bool { sendAction(action, to: target); return true }
}

final class MLButton: MLControl {
    var title: String { didSet { needsDisplay = true } }
    var isDefault = false
    init(_ title: String, _ f: @escaping () -> Void) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 20))
        let c = MLClosure(f); closure = c; target = c; action = #selector(MLClosure.run)
        setAccessibilityRole(.button); setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    private var closure: MLClosure?
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let p = NSBezierPath(roundedRect: r, xRadius: 4.5, yRadius: 4.5)
        if isDefault && isEnabled {
            mlGradient(bounds, [(0, mlRGB(178, 210, 248)), (0.5, mlRGB(104, 158, 232)), (1, mlRGB(120, 176, 244))], radius: 4.5)
        } else {
            let k: CGFloat = pressed ? 0.18 : 0
            mlGradient(bounds, [(0, mlMix(.white, .black, k)), (1, mlMix(mlRGB(222, 222, 222), .black, k))], radius: 4.5)
        }
        (isDefault && isEnabled ? mlRGB(52, 96, 170) : mlRGB(128, 128, 128)).setStroke(); p.lineWidth = 1; p.stroke()
        mlText(title, bounds, mlPF(10.5), isEnabled ? .black : mlRGB(150, 150, 150), align: .center)
    }
    override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        track(e) { if $0 { sendAction(action, to: target) } }
    }
}

final class MLCheck: MLControl {
    var on: Bool { didSet { needsDisplay = true; setAccessibilityValue(on ? 1 : 0) } }
    var title: String
    init(_ title: String = "", on: Bool, _ f: @escaping () -> Void) {
        self.title = title; self.on = on
        super.init(frame: NSRect(x: 0, y: 0, width: title.isEmpty ? 16 : 200, height: 18))
        let c = MLClosure(f); closure = c; target = c; action = #selector(MLClosure.run)
        setAccessibilityRole(.checkBox); setAccessibilityLabel(title.isEmpty ? nil : title); setAccessibilityValue(on ? 1 : 0)
    }
    required init?(coder: NSCoder) { fatalError() }
    private var closure: MLClosure?
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func draw(_ dirty: NSRect) {
        let box = NSRect(x: 1, y: (bounds.height - 14) / 2, width: 14, height: 14)
        let p = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        mlGradient(box, [(0, mlMix(.white, .black, pressed ? 0.15 : 0)), (1, mlRGB(226, 226, 226))], radius: 3)
        mlRGB(120, 120, 120, isEnabled ? 1 : 0.5).setStroke(); p.lineWidth = 1; p.stroke()
        if on {
            let c = NSBezierPath()
            c.move(to: NSPoint(x: box.minX + 3, y: box.midY + 0.5)); c.line(to: NSPoint(x: box.minX + 6, y: box.maxY - 3)); c.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 1.5))
            mlRGB(20, 20, 24, isEnabled ? 1 : 0.4).setStroke(); c.lineWidth = 2; c.lineCapStyle = .round; c.lineJoinStyle = .round; c.stroke()
        }
        if !title.isEmpty { mlText(title, NSRect(x: 22, y: 0, width: bounds.width - 22, height: bounds.height), mlPF(11), isEnabled ? .black : mlRGB(150, 150, 150)) }
    }
    override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        track(e) { if $0 { on.toggle(); sendAction(action, to: target) } }
    }
    override func keyDown(with e: NSEvent) { if e.keyCode == 49 { on.toggle(); sendAction(action, to: target) } else { super.keyDown(with: e) } }
}

/// Pop-up button: white pill with the blue Aqua arrow cap on the right.
final class MLPopup: MLControl {
    var items: [String] { didSet { needsDisplay = true } }
    var colors: [NSColor?] = []
    var index: Int { didSet { needsDisplay = true; setAccessibilityValue(items.indices.contains(index) ? items[index] : "") } }
    var plain = false                       // editor popover: text + arrows only, no pill
    private var closure: MLClosure?
    init(_ items: [String], index: Int, _ f: @escaping (Int) -> Void) {
        self.items = items; self.index = max(0, min(index, max(items.count - 1, 0)))
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 22))
        let c = MLClosure { [weak self] in if let s = self { f(s.index) } }; closure = c; target = c; action = #selector(MLClosure.run)
        setAccessibilityRole(.popUpButton); setAccessibilityValue(items.indices.contains(self.index) ? items[self.index] : "")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func draw(_ dirty: NSRect) {
        let text = items.indices.contains(index) ? items[index] : ""
        let cap: CGFloat = plain ? 12 : 18
        let tx: CGFloat = plain ? 2 : 8
        if !plain {
            let r = bounds.insetBy(dx: 0.5, dy: 0.5)
            let p = NSBezierPath(roundedRect: r, xRadius: 4.5, yRadius: 4.5)
            let k: CGFloat = pressed ? 0.16 : 0
            mlGradient(bounds, [(0, mlMix(.white, .black, k)), (1, mlMix(mlRGB(228, 228, 228), .black, k))], radius: 4.5)
            NSGraphicsContext.saveGraphicsState(); p.addClip()
            mlGradient(NSRect(x: bounds.maxX - cap - 1, y: 0, width: cap + 1, height: bounds.height), [(0, mlRGB(150, 190, 240)), (0.5, mlRGB(88, 144, 226)), (1, mlRGB(110, 166, 240))])
            NSGraphicsContext.restoreGraphicsState()
            mlRGB(120, 120, 120, isEnabled ? 1 : 0.5).setStroke(); p.lineWidth = 1; p.stroke()
        }
        var x = tx
        if colors.indices.contains(index), let c = colors[index] {
            let sw = NSRect(x: x, y: bounds.midY - 5, width: 14, height: 10)
            mlGradient(sw, [(0, mlMix(c, .white, 0.25)), (1, mlMix(c, .black, 0.15))], radius: 1.5)
            mlMix(c, .black, 0.5).setStroke(); NSBezierPath(roundedRect: sw.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5).stroke(); x += 19
        }
        mlText(text, NSRect(x: x, y: 0, width: bounds.width - x - cap - 4, height: bounds.height), mlPF(11), isEnabled ? .black : mlRGB(150, 150, 150))
        // arrows
        let cx = bounds.maxX - cap / 2 - (plain ? 0 : 0.5), cy = bounds.midY
        let a = NSBezierPath()
        a.move(to: NSPoint(x: cx - 3, y: cy - 1.5)); a.line(to: NSPoint(x: cx, y: cy - 5)); a.line(to: NSPoint(x: cx + 3, y: cy - 1.5)); a.close()
        a.move(to: NSPoint(x: cx - 3, y: cy + 1.5)); a.line(to: NSPoint(x: cx, y: cy + 5)); a.line(to: NSPoint(x: cx + 3, y: cy + 1.5)); a.close()
        (plain ? mlRGB(90, 90, 90) : NSColor.white).setFill(); a.fill()
    }

    override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        let m = NSMenu()
        m.font = mlPF(11)
        for (i, t) in items.enumerated() {
            let it = MLBlockItem(t) { [weak self] in
                guard let s = self else { return }
                s.index = i; s.sendAction(s.action, to: s.target)
            }
            if colors.indices.contains(i), let c = colors[i] {
                it.image = NSImage(size: NSSize(width: 14, height: 10), flipped: false) { r in c.setFill(); NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill(); return true }
            }
            it.state = i == index ? .on : .off
            m.addItem(it)
        }
        m.popUp(positioning: m.item(at: index), at: NSPoint(x: 0, y: bounds.height), in: self)
        pressed = false
    }
}
