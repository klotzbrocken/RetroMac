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
    /// `maxWidth` bounds the plaque (text included): a title longer than that is shortened in
    /// the middle, the way the Finder shortened file names, so it never runs over the boxes.
    static func titlePlaque(_ title: String, bar: NSRect, font: NSFont, maxWidth: CGFloat? = nil) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let full = title.size(withAttributes: attrs)
        let textLimit = maxWidth.map { max(0, $0 - 16) } ?? .greatestFiniteMagnitude
        let textWidth = min(full.width, textLimit)
        let px = bar.minX + (bar.width - textWidth) / 2
        fill(NSRect(x: px - 8, y: bar.minY, width: textWidth + 16, height: bar.height), plaque)
        // draw(in:) respects the current context's flipped-ness, so this works in both views.
        let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingMiddle
        var a = attrs; a[.paragraphStyle] = style
        let ty = bar.minY + (bar.height - full.height) / 2
        (title as NSString).draw(in: NSRect(x: px, y: ty, width: textWidth, height: full.height),
                                 withAttributes: a)
    }

    /// The width a plaque will take for `title` under `maxWidth`, for tests and layout.
    static func plaqueWidth(_ title: String, font: NSFont, maxWidth: CGFloat?) -> CGFloat {
        let full = title.size(withAttributes: [.font: font]).width
        let limit = maxWidth.map { max(0, $0 - 16) } ?? .greatestFiniteMagnitude
        return min(full, limit) + 16
    }
}

// MARK: - The bar as os9.ca draws it

