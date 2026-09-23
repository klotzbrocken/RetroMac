import AppKit

/// **System 7.1** window chrome as a colour Mac drew it at 256 colours, measured pixel for pixel
/// from System 7.1 running in an emulator (Infinite Mac, the Finder's own windows).
///
/// The active title bar is 19 px from the frame's top rule to the black line under it: a
/// #CCCCFF light edge along the top and left, a #9999CC shadow along the bottom and right, an
/// #EEEEEE ground with six #777777 stripes, and — each 9 px in from the window's edge — the close
/// box on the left and the zoom box on the right: 11 px, sunk into the bar (#333366 above and
/// left, #CCCCFF below and right) around a raised #AAAAAA face, with a 1 px #EEEEEE gap cut out
/// of the stripes either side. The title is centred in Chicago with 8 px of ground each side.
/// An inactive window's bar is white, stripeless and boxless, its title in #777777.
///
/// Drawing is in whole pixels and works in flipped and unflipped views alike (`flipped` says
/// which): every part is placed by its row counted from the top rule.
enum System7Chrome {

    static let black = Mac256.black
    static let white = Mac256.white
    static let face = Mac256.colour(0xEEEEEE)
    static let stripe = Mac256.colour(0x777777)
    static let light = Mac256.colour(0xCCCCFF)      // the lavender light edge
    static let shade = Mac256.colour(0x9999CC)      // the lavender shadow edge
    static let deep = Mac256.colour(0x333366)       // the boxes' dark edge
    static let boxFace = Mac256.greyAA
    static let pressedFace = Mac256.colour(0x777777)
    static let inactiveText = Mac256.colour(0x777777)

    /// Top rule, 17 rows, the black line under the bar.
    static let barHeight: CGFloat = 19
    static let boxSize: CGFloat = 11
    /// From the window's outer edge to a box.
    static let boxInset: CGFloat = 9
    static var titleFont: NSFont { System6Chrome.titleFont }

    // MARK: Geometry

    /// Row `i` (0 = the top rule) of `bar`, from `x` for `w` pixels, `n` rows tall.
    private static func rows(_ bar: NSRect, _ i: Int, _ n: Int = 1, x: CGFloat, w: CGFloat, flipped: Bool) -> NSRect {
        let y = flipped ? bar.minY + CGFloat(i) : bar.maxY - CGFloat(i + n)
        return NSRect(x: x, y: y, width: w, height: CGFloat(n))
    }

    static func closeRect(in bar: NSRect, flipped: Bool) -> NSRect {
        rows(bar, 4, Int(boxSize), x: bar.minX + boxInset, w: boxSize, flipped: flipped)
    }
    static func zoomRect(in bar: NSRect, flipped: Bool) -> NSRect {
        rows(bar, 4, Int(boxSize), x: bar.maxX - boxInset - boxSize, w: boxSize, flipped: flipped)
    }

    // MARK: Drawing

    /// The whole bar in `bar` (`barHeight` tall): the black rules round it, and for an active
    /// window the light and shadow edges, the ground and the six stripes.
    static func titleBar(_ bar: NSRect, active: Bool, flipped: Bool) {
        let n = Int(bar.height)
        (active ? face : white).setFill(); bar.fill()
        black.setFill()
        rows(bar, 0, x: bar.minX, w: bar.width, flipped: flipped).fill()
        rows(bar, n - 1, x: bar.minX, w: bar.width, flipped: flipped).fill()
        NSRect(x: bar.minX, y: bar.minY, width: 1, height: bar.height).fill()
        NSRect(x: bar.maxX - 1, y: bar.minY, width: 1, height: bar.height).fill()
        guard active else { return }
        light.setFill()
        rows(bar, 1, x: bar.minX + 1, w: bar.width - 3, flipped: flipped).fill()
        rows(bar, 1, n - 3, x: bar.minX + 1, w: 1, flipped: flipped).fill()
        shade.setFill()
        rows(bar, n - 2, x: bar.minX + 1, w: bar.width - 2, flipped: flipped).fill()
        rows(bar, 1, n - 2, x: bar.maxX - 2, w: 1, flipped: flipped).fill()
        stripe.setFill()
        for i in stride(from: 4, through: n - 5, by: 2) {
            rows(bar, i, x: bar.minX + 2, w: bar.width - 4, flipped: flipped).fill()
        }
    }

    /// A box in `r`, drawn by its rows from the top: the sunken frame, the raised face, and for
    /// the zoom box the small square's shadow in its upper left.
    private static func box(_ r: NSRect, zoom: Bool, pressed: Bool, flipped: Bool) {
        // The stripes stop a pixel short of the box on either side.
        face.setFill(); r.insetBy(dx: -1, dy: 0).fill()
        func px(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: NSColor) {
            c.setFill()
            let yy = flipped ? r.minY + CGFloat(y) : r.maxY - CGFloat(y + h)
            NSRect(x: r.minX + CGFloat(x), y: yy, width: CGFloat(w), height: CGFloat(h)).fill()
        }
        let s = Int(r.width)
        px(0, 0, s, s, pressed ? pressedFace : boxFace)
        // Sunk into the bar: dark above and left, light below and right. The top and left
        // edges are drawn last: they own the corners, as the original's did.
        px(0, s - 1, s, 1, light); px(s - 1, 0, 1, s, light)
        px(0, 0, s, 1, deep); px(0, 0, 1, s, deep)
        // The face, raised — or pushed in while the mouse holds it.
        let hi = pressed ? deep : light, lo = pressed ? light : deep
        px(1, s - 2, s - 2, 1, lo); px(s - 2, 1, 1, s - 2, lo)
        px(1, 1, s - 2, 1, hi); px(1, 1, 1, s - 2, hi)
        if zoom {
            px(6, 2, 1, 5, deep); px(2, 6, 5, 1, deep)
        }
    }

    static func closeBox(_ r: NSRect, pressed: Bool = false, flipped: Bool) { box(r, zoom: false, pressed: pressed, flipped: flipped) }
    static func zoomBox(_ r: NSRect, pressed: Bool = false, flipped: Bool) { box(r, zoom: true, pressed: pressed, flipped: flipped) }

    /// The title, centred on the bar with 8 px of ground cleared either side, kept between
    /// `minX` and `maxX` (the boxes).
    static func title(_ title: String, bar: NSRect, active: Bool, flipped: Bool,
                      minX: CGFloat? = nil, maxX: CGFloat? = nil, font: NSFont = titleFont) {
        guard !title.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: active ? black : inactiveText]
        let lo = (minX ?? bar.minX + 1) + 8, hi = (maxX ?? bar.maxX - 1) - 8
        guard hi > lo else { return }
        let size = title.size(withAttributes: attrs)
        let w = min(size.width.rounded(.up), hi - lo)
        let x = max(lo, min(hi - w, (bar.midX - w / 2).rounded()))
        (active ? face : white).setFill()
        rows(bar, 2, Int(bar.height) - 4, x: x - 8, w: w + 16, flipped: flipped).fill()
        let y = (bar.minY + (bar.height - size.height) / 2).rounded()
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: x, y: bar.minY, width: w, height: bar.height).clip()
        (title as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The window's 1 px black frame.
    static func frame(_ r: NSRect) {
        black.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }
}
