import AppKit

/// **Mac OS X 10.0** window chrome, measured pixel for pixel from 10.0.4 screenshots
/// (guidebookgallery.org, the Finder and TextEdit windows).
///
/// The title bar is 23 px: a #CBCBCB top edge, 21 rows of white pinstripes darkening a little
/// toward the bottom, and a #919191 line under them. Its top corners are rounded by 6 px and a
/// #CBCBCB edge runs down either side. The traffic lights are 13 px gems, 22 px apart, the
/// first centred 16 px in from the left edge and 10 px below the top: black at the top of the
/// rim, a white gloss across the top third, the colour deepening under it and glowing back up
/// toward the bottom, and a soft grey drop shadow under each. On the right, 8 px in, the pill:
/// a 22 × 10 px capsule, white with a grey waist and a dark outline. The title is Lucida Grande
/// 13, centred. An inactive window's pinstripes pale and its gems go grey.
///
/// Every part is placed by its row counted from the top edge, so it draws the same in flipped
/// and unflipped views (`flipped` says which).
enum AquaChrome {

    /// Top edge, 21 pinstripe rows, the line under them.
    static let barHeight: CGFloat = 23
    static let cornerRadius: CGFloat = 6
    static let lightDiameter: CGFloat = 13
    static let lightSpacing: CGFloat = 22
    /// From the bar's left edge to the first light's left edge (its centre is 16.5 px in).
    static let lightInset: CGFloat = 10
    static let lightTop: CGFloat = 4
    static let pillSize = NSSize(width: 22, height: 10)
    /// From the bar's right edge to the pill's right end.
    static let pillInset: CGFloat = 8
    static let pillTop: CGFloat = 6

    static let edge = grey(0xCB)
    static let underline = grey(0x91)
    /// The rows under the top edge, as 10.0.4 drew them.
    static let stripes: [UInt8] = [0xFF, 0xFF, 0xF4, 0xEE, 0xF4, 0xFE, 0xF3, 0xED, 0xF2, 0xFD, 0xF1,
                                   0xEB, 0xF0, 0xF9, 0xED, 0xE6, 0xE9, 0xF2, 0xE7, 0xE0, 0xE4]

    static var titleFont: NSFont { NSFont(name: "LucidaGrande", size: 13) ?? .systemFont(ofSize: 13) }

    private static func grey(_ v: Int) -> NSColor { NSColor(srgbRed: CGFloat(v) / 255, green: CGFloat(v) / 255, blue: CGFloat(v) / 255, alpha: 1) }

    // MARK: Geometry

    /// `n` rows of `bar` from row `i` (0 = the top edge), `x` to `x + w`.
    private static func rows(_ bar: NSRect, _ i: CGFloat, _ n: CGFloat = 1, x: CGFloat, w: CGFloat, flipped: Bool) -> NSRect {
        let y = flipped ? bar.minY + i : bar.maxY - i - n
        return NSRect(x: x, y: y, width: w, height: n)
    }

    /// The three lights, left to right: close, minimise, zoom.
    static func lightRects(in bar: NSRect, flipped: Bool) -> [NSRect] {
        (0..<3).map { k in
            rows(bar, lightTop, lightDiameter, x: bar.minX + lightInset + CGFloat(k) * lightSpacing, w: lightDiameter, flipped: flipped)
        }
    }

    static func pillRect(in bar: NSRect, flipped: Bool) -> NSRect {
        rows(bar, pillTop, pillSize.height, x: bar.maxX - pillInset - pillSize.width, w: pillSize.width, flipped: flipped)
    }

    /// The bar's outline: the top corners rounded, the bottom square where it meets the window.
    static func outline(_ b: NSRect, flipped: Bool) -> NSBezierPath {
        let r = cornerRadius
        let top = flipped ? b.minY : b.maxY, bottom = flipped ? b.maxY : b.minY
        let p = NSBezierPath()
        p.move(to: NSPoint(x: b.minX, y: bottom))
        p.line(to: NSPoint(x: b.minX, y: flipped ? top + r : top - r))
        p.appendArc(from: NSPoint(x: b.minX, y: top), to: NSPoint(x: b.minX + r, y: top), radius: r)
        p.line(to: NSPoint(x: b.maxX - r, y: top))
        p.appendArc(from: NSPoint(x: b.maxX, y: top), to: NSPoint(x: b.maxX, y: flipped ? top + r : top - r), radius: r)
        p.line(to: NSPoint(x: b.maxX, y: bottom))
        p.close()
        return p
    }

    // MARK: Drawing

