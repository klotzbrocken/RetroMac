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

    private let face   = NSColor(calibratedWhite: 0.847, alpha: 1)
    private let dark   = NSColor(calibratedWhite: 0.502, alpha: 1)
    private let darker = NSColor(calibratedWhite: 0.333, alpha: 1)
    private let strLt  = NSColor(calibratedWhite: 0.929, alpha: 1)
    private let strDk  = NSColor(calibratedWhite: 0.741, alpha: 1)
    private let titleFont = NSFont(name: "Charcoal", size: 12)
        ?? NSFont(name: "ChicagoFLF", size: 12) ?? .boldSystemFont(ofSize: 12)
    private let boxS: CGFloat = 13

    private var barRect: NSRect { NSRect(x: 0, y: bounds.height - Self.barH, width: bounds.width, height: Self.barH) }
    private var boxY: CGFloat { bounds.height - Self.barH + (Self.barH - boxS) / 2 }
    private var closeRect: NSRect { NSRect(x: 8, y: boxY, width: boxS, height: boxS) }
    private var zoomRect: NSRect { NSRect(x: bounds.width - 7 - boxS, y: boxY, width: boxS, height: boxS) }
    private var collapseRect: NSRect { NSRect(x: zoomRect.minX - 5 - boxS, y: boxY, width: boxS, height: boxS) }

    override var isOpaque: Bool { false }

    private func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); NSBezierPath(rect: r).fill() }
    private func bevelBox(_ r: NSRect) {
        fill(r, face)
        fill(NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1), .white)     // top
        fill(NSRect(x: r.minX, y: r.minY, width: 1, height: r.height), .white)         // left
        fill(NSRect(x: r.minX, y: r.minY, width: r.width, height: 1), dark)            // bottom
        fill(NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height), dark)       // right
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = barRect
        fill(bar, face)
        // pinstripes
        var y = bar.minY + 1
        while y < bar.maxY - 1 { fill(NSRect(x: 1, y: y, width: bounds.width - 2, height: 1), strLt)
                                 fill(NSRect(x: 1, y: y + 1, width: bounds.width - 2, height: 1), strDk); y += 2 }
        // 1px black window frame + separator under the bar
        NSColor.black.setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        fill(NSRect(x: 0, y: bar.minY, width: bounds.width, height: 1), dark)
        // control boxes
        bevelBox(closeRect); bevelBox(collapseRect); bevelBox(zoomRect)
        let z = zoomRect.insetBy(dx: 2, dy: 2)
        darker.setStroke(); NSBezierPath(rect: z.insetBy(dx: 0.5, dy: 0.5)).stroke()
        fill(NSRect(x: collapseRect.minX + 3, y: collapseRect.midY, width: boxS - 6, height: 1), darker)
        // centered title plaque
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.black]
        let s = title.size(withAttributes: attrs)
        let px = (bounds.width - s.width) / 2
        fill(NSRect(x: px - 8, y: bar.minY, width: s.width + 16, height: Self.barH), face)
        title.draw(at: NSPoint(x: px, y: bar.midY - s.height / 2), withAttributes: attrs)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return super.hitTest(point) }
        let p = convert(point, from: sv)
        if barRect.contains(p) { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Generous hit areas — the 13px Platinum boxes were fiddly to click.
        if closeRect.insetBy(dx: -6, dy: -6).contains(p) { onClose?(); return }
        if collapseRect.insetBy(dx: -4, dy: -6).contains(p) { onCollapse?(); return }
        if zoomRect.insetBy(dx: -4, dy: -6).contains(p) { onZoom?(); return }
        if barRect.contains(p) { window?.performDrag(with: event); return }
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
    private func captionBtn(_ r: NSRect, red: Bool) {
        if red { vgrad(r, NSColor(calibratedRed: 0.969, green: 0.702, blue: 0.620, alpha: 1),
                       NSColor(calibratedRed: 0.890, green: 0.373, blue: 0.267, alpha: 1),
                       NSColor(calibratedRed: 0.769, green: 0.220, blue: 0.165, alpha: 1)) }
        else { vgrad(r, NSColor(calibratedRed: 0.361, green: 0.690, blue: 1.0, alpha: 1),
                     NSColor(calibratedRed: 0.114, green: 0.388, blue: 0.941, alpha: 1),
                     NSColor(calibratedRed: 0.043, green: 0.275, blue: 0.812, alpha: 1)) }
        NSColor(white: 1, alpha: 0.6).setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
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
        // caption buttons (minimise omitted: the floating TV window has no taskbar entry)
        captionBtn(maxRect, red: false); captionBtn(closeRect, red: true)
        let white = NSColor.white
        white.setStroke()                                                                            // maximise
        let mr = maxRect.insetBy(dx: 5, dy: 5)
        let mp = NSBezierPath(rect: mr); mp.lineWidth = 1; mp.stroke()
        fill(NSRect(x: mr.minX, y: mr.maxY - 3, width: mr.width, height: 3), white)
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

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) { onClose?(); return }
        if maxRect.contains(p) { onMax?(); return }
        if barRect.contains(p) { window?.performDrag(with: event); return }
    }
}
