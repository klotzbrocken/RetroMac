import AppKit

/// The one measured description of a Mac OS X 10.6 title bar.
///
/// Every surface that draws Snow Leopard chrome (web-app windows, the TV window, and the
/// widget CSS which mirrors these numbers) reads from here, because four hand-tuned copies
/// is exactly how they ended up looking like four different operating systems.
///
/// All values are sampled pixel-by-pixel from a real 10.6 title bar at 1x, top to bottom:
///
///     #E3E3E3            1px hairline along the top edge
///     #CFCFCF → #A8A8A8  20px ramp, light at the top falling to dark
///     #525252            1px separator along the BOTTOM, against the content
///     lights             14px across, 7px apart, first one 8px in, vertically centred
///
/// The traffic lights are glossy orbs, not flat discs: a thin dark rim on top, a near-white
/// specular band just under it, the saturated body, and a pale glow at the bottom.
enum SnowLeopardChrome {

    // MARK: - Metrics

    static let barH: CGFloat = 22
    static let lightD: CGFloat = 14
    static let lightGap: CGFloat = 7
    static let lightInset: CGFloat = 8

    static var titleFont: NSFont {
        NSFont(name: "Lucida Grande Bold", size: 13)
            ?? NSFont(name: "Lucida Grande", size: 13) ?? .boldSystemFont(ofSize: 13)
    }
    static let titleColor = NSColor(srgbRed: 0.247, green: 0.247, blue: 0.247, alpha: 1)

    /// x offsets of close / minimize / zoom, left to right.
    static func lightOrigins(startingAt x0: CGFloat = lightInset) -> [CGFloat] {
        (0..<3).map { x0 + CGFloat($0) * (lightD + lightGap) }
    }

    // MARK: - Measured colour ramps  (location 0 = visually TOP)