    /// The bar in `bar` (`barHeight` tall): pinstripes, the grey edge round its top and sides,
    /// the line under it. Pale pinstripes for an inactive window.
    static func titleBar(_ bar: NSRect, active: Bool, flipped: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let shape = outline(bar, flipped: flipped)
        shape.addClip()
        edge.setFill(); bar.fill()
        let n = Int(bar.height)
        for i in 1..<(n - 1) {
            let v = CGFloat(stripes[min(i - 1, stripes.count - 1)]) / 255
            let g = active ? v : 1 - (1 - v) * 0.45
            NSColor(srgbRed: g, green: g, blue: g, alpha: 1).setFill()
            rows(bar, CGFloat(i), x: bar.minX + 1, w: bar.width - 2, flipped: flipped).fill()
        }
        // The rounded corners' edge: the outline stroked inside the clip.
        edge.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        (active ? underline : grey(0xB4)).setFill()
        rows(bar, CGFloat(n - 1), x: bar.minX, w: bar.width, flipped: flipped).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The pill that rolls the window up. White, a grey waist, a dark outline and a shadow under.
    static func pill(_ r: NSRect, active: Bool, pressed: Bool, flipped: Bool) {
        let radius = r.height / 2
        let shape = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(active ? 0.35 : 0.15)
        shadow.shadowOffset = NSSize(width: 0, height: -1)   // base coordinates: down on screen
        shadow.shadowBlurRadius = 1
        shadow.set()
        NSColor.white.setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        // The waist, top to bottom: white, grey through the middle, white again.
        let fill: [(NSColor, CGFloat)] = pressed
            ? [(grey(0xC8), 0), (grey(0x9A), 0.45), (grey(0xB8), 0.6), (grey(0xD8), 1)]
            : [(grey(0xF9), 0), (grey(0xF6), 0.2), (grey(0xDD), 0.4), (grey(0xD5), 0.5), (grey(0xE8), 0.62), (.white, 0.8), (.white, 1)]
        NSGradient(colors: fill.map(\.0), atLocations: fill.map(\.1), colorSpace: .sRGB)?
            .draw(in: shape, angle: flipped ? 90 : -90)
        (active ? grey(0x5A) : grey(0x9A)).setStroke()
        shape.lineWidth = 1.2
        shape.stroke()
    }

    /// The title, centred on the bar and kept between `minX` and `maxX`.
    static func title(_ title: String, bar: NSRect, active: Bool, flipped: Bool, minX: CGFloat, maxX: CGFloat) {
        guard !title.isEmpty else { return }
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .paragraphStyle: para,
                                                   .foregroundColor: active ? NSColor.black : grey(0x80)]
        let lo = minX + 8, hi = maxX - 8
        guard hi > lo else { return }
        let size = title.size(withAttributes: attrs)
        let w = min(size.width.rounded(.up), hi - lo)
        let x = max(lo, min(hi - w, (bar.midX - w / 2).rounded()))
        let y = (bar.minY + (bar.height - 1 - size.height) / 2).rounded()
        (title as NSString).draw(in: NSRect(x: x, y: y, width: w, height: size.height), withAttributes: attrs)
    }
}

/// The Aqua traffic light of Mac OS X 10.0 to 10.2, from 10.0.4's pixels: black at the top of
/// the rim and the hue's own dark down its sides; a white gloss across the top third; the
/// colour deep under the gloss and glowing toward the bottom, where the rim goes light; a
/// soft grey shadow under the gem. Works in flipped and unflipped views alike.
enum AquaGem {
    private struct Palette { let rim: NSColor; let deep: NSColor; let mid: NSColor; let glow: NSColor }

    private static func c(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    private static func palette(_ kind: SnowLeopardChrome.Light, active: Bool) -> Palette {
        guard active else { return Palette(rim: c(0x6A6A6A), deep: c(0xA8A8A8), mid: c(0xCFCFCF), glow: c(0xF4F4F4)) }
        switch kind {
        case .close:    return Palette(rim: c(0x7D1105), deep: c(0xC5493B), mid: c(0xEB8877), glow: c(0xFFC9BD))
        case .minimize: return Palette(rim: c(0xB03D03), deep: c(0xE8A12E), mid: c(0xFAC95F), glow: c(0xFFFDA3))
        case .zoom:     return Palette(rim: c(0x2F6A0C), deep: c(0x6FB03C), mid: c(0x9DD364), glow: c(0xDFFBAB))
        }
    }

    static func draw(_ r: NSRect, _ kind: SnowLeopardChrome.Light, active: Bool, pressed: Bool, flipped: Bool = true) {
        let p = palette(kind, active: active)
        let down: CGFloat = flipped ? 1 : -1           // +1 row toward the bottom of the screen
        let top = flipped ? r.minY : r.maxY, bottom = flipped ? r.maxY : r.minY
        let disc = NSBezierPath(ovalIn: r)

        // The shadow under the gem: a blurred disc three rows down.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(active ? 0.9 : 0.45)
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 2.5
        shadow.set()
        NSColor.black.withAlphaComponent(active ? 0.55 : 0.3).setFill()
        NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1).offsetBy(dx: 0, dy: 3 * down)).fill()
        NSGraphicsContext.restoreGraphicsState()

        // The rim: black on top, the hue's dark down the sides, light at the bottom.
        let rimTop = active ? c(0x080808) : c(0x4A4A4A)
        NSGradient(colors: [rimTop, p.rim, p.rim, p.mid], atLocations: [0, 0.3, 0.7, 1], colorSpace: .sRGB)?
            .draw(in: disc, angle: flipped ? 90 : -90)

        // The body: deep near the rim and under the gloss, glowing from low in the middle.
        let inner = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.saveGraphicsState()
        inner.addClip()
        let deep = pressed ? (p.deep.blended(withFraction: 0.3, of: .black) ?? p.deep) : p.deep
        let glow = pressed ? (p.glow.blended(withFraction: 0.25, of: .black) ?? p.glow) : p.glow
        deep.setFill(); inner.fill()
        // Measured down the middle of 10.0.4's close light: deep four rows from the top, the
        // hue's middle three rows lower, the glow two rows above the bottom.
        let centre = NSPoint(x: r.midX, y: bottom - 2.5 * down)
        NSGradient(colors: [glow, p.mid, deep, deep], atLocations: [0, 0.42, 0.72, 1], colorSpace: .sRGB)?
            .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: r.height * 0.62, options: [])
        NSGraphicsContext.restoreGraphicsState()

        // The gloss: white across the top third, fading downward.
        let gw = r.width * 0.68, gh = r.height * 0.27
        let gloss = NSBezierPath(ovalIn: NSRect(x: r.midX - gw / 2, y: flipped ? top + 1 : top - 1 - gh, width: gw, height: gh))
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.97), NSColor.white.withAlphaComponent(0.4)])?
            .draw(in: gloss, angle: flipped ? 90 : -90)
    }
}
