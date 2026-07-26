import AppKit

/// Shared drawing helpers for the classic Mac OS (System 6 / Platinum) window chrome, so the
/// TV window (`Mac9TVChromeView`) and real WebApp windows (`WebAppChromeView`) render an
/// identical title bar. Colours are measured from the Mac OS 9 UI kit; the pinstripe and
/// control boxes are drawn — no Apple-copyrighted bitmap patterns are used. classic.css (MIT)
/// and the public-domain ChicagoFLF font informed the reference look.
///
/// All helpers are coordinate-agnostic (they only fill/stroke the rects the caller passes), so
/// they work in both the TV view (default coords) and the flipped WebApp view.
enum ClassicMacChrome {

    // Platinum palette
    static let face      = NSColor(calibratedWhite: 0.953, alpha: 1)          // #F3F3F3 light plate
    // Control boxes: DARK outline + white inner highlight + light-grey face (measured off os9.ca),
    // not the lavender/purple bevel — that read completely wrong.
    static let boxBP     = NSColor(calibratedWhite: 0.165, alpha: 1)          // #2A2A2A dark outline
    static let boxHi     = NSColor(calibratedWhite: 1.0, alpha: 1)            // #FFFFFF inner highlight
    static let boxFace   = NSColor(calibratedWhite: 0.847, alpha: 1)          // #D8D8D8 box face
    static let botShadow = NSColor(calibratedRed: 0.702, green: 0.702, blue: 0.855, alpha: 1) // #B3B3DA
    // STRONG platinum pinstripes (os9.ca): near-white + mid-grey, clearly visible.
    static let stripeLt  = NSColor(calibratedWhite: 0.957, alpha: 1)          // #F4F4F4
    static let stripeDk  = NSColor(calibratedWhite: 0.490, alpha: 1)          // #7D7D7D
    static let plaque    = NSColor(calibratedWhite: 0.863, alpha: 1)          // #DCDCDC grey title plate

    /// Standard Platinum control-box side length.
    static let boxSize: CGFloat = 11

    private static func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); NSBezierPath(rect: r).fill() }

    /// The horizontal pinstripe fill that runs across a Platinum title bar.
    static func pinstripes(in bar: NSRect) {
        var y = bar.minY + 1
        while y < bar.maxY - 1 {
            fill(NSRect(x: bar.minX + 1, y: y,     width: bar.width - 2, height: 1), stripeLt)
            fill(NSRect(x: bar.minX + 1, y: y + 1, width: bar.width - 2, height: 1), stripeDk)
            y += 2
        }
    }

    /// Platinum control box: gray face, 1px blue-purple border, 1px lavender highlight inside.
    /// `pressed` sinks the box (darker face); `hovered` lifts the face slightly.
    static func bevelBox(_ r: NSRect, state: ChromeButtonState = .normal) {
        let black = NSColor(calibratedWhite: 0, alpha: 1), white = NSColor(calibratedWhite: 1, alpha: 1)
        switch state {
        case .pressed:
            fill(r, boxFace.blended(withFraction: 0.20, of: black) ?? boxFace)
            boxBP.setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            boxHi.setStroke(); NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5)).stroke()
        case .hovered:
            fill(r, boxFace.blended(withFraction: 0.12, of: white) ?? boxFace)
            boxHi.setStroke(); NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5)).stroke()
            boxBP.setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        default:
            fill(r, boxFace)
            boxHi.setStroke(); NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5)).stroke()
            boxBP.setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    /// The nested-square glyph in the zoom box (upper-left corner of the box face).
    static func zoomGlyph(in box: NSRect) {
        let z = NSRect(x: box.minX + 2, y: box.maxY - 2 - 4, width: 4, height: 4)
        fill(z, boxFace); boxBP.setStroke(); NSBezierPath(rect: z.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    /// The single WindowShade bar in the collapse box.
    static func collapseGlyph(in box: NSRect) {
        fill(NSRect(x: box.minX + 2, y: box.midY, width: boxSize - 4, height: 1), boxBP)
    }

    /// Draw the centred title over a light plaque that interrupts the pinstripes.
    static func titlePlaque(_ title: String, bar: NSRect, font: NSFont) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let s = title.size(withAttributes: attrs)
        let px = bar.minX + (bar.width - s.width) / 2
        fill(NSRect(x: px - 8, y: bar.minY, width: s.width + 16, height: bar.height), plaque)
        // draw(in:) respects the current context's flipped-ness, so this works in both views.
        let style = NSMutableParagraphStyle(); style.alignment = .center
        var a = attrs; a[.paragraphStyle] = style
        let ty = bar.minY + (bar.height - s.height) / 2
        (title as NSString).draw(in: NSRect(x: bar.minX, y: ty, width: bar.width, height: s.height),
                                 withAttributes: a)
    }
}
