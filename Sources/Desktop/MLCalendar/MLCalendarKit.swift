import AppKit

// Drawing helpers shared by the Mountain Lion calendar views.

func mlRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func mlMix(_ c: NSColor, _ other: NSColor, _ t: CGFloat) -> NSColor {
    let a = c.usingColorSpace(.sRGB) ?? c, b = other.usingColorSpace(.sRGB) ?? other
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}

/// Lucida Grande, the system font of OS X 10.8. Falls back to the system font if a Mac no longer ships it.
/// Sizes are given in the calendar's own scale; the reference screens measure ~0.88 of the nominal point size.
func mlFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
    let size = (size * 0.88 * 2).rounded() / 2
    return NSFont(name: bold ? "LucidaGrande-Bold" : "LucidaGrande", size: size)
        ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
}

@discardableResult
func mlText(_ s: String, _ r: NSRect, _ font: NSFont, _ color: NSColor, align: NSTextAlignment = .left,
            shadow: NSColor? = nil) -> CGFloat {
    let ps = NSMutableParagraphStyle()
    ps.alignment = align
    ps.lineBreakMode = .byTruncatingTail
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: ps]
    let h = ceil(font.ascender - font.descender + font.leading)
    let box = NSRect(x: r.minX, y: r.minY + floor((r.height - h) / 2), width: r.width, height: h)
    if let shadow {
        let sh = NSShadow(); sh.shadowColor = shadow; sh.shadowOffset = NSSize(width: 0, height: -1); sh.shadowBlurRadius = 0
        attrs[.shadow] = sh
    }
    (s as NSString).draw(in: box, withAttributes: attrs)
    return (s as NSString).size(withAttributes: [.font: font]).width
}

func mlTextWidth(_ s: String, _ font: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }

func mlLine(_ r: NSRect, _ c: NSColor) { c.setFill(); r.fill() }

/// Vertical gradient, first colour at the top of a flipped view.
func mlGradient(_ r: NSRect, _ stops: [(CGFloat, NSColor)], radius: CGFloat = 0) {
    let g = NSGradient(colors: stops.map { $0.1 }, atLocations: stops.map { $0.0 }, colorSpace: .sRGB)
    if radius > 0 { NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip() }
    g?.draw(in: r, angle: 90)
    if radius > 0 { NSGraphicsContext.restoreGraphicsState() }
}

// MARK: - Leather and paper

enum MLAsset {
    private static var cache: [String: NSImage] = [:]
    /// Decoded once; `unitsPerPixel` sets the size in calendar units (the calendar is drawn at 1.5× on screen).
    static func image(_ b64: String, unitsPerPixel u: CGFloat) -> NSImage {
        let key = "\(b64.hashValue)|\(u)"
        if let c = cache[key] { return c }
        let img = Data(base64Encoded: b64).flatMap { NSImage(data: $0) } ?? NSImage(size: NSSize(width: 1, height: 1))
        if let rep = img.representations.first, rep.pixelsWide > 0 { img.size = NSSize(width: CGFloat(rep.pixelsWide) * u, height: CGFloat(rep.pixelsHigh) * u) }
        cache[key] = img
        return img
    }
}

enum MLLeather {
    /// Grain taken from the reference crop (high-pass of the user-supplied leather sample, mirrored for seamless tiling).
    static let tile: NSImage = MLAsset.image(MLAssets.leatherGrain, unitsPerPixel: 0.36)

    static func fill(_ r: NSRect) {
        // base shading measured from the 2012 reference: lit at the top edge, shading down to a darker lower edge
        mlGradient(r, [(0, mlRGB(250, 213, 148)), (0.03, mlRGB(236, 199, 134)), (0.12, mlRGB(226, 189, 124)), (0.45, mlRGB(220, 183, 117)),
                       (0.70, mlRGB(208, 171, 104)), (0.86, mlRGB(196, 158, 92)), (0.96, mlRGB(170, 136, 76)), (1, mlRGB(150, 118, 62))])
        NSGraphicsContext.saveGraphicsState()
        NSColor(patternImage: tile).setFill()
        NSGraphicsContext.current?.patternPhase = NSPoint(x: 0, y: r.maxY)
        r.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    static let barHeight: CGFloat = 4.3

    /// The periwinkle rule where the leather ends. Row colours are sampled from the user-supplied strip (smooth, so it
    /// stays sharp at any scale instead of showing the strip's own pixels or tile seams).
    static func bar(width: CGFloat, y: CGFloat) {
        mlLine(NSRect(x: 0, y: y, width: width, height: 0.7), mlRGB(112, 80, 44))
        mlGradient(NSRect(x: 0, y: y + 0.7, width: width, height: 2.9), [(0, mlRGB(136, 146, 188)), (0.45, mlRGB(114, 124, 162)), (1, mlRGB(98, 107, 142))])
        mlLine(NSRect(x: 0, y: y + 3.6, width: width, height: 0.7), mlRGB(34, 37, 50))
    }

    // Sizes measured on the 1500 px reference: a bump is 40-70 units wide and ~3 deep; bumps are sparse (one per 100-270 units).
    private static let fringes: [NSImage] = [
        MLAsset.image(MLAssets.paperA, unitsPerPixel: 0.46), MLAsset.image(MLAssets.paperC, unitsPerPixel: 0.7),
        MLAsset.image(MLAssets.paperB, unitsPerPixel: 0.7), MLAsset.image(MLAssets.paperC, unitsPerPixel: 0.62),
        MLAsset.image(MLAssets.paperA, unitsPerPixel: 0.4), MLAsset.image(MLAssets.paperB, unitsPerPixel: 0.8),
    ]

    /// Torn paper below the rule: the three user-supplied fringe samples placed one after another with small gaps.
    static func wisps(width: CGFloat, y: CGFloat) {
        // the paper edge is continuous right under the rule; the torn patches hang from it
        mlGradient(NSRect(x: 0, y: y, width: width, height: 1.6), [(0, mlRGB(86, 86, 88, 0.9)), (1, mlRGB(160, 160, 162, 0.05))])
        var seed: UInt32 = 5
        func rnd() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed >> 8 & 0xFFFF) / 65535 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        var x: CGFloat = 20 + rnd() * 40
        var i = 0
        while x < width {
            let img = fringes[i % fringes.count]
            img.draw(in: NSRect(x: x, y: y, width: img.size.width, height: img.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += img.size.width + 25 + rnd() * 120
            i += 1
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Traffic lights

func mlTrafficLights(centers: [NSPoint], dia: CGFloat, active: Bool, hover: Bool) {
    let cols = [mlRGB(236, 81, 66), mlRGB(238, 187, 52), mlRGB(86, 192, 60)]
    let glyph = ["×", "−", "+"]
    for (i, c) in centers.enumerated() {
        let r = NSRect(x: c.x - dia / 2, y: c.y - dia / 2, width: dia, height: dia)
        let base = active ? cols[i] : mlRGB(150, 172, 200)      // inactive: bluish silver glass
        mlGradient(r, [(0, mlMix(base, .white, 0.45)), (0.5, base), (1, mlMix(base, .black, 0.12))], radius: dia / 2)
        let p = NSBezierPath(ovalIn: r.insetBy(dx: 0.35, dy: 0.35))
        mlMix(base, .black, 0.45).setStroke(); p.lineWidth = 0.7; p.stroke()
        if hover { mlText(glyph[i], r.offsetBy(dx: 0, dy: -0.5), NSFont(name: "LucidaGrande-Bold", size: dia * 0.9) ?? .boldSystemFont(ofSize: dia * 0.9), mlRGB(70, 20, 10, 0.8), align: .center) }
    }
}
