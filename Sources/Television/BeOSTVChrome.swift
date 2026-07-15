import AppKit

/// Borderless window that can still become key (needed so the WKWebView / player stays
/// interactive without a native title bar).
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// BeOS chrome container: a transparent view with a protruding yellow Lasche at the top-left
/// and the real content (video / web view) hosted below it. Drag the tab to move, click the
/// close box to close.
final class BeOSTVChromeView: NSView {
    static let tabH: CGFloat = 24
    var title = ""
    var onClose: (() -> Void)?

    private var tabW: CGFloat { min(max(120, title.size(withAttributes: [.font: titleFont]).width + 46), 260) }
    private let titleFont = NSFont(name: "Helvetica-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)
    // AppKit default coords (origin bottom-left): the tab sits at the TOP.
    private var tabRect: NSRect { NSRect(x: 0, y: bounds.height - Self.tabH, width: tabW, height: Self.tabH) }
    private var closeRect: NSRect { NSRect(x: 8, y: bounds.height - Self.tabH + (Self.tabH - 13) / 2, width: 13, height: 13) }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let t = tabRect
        NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(rect: t).fill()
        NSColor(calibratedWhite: 0.16, alpha: 1).setStroke()
        NSBezierPath(rect: t.insetBy(dx: 0.5, dy: 0.5)).stroke()
        // close box
        let c = closeRect
        NSColor(calibratedRed: 0.92, green: 0.73, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(rect: c).fill()
        NSColor(calibratedWhite: 0.16, alpha: 1).setStroke()
        NSBezierPath(rect: c.insetBy(dx: 0.5, dy: 0.5)).stroke()
        // title
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1)]
        let s = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: c.maxX + 8, y: t.midY - s.height / 2), withAttributes: attrs)
    }

    // Only the tab strip is interactive here; everything below passes through to the content.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return super.hitTest(point) }
        let p = convert(point, from: sv)
        if tabRect.contains(p) { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) { onClose?(); return }
        if tabRect.contains(p) { window?.performDrag(with: event); return }
    }
}

/// Mac OS 9 (Platinum) chrome container: a full-width pinstripe title bar with the close box
/// left and collapse (WindowShade) + zoom boxes right; the content sits below.
final class Mac9TVChromeView: NSView {
    static let barH: CGFloat = 22
    var title = ""
    var onClose: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onZoom: (() -> Void)?

    // Colors measured from the Mac OS 9 UI Kit (Figma) title bar.
    private let face   = NSColor(calibratedWhite: 0.953, alpha: 1)          // #F3F3F3 light plate
    private let dark   = NSColor(calibratedWhite: 0.502, alpha: 1)
    private let boxBP  = NSColor(calibratedRed: 0.329, green: 0.329, blue: 0.529, alpha: 1) // #545487 bevel
    private let boxHi  = NSColor(calibratedRed: 0.855, green: 0.855, blue: 1.0, alpha: 1)   // #DADAFF highlight
    private let boxFace = NSColor(calibratedWhite: 0.753, alpha: 1)         // #C0C0C0 box face
    private let botShadow = NSColor(calibratedRed: 0.702, green: 0.702, blue: 0.855, alpha: 1) // #B3B3DA
    private let strLt  = NSColor(calibratedWhite: 0.953, alpha: 1)          // #F3F3F3
    private let strDk  = NSColor(calibratedWhite: 0.467, alpha: 1)          // #777777
    private let titleFont = NSFont(name: "Charcoal", size: 12)
        ?? NSFont(name: "ChicagoFLF", size: 12) ?? .boldSystemFont(ofSize: 12)
    private let boxS: CGFloat = 11
    private var tracker = ChromeButtonTracker()

    private var barRect: NSRect { NSRect(x: 0, y: bounds.height - Self.barH, width: bounds.width, height: Self.barH) }
    private var boxY: CGFloat { bounds.height - Self.barH + (Self.barH - boxS) / 2 }
    private var closeRect: NSRect { NSRect(x: 8, y: boxY, width: boxS, height: boxS) }
    private var zoomRect: NSRect { NSRect(x: bounds.width - 7 - boxS, y: boxY, width: boxS, height: boxS) }
    private var collapseRect: NSRect { NSRect(x: zoomRect.minX - 5 - boxS, y: boxY, width: boxS, height: boxS) }

    override var isOpaque: Bool { false }