/// The Platinum title bar exactly as the Applications widget has it, which takes its CSS from
/// os9.ca's window.min.css: a #DADADA bar inside a 1 px black frame with a white/grey bevel,
/// a 12 px band of white/#737373 pinstripes 5 px down, gradient-faced boxes with a dark
/// outline and their own drop shadow, and the title (with a proxy icon) on a gap in the
/// stripes. Flipped coordinates (y grows down); the bar's bottom edge joins the window.
enum PlatinumBar {
    static let bar       = NSColor(srgbRed: 0.855, green: 0.855, blue: 0.855, alpha: 1)   // #DADADA
    static let stripeLt  = NSColor.white
    static let stripeDk  = NSColor(srgbRed: 0.451, green: 0.451, blue: 0.451, alpha: 1)   // #737373
    static let frame     = NSColor.black
    static let frameBlur = NSColor(srgbRed: 0.322, green: 0.322, blue: 0.322, alpha: 1)   // #525252
    static let bevelHi   = NSColor.white
    static let bevelLo   = NSColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)         // #999999
    static let boxLine   = NSColor(srgbRed: 0.133, green: 0.133, blue: 0.133, alpha: 1)   // #222222
    static let glyph     = NSColor(srgbRed: 0.125, green: 0.125, blue: 0.125, alpha: 1)   // #202020
    static let boxSize: CGFloat = 11   // 9 px face + 1 px outline each side
    static let height: CGFloat = 22

    private static func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); r.fill() }

    /// The boxes' places in a bar of `width`: close 5 px in from the left, the zoom and the
    /// collapse box at the right with the widget's margins, all 4 px down from the top line.
    static func boxRects(width w: CGFloat) -> (close: NSRect, zoom: NSRect, collapse: NSRect) {
        let s = boxSize, y: CGFloat = 5
        let close = NSRect(x: 6, y: y, width: s, height: s)
        let collapse = NSRect(x: w - 6 - s, y: y, width: s, height: s)
        let zoom = NSRect(x: collapse.minX - 8 - s, y: y, width: s, height: s)
        return (close, zoom, collapse)
    }

    /// The bar's own picture: fill, frame, bevel, stripes. Boxes and title go on top.
    static func drawBar(_ b: NSRect, active: Bool) {
        fill(b, bar)
        // Frame: top and both sides (the bottom joins the window), and the bevel inside it.
        let line = active ? frame : frameBlur
        fill(NSRect(x: b.minX, y: b.minY, width: b.width, height: 1), line)
        fill(NSRect(x: b.minX, y: b.minY, width: 1, height: b.height), line)
        fill(NSRect(x: b.maxX - 1, y: b.minY, width: 1, height: b.height), line)
        fill(NSRect(x: b.minX + 1, y: b.minY + 1, width: b.width - 3, height: 1), bevelHi)
        fill(NSRect(x: b.minX + 1, y: b.minY + 1, width: 1, height: b.height - 1), bevelHi)
        fill(NSRect(x: b.maxX - 2, y: b.minY + 1, width: 1, height: b.height - 1), bevelLo)
        // The pinstripe band: 12 rows from 5 px down, white and grey by turns.
        for row in 0..<12 {
            fill(NSRect(x: b.minX + 2, y: b.minY + 5 + CGFloat(row), width: b.width - 4, height: 1), row % 2 == 0 ? stripeLt : stripeDk)
        }
    }

    /// One control box. Active: outline #222, a diagonal #999→white face, a 1 px inset
    /// (#CCC top-left, #888 bottom-right) and a drop shadow (#808080 above-left, white
    /// below-right). Inactive: the outline goes #525252 and the shadows go.
    static func drawBox(_ r: NSRect, active: Bool, state: ChromeButtonState = .normal) {
        if active {
            fill(NSRect(x: r.minX - 1, y: r.minY - 1, width: r.width + 1, height: 1), NSColor(white: 0.502, alpha: 1))
            fill(NSRect(x: r.minX - 1, y: r.minY - 1, width: 1, height: r.height + 1), NSColor(white: 0.502, alpha: 1))
            fill(NSRect(x: r.minX, y: r.maxY, width: r.width + 1, height: 1), .white)
            fill(NSRect(x: r.maxX, y: r.minY, width: 1, height: r.height + 1), .white)
        }
        fill(r, active ? boxLine : frameBlur)
        let face = r.insetBy(dx: 1, dy: 1)
        let pressed = state == .pressed
        let start = NSColor(white: pressed ? 0.45 : 0.6, alpha: 1), end = NSColor(white: pressed ? 0.85 : 1.0, alpha: 1)
        NSGradient(starting: pressed ? end : start, ending: pressed ? start : end)?.draw(in: face, angle: 45)
        if active {
            fill(NSRect(x: face.minX, y: face.minY, width: face.width, height: 1), NSColor(white: 0.8, alpha: 1))
            fill(NSRect(x: face.minX, y: face.minY, width: 1, height: face.height), NSColor(white: 0.8, alpha: 1))
            fill(NSRect(x: face.minX, y: face.maxY - 1, width: face.width, height: 1), NSColor(white: 0.533, alpha: 1))
            fill(NSRect(x: face.maxX - 1, y: face.minY, width: 1, height: face.height), NSColor(white: 0.533, alpha: 1))
        }
    }

    /// The zoom glyph: the bottom and right edge of a 5 px square in the face's top-left corner.
    static func zoomGlyph(in r: NSRect, active: Bool) {
        let c = active ? glyph : frameBlur
        fill(NSRect(x: r.minX + 2, y: r.minY + 6, width: 5, height: 1), c)
        fill(NSRect(x: r.minX + 6, y: r.minY + 2, width: 1, height: 5), c)
    }

    /// The collapse glyph: two lines across the face, a row apart.
    static func collapseGlyph(in r: NSRect, active: Bool) {
        let c = active ? glyph : frameBlur
        fill(NSRect(x: r.minX + 2, y: r.minY + 5, width: r.width - 4, height: 1), c)
        fill(NSRect(x: r.minX + 2, y: r.minY + 7, width: r.width - 4, height: 1), c)
    }

    /// The title on its gap in the stripes: a #DADADA plaque, 15 px tall, the proxy icon at 16 px
    /// before the text, Charcoal 13; an inactive bar shows it at half strength. Kept between
    /// `minX` and `maxX`, the title shortened in the middle when it would not fit.
    static func drawTitle(_ title: String, icon: NSImage?, in b: NSRect, active: Bool, minX: CGFloat, maxX: CGFloat) {
        let font = NSFont(name: "Charcoal", size: 13) ?? NSFont(name: "ChicagoFLF", size: 13) ?? .systemFont(ofSize: 13)
        let colour = NSColor.black.withAlphaComponent(active ? 1 : 0.5)
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour, .paragraphStyle: style]
        let iconW: CGFloat = icon == nil ? 0 : 21   // 16 px icon and its gap
        let textLimit = max(0, (maxX - minX) - 16 - iconW)
        let textW = min(title.size(withAttributes: attrs).width.rounded(.up), textLimit)
        let plaqueW = textW + 16 + iconW
        let px = (b.midX - plaqueW / 2).rounded()
        let plaque = NSRect(x: px, y: b.minY + 4, width: plaqueW, height: 15)
        fill(plaque, bar)
        if let icon {
            icon.draw(in: NSRect(x: px + 5, y: b.minY + 3, width: 16, height: 16), from: .zero, operation: .sourceOver,
                      fraction: active ? 1 : 0.5, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        }
        let textH = font.ascender - font.descender
        (title as NSString).draw(in: NSRect(x: px + 8 + iconW, y: b.minY + (height - textH) / 2, width: textW, height: textH), withAttributes: attrs)
    }
}
