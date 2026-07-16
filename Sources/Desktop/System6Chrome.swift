import AppKit

/// Authentic **Mac System 6** (1-bit black-and-white) window chrome — distinct from the
/// Mac OS 8/9 "Platinum" look in `ClassicMacChrome`. Modelled on system.css (MIT, Sakun
/// Acharige): a white title bar filled with horizontal black "racing stripes", a centred title
/// on a white plaque that interrupts the stripes (Chicago font), a hollow-square close box at
/// the top-left, NO zoom/collapse boxes, and a thin 1px black window frame. Inactive windows
/// drop the stripes and grey the title.
///
/// All helpers are coordinate-agnostic (they only fill/stroke the rects passed in), so they work
/// in both the flipped WebApp view and the default-coords TV view — same contract as
/// `ClassicMacChrome`.
enum System6Chrome {

    static let black = NSColor.black
    static let white = NSColor.white
    static let inactiveText = NSColor(calibratedWhite: 0.647, alpha: 1)   // #A5A5A5 (system.css)

    /// Close/zoom box side length. system.css boxes are ~(titlebar − 4) — near-full-height
    /// squares in the ~20px bar.
    static let boxSize: CGFloat = 15

    /// The System 6 title font (Chicago), bundled with the Mac OS 6 theme; falls back gracefully.
    static var titleFont: NSFont {
        NSFont(name: "Chicago", size: 12)
            ?? NSFont(name: "ChiKareGo2", size: 12)
            ?? NSFont(name: "ChicagoFLF", size: 12)
            ?? .boldSystemFont(ofSize: 12)
    }

    private static func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); NSBezierPath(rect: r).fill() }

    /// The racing-stripe title bar: white ground with ~6 evenly-spaced horizontal black lines
    /// (active only). Draw the plaque + title on top afterwards.
    static func titleBar(_ bar: NSRect, active: Bool) {
        fill(bar, white)
        guard active else { return }
        // Fine racing stripes like system.css: 1px black hairlines every 2px, inset ~3px from the
        // top/bottom edges (a dense pinstripe field, not a few thick bars).
        var y = bar.minY + 3
        while y <= bar.maxY - 3 {
            fill(NSRect(x: bar.minX + 3, y: y, width: bar.width - 6, height: 1), black)
            y += 2
        }
    }

    /// Hollow-square close box (top-left). Pressed → draw the × (system.css shows it on :active).
    static func closeBox(_ r: NSRect, state: ChromeButtonState = .normal) {
        fill(r, white)
        black.setStroke()
        let p = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1.5; p.stroke()
        if state == .pressed {
            let x = NSBezierPath(); x.lineWidth = 1.5
            let i = r.insetBy(dx: 3.5, dy: 3.5)
            x.move(to: NSPoint(x: i.minX, y: i.minY)); x.line(to: NSPoint(x: i.maxX, y: i.maxY))
            x.move(to: NSPoint(x: i.minX, y: i.maxY)); x.line(to: NSPoint(x: i.maxX, y: i.minY))
            black.setStroke(); x.stroke()
        }
    }

    /// Resize / zoom box (top-right, per system.css): a hollow square with a small concentric
    /// square inside — the classic Mac "zoom" glyph. Maps to fullscreen (TV) / maximise (WebApp).
    static func resizeBox(_ r: NSRect, state: ChromeButtonState = .normal) {
        fill(r, white)
        black.setStroke()
        let outer = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); outer.lineWidth = 1.5; outer.stroke()
        // small concentric square in the upper-left of the box (zoom glyph)
        let g = NSRect(x: r.minX + 2.5, y: r.maxY - 2.5 - 4, width: 4, height: 4)
        let gp = NSBezierPath(rect: g); gp.lineWidth = 1; black.setStroke(); gp.stroke()
        if state == .pressed { fill(r.insetBy(dx: 3, dy: 3), black) }
    }

    /// Centred title over a white plaque that interrupts the stripes. `draw(in:)` respects the
    /// current context's flipped-ness, so this works in both chrome views.
    static func titlePlaque(_ title: String, bar: NSRect, font: NSFont, active: Bool) {
        let color = active ? black : inactiveText
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = title.size(withAttributes: attrs)
        let px = bar.minX + (bar.width - s.width) / 2
        // White plaque with a little horizontal padding, full bar height so it clears the stripes.
        fill(NSRect(x: px - 8, y: bar.minY, width: s.width + 16, height: bar.height), white)
        let style = NSMutableParagraphStyle(); style.alignment = .center
        var a = attrs; a[.paragraphStyle] = style
        let ty = bar.minY + (bar.height - s.height) / 2
        (title as NSString).draw(in: NSRect(x: bar.minX, y: ty, width: bar.width, height: s.height),
                                 withAttributes: a)
    }

    /// Thin 1px black window frame around the whole window (System 6 windows are white with a
    /// single black outline).
    static func windowFrame(_ b: NSRect) {
        black.setStroke()
        let p = NSBezierPath(rect: b.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1; p.stroke()
    }
}