    private static func c(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static let topBorder = c(0x525252)          // sits along the BOTTOM edge in 10.6
    static let hairline = c(0xE3E3E3)           // and this one along the top
    static let borderInactive = c(0x8A8A8A)

    private static let barActive:   [(CGFloat, NSColor)] = [(0, c(0xCFCFCF)), (1, c(0xA8A8A8))]
    /// An unfocused 10.6 window keeps the same ramp, lifted and flattened.
    private static let barInactive: [(CGFloat, NSColor)] = [(0, c(0xE8E8E8)), (1, c(0xD2D2D2))]

    private static func sample(_ stops: [(CGFloat, NSColor)], _ t: CGFloat) -> NSColor {
        if t <= stops[0].0 { return stops[0].1 }
        for i in 1..<stops.count where t <= stops[i].0 {
            let (a, ca) = stops[i - 1], (b, cb) = stops[i]
            let f = b == a ? 0 : (t - a) / (b - a)
            return ca.blended(withFraction: f, of: cb) ?? cb
        }
        return stops[stops.count - 1].1
    }

    /// Fill `rect` with a vertical ramp one device row at a time.
    ///
    /// Deliberately NOT `NSGradient.draw(in:angle:)`: the two callers live in views with
    /// opposite `isFlipped`, and an angle that reads correctly in one is upside down in the
    /// other. Driving the row index explicitly makes both produce identical pixels, which is
    /// the whole point of this file.
    private static func ramp(_ rect: NSRect, flipped: Bool, _ stops: [(CGFloat, NSColor)]) {
        let rows = max(1, Int(rect.height.rounded()))
        for i in 0..<rows {
            let t = (CGFloat(i) + 0.5) / CGFloat(rows)          // 0 == visually top
            let y = flipped ? rect.minY + CGFloat(i) : rect.maxY - CGFloat(i) - 1
            sample(stops, t).setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
        }
    }

    // MARK: - Drawing

    /// The caption strip: a light hairline along the top, the ramp, and the dark separator
    /// along the bottom. `rect` must be `barH` tall. Pass the view's own `isFlipped`.
    static func drawTitleBar(_ rect: NSRect, active: Bool, flipped: Bool) {
        func row(_ fromTop: CGFloat) -> NSRect {
            NSRect(x: rect.minX,
                   y: flipped ? rect.minY + fromTop : rect.maxY - fromTop - 1,
                   width: rect.width, height: 1)
        }
        let ramped = NSRect(x: rect.minX, y: flipped ? rect.minY + 1 : rect.minY + 1,
                            width: rect.width, height: rect.height - 2)
        ramp(ramped, flipped: flipped, active ? barActive : barInactive)
        (active ? hairline : NSColor(white: 0.96, alpha: 1)).setFill()
        row(0).fill()
        (active ? topBorder : borderInactive).setFill()
        row(rect.height - 1).fill()
    }

    enum Light { case close, minimize, zoom }

    /// One traffic light, drawn from the reference artwork in `Resources/Chrome/snowleopard/`.
    ///
    /// This used to be a parametric model fitted to a screenshot. It is artwork now because the
    /// orbs are a fixed 14pt and the reference sheet already ships them at exactly 1x and 2x —
    /// no model to drift, and the widgets embed the very same PNGs, so every surface is
    /// identical by construction rather than by two implementations agreeing.
    static func drawLight(_ rect: NSRect, _ kind: Light, active: Bool, flipped: Bool) {
        let base: String
        if !active { base = "off" } else {
            switch kind {
            case .close: base = "close"
            case .minimize: base = "min"
            case .zoom: base = "zoom"
            }
        }
        if let img = ChromeAssets.image(dir: "snowleopard", base: base, state: .normal) {
            img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            return
        }
        // Assets absent: a plain disc, so the window still has usable controls.
        let fallback: NSColor
        switch (active, kind) {
        case (false, _):      fallback = NSColor(white: 0.78, alpha: 1)
        case (true, .close):  fallback = NSColor(srgbRed: 0.96, green: 0.25, blue: 0.25, alpha: 1)
        case (true, .minimize): fallback = NSColor(srgbRed: 1.0, green: 0.77, blue: 0.35, alpha: 1)
        case (true, .zoom):   fallback = NSColor(srgbRed: 0.52, green: 0.81, blue: 0.32, alpha: 1)
        }
        fallback.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    /// The ×, − and + that 10.6 reveals once the pointer is over the cluster.
    static func drawGlyph(_ kind: Light, in rect: NSRect) {
        NSColor(white: 0.18, alpha: 0.75).setStroke()
        let p = NSBezierPath()
        p.lineWidth = 1.4
        p.lineCapStyle = .round
        let i = rect.insetBy(dx: rect.width * 0.30, dy: rect.height * 0.30)
        switch kind {
        case .close:
            p.move(to: NSPoint(x: i.minX, y: i.minY)); p.line(to: NSPoint(x: i.maxX, y: i.maxY))
            p.move(to: NSPoint(x: i.maxX, y: i.minY)); p.line(to: NSPoint(x: i.minX, y: i.maxY))
        case .minimize:
            p.move(to: NSPoint(x: i.minX, y: i.midY)); p.line(to: NSPoint(x: i.maxX, y: i.midY))
        case .zoom:
            p.move(to: NSPoint(x: i.minX, y: i.midY)); p.line(to: NSPoint(x: i.maxX, y: i.midY))
            p.move(to: NSPoint(x: i.midX, y: i.minY)); p.line(to: NSPoint(x: i.midX, y: i.maxY))
        }
        p.stroke()
    }

    /// Centred caption text with the white emboss 10.6 puts under it.
    static func drawTitle(_ title: String, in box: NSRect, active: Bool, flipped: Bool) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let font = titleFont
        if active {
            let shadow = NSRect(x: box.minX, y: flipped ? box.minY + 1 : box.minY - 1,
                                width: box.width, height: box.height)
            (title as NSString).draw(in: shadow, withAttributes: [
                .font: font, .foregroundColor: NSColor(white: 1, alpha: 0.7), .paragraphStyle: para])
        }
        (title as NSString).draw(in: box, withAttributes: [
            .font: font,
            .foregroundColor: active ? titleColor : titleColor.withAlphaComponent(0.45),
            .paragraphStyle: para])
    }
}