    private func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); NSBezierPath(rect: r).fill() }
    /// Platinum control box — shared with the WebApp Mac window via `ClassicMacChrome`.
    private func bevelBox(_ r: NSRect, state: ChromeButtonState = .normal) {
        ClassicMacChrome.bevelBox(r, state: state)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = barRect
        fill(bar, face)
        // pinstripes
        var y = bar.minY + 1
        while y < bar.maxY - 1 { fill(NSRect(x: 1, y: y, width: bounds.width - 2, height: 1), strLt)
                                 fill(NSRect(x: 1, y: y + 1, width: bounds.width - 2, height: 1), strDk); y += 2 }
        // 1px black window frame + light-purple shadow line under the bar
        NSColor.black.setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        fill(NSRect(x: 0, y: bar.minY, width: bounds.width, height: 1), botShadow)
        // control boxes (interactive: close left, collapse + zoom right) with hover/press
        tracker.reset()
        tracker.add(.close, closeRect.insetBy(dx: -4, dy: -4), interactive: true)
        tracker.add(.collapse, collapseRect.insetBy(dx: -2, dy: -3), interactive: true)
        tracker.add(.zoom, zoomRect.insetBy(dx: -2, dy: -3), interactive: true)
        bevelBox(closeRect, state: tracker.state(for: .close))
        bevelBox(collapseRect, state: tracker.state(for: .collapse))
        bevelBox(zoomRect, state: tracker.state(for: .zoom))
        // zoom: small nested square in the upper-left of the box face
        let zsq = NSRect(x: zoomRect.minX + 2, y: zoomRect.maxY - 2 - 4, width: 4, height: 4)
        fill(zsq, boxFace); boxBP.setStroke(); NSBezierPath(rect: zsq.insetBy(dx: 0.5, dy: 0.5)).stroke()
        // collapse: single WindowShade bar
        fill(NSRect(x: collapseRect.minX + 2, y: collapseRect.midY, width: boxS - 4, height: 1), boxBP)
        // centered title plaque (light, interrupts the stripes)
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.black]
        let s = title.size(withAttributes: attrs)
        let px = (bounds.width - s.width) / 2
        fill(NSRect(x: px - 8, y: bar.minY, width: s.width + 16, height: Self.barH), strLt)
        title.draw(at: NSPoint(x: px, y: bar.midY - s.height / 2), withAttributes: attrs)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return super.hitTest(point) }
        let p = convert(point, from: sv)
        if barRect.contains(p) { return self }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        if tracker.mouseMoved(to: convert(event.locationInWindow, from: nil)) { needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) {
        if tracker.mouseExited() { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if tracker.hitTest(p) != nil {          // press a control box (fires on mouse-up-inside)
            if tracker.mouseDown(at: p) { needsDisplay = true }
            return
        }
        if barRect.contains(p) { window?.performDrag(with: event); return }
    }

    override func mouseDragged(with event: NSEvent) {
        if tracker.mouseDragged(to: convert(event.locationInWindow, from: nil)) { needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        let r = tracker.mouseUp(at: convert(event.locationInWindow, from: nil))
        if r.needsRedraw { needsDisplay = true }
        switch r.fire {
        case .close: onClose?()
        case .collapse: onCollapse?()
        case .zoom: onZoom?()
        default: break
        }
    }
}

/// Windows XP (Luna Blue) chrome container: a full-width gradient title bar with a system
/// icon left and minimise / maximise / close caption buttons right; the content sits below,
/// inset by the 4px blue sizing frame.
final class WinXPTVChromeView: NSView {
    static let barH: CGFloat = 30
    static let border: CGFloat = 4
    var title = ""
    var onClose: (() -> Void)?
    var onMin: (() -> Void)?
    var onMax: (() -> Void)?

    private let titleFont = NSFont(name: "Trebuchet MS", size: 13)
        ?? NSFont(name: "Segoe UI Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
    private let btnS: CGFloat = 21
    private let frameBlue = NSColor(calibratedRed: 0.031, green: 0.192, blue: 0.851, alpha: 1)
    private var tracker = ChromeButtonTracker()

    private var barRect: NSRect { NSRect(x: 0, y: bounds.height - Self.barH, width: bounds.width, height: Self.barH) }
    private var btnY: CGFloat { bounds.height - Self.barH + (Self.barH - btnS) / 2 }
    private var closeRect: NSRect { NSRect(x: bounds.width - Self.border - 23, y: btnY, width: 23, height: btnS) }
    private var maxRect: NSRect { NSRect(x: closeRect.minX - 2 - btnS, y: btnY, width: btnS, height: btnS) }
    private var minRect: NSRect { NSRect(x: maxRect.minX - 2 - btnS, y: btnY, width: btnS, height: btnS) }

    override var isOpaque: Bool { false }

    private func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); NSBezierPath(rect: r).fill() }
    private func vgrad(_ r: NSRect, _ top: NSColor, _ mid: NSColor, _ bot: NSColor) {
        let g = NSGradient(colors: [top, mid, bot], atLocations: [0, 0.5, 1], colorSpace: .deviceRGB)
        g?.draw(in: NSBezierPath(rect: r), angle: -90)
    }
    private func captionBtn(_ r: NSRect, red: Bool, state: ChromeButtonState = .normal) {
        var top: NSColor, mid: NSColor, bot: NSColor
        if red { top = NSColor(calibratedRed: 0.969, green: 0.702, blue: 0.620, alpha: 1)
                 mid = NSColor(calibratedRed: 0.890, green: 0.373, blue: 0.267, alpha: 1)
                 bot = NSColor(calibratedRed: 0.769, green: 0.220, blue: 0.165, alpha: 1) }
        else   { top = NSColor(calibratedRed: 0.361, green: 0.690, blue: 1.0, alpha: 1)
                 mid = NSColor(calibratedRed: 0.114, green: 0.388, blue: 0.941, alpha: 1)
                 bot = NSColor(calibratedRed: 0.043, green: 0.275, blue: 0.812, alpha: 1) }
        let W = NSColor(calibratedWhite: 1, alpha: 1), K = NSColor(calibratedWhite: 0, alpha: 1)
        switch state {
        case .hovered:  top = top.blended(withFraction: 0.20, of: W) ?? top
                        mid = mid.blended(withFraction: 0.14, of: W) ?? mid
                        bot = bot.blended(withFraction: 0.10, of: W) ?? bot
        case .pressed:  top = top.blended(withFraction: 0.28, of: K) ?? top
                        mid = mid.blended(withFraction: 0.24, of: K) ?? mid
                        bot = bot.blended(withFraction: 0.20, of: K) ?? bot
        default:        break
        }
        vgrad(r, top, mid, bot)
        // Subtle dark-blue outline (a white rim reads as a stuck-on border).
        NSColor(calibratedRed: 0.03, green: 0.13, blue: 0.42, alpha: 0.55).setStroke()
        NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        fill(bounds, frameBlue)   // 4px sizing frame shows around the inset content
        let bar = barRect
        vgrad(bar, NSColor(calibratedRed: 0.035, green: 0.592, blue: 1.0, alpha: 1),
              NSColor(calibratedRed: 0.0, green: 0.325, blue: 0.933, alpha: 1),
              NSColor(calibratedRed: 0.0, green: 0.239, blue: 0.824, alpha: 1))
        // system icon
        let sysi = NSRect(x: 6, y: bar.midY - 8, width: 16, height: 16)
        fill(sysi, NSColor(calibratedRed: 0.81, green: 0.88, blue: 1.0, alpha: 1))
        // caption buttons: minimise / maximise / close (Luna blue, close red) — all interactive
        tracker.reset()
        tracker.add(.minimize, minRect, interactive: true)
        tracker.add(.maximize, maxRect, interactive: true)
        tracker.add(.close, closeRect, interactive: true)
        captionBtn(minRect, red: false, state: tracker.state(for: .minimize))
        captionBtn(maxRect, red: false, state: tracker.state(for: .maximize))
        captionBtn(closeRect, red: true, state: tracker.state(for: .close))
        let white = NSColor.white
        white.setStroke()                                                                            // maximise
        let mr = maxRect.insetBy(dx: 5, dy: 5)
        let mp = NSBezierPath(rect: mr); mp.lineWidth = 1; mp.stroke()
        fill(NSRect(x: mr.minX, y: mr.maxY - 3, width: mr.width, height: 3), white)
        // minimise: a short bar along the bottom of the button (rolls the window up, WindowShade)
        let nr = minRect.insetBy(dx: 5, dy: 5)
        fill(NSRect(x: nr.minX, y: nr.minY, width: nr.width, height: 2), white)
        let cp = NSBezierPath(); cp.lineWidth = 2; let c = NSPoint(x: closeRect.midX, y: closeRect.midY); let d: CGFloat = 5
        cp.move(to: NSPoint(x: c.x - d, y: c.y - d)); cp.line(to: NSPoint(x: c.x + d, y: c.y + d))
        cp.move(to: NSPoint(x: c.x - d, y: c.y + d)); cp.line(to: NSPoint(x: c.x + d, y: c.y - d))
        white.setStroke(); cp.stroke()
        // title text
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.white]
        let s = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: sysi.maxX + 6, y: bar.midY - s.height / 2), withAttributes: attrs)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return super.hitTest(point) }
        let p = convert(point, from: sv)
        if barRect.contains(p) { return self }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        if tracker.mouseMoved(to: convert(event.locationInWindow, from: nil)) { needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) {
        if tracker.mouseExited() { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if tracker.hitTest(p) != nil {          // press a caption button (fires on mouse-up-inside)
            if tracker.mouseDown(at: p) { needsDisplay = true }
            return
        }
        if barRect.contains(p) { window?.performDrag(with: event); return }
    }

    override func mouseDragged(with event: NSEvent) {
        if tracker.mouseDragged(to: convert(event.locationInWindow, from: nil)) { needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        let r = tracker.mouseUp(at: convert(event.locationInWindow, from: nil))
        if r.needsRedraw { needsDisplay = true }
        switch r.fire {
        case .close: onClose?()
        case .maximize: onMax?()
        case .minimize: onMin?()
        default: break
        }
    }
}
