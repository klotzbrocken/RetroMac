import AppKit

/// The Mac's 256 colours (`menuBar.palette: "mac256"`): Apple's standard 8-bit colour table,
/// the one System 7 drew with when the Monitors control panel said "256". A picture is
/// resampled to the pixels it is shown at and every pixel then takes the nearest of the 256 —
/// no dithering, and a 1-bit mask as the icons had: a pixel is there or it is not.
enum Mac256 {

    /// Whether the active theme draws in the 256 colours.
    static var active: Bool { ThemeManager.shared.activeTheme?.config.hasMac256Palette == true }

    /// The standard table: the 6 × 6 × 6 cube of FF, CC, 99, 66, 33, 00 without black, then
    /// ten-step ramps of red, green, blue and grey (EE DD BB AA 88 77 55 44 22 11), then black.
    static let palette: [(r: UInt8, g: UInt8, b: UInt8)] = {
        var p: [(r: UInt8, g: UInt8, b: UInt8)] = []
        let cube: [UInt8] = [0xFF, 0xCC, 0x99, 0x66, 0x33, 0x00]
        for r in cube { for g in cube { for b in cube where r | g | b != 0 { p.append((r, g, b)) } } }
        let ramp: [UInt8] = [0xEE, 0xDD, 0xBB, 0xAA, 0x88, 0x77, 0x55, 0x44, 0x22, 0x11]
        for v in ramp { p.append((v, 0, 0)) }
        for v in ramp { p.append((0, v, 0)) }
        for v in ramp { p.append((0, 0, v)) }
        for v in ramp { p.append((v, v, v)) }
        p.append((0, 0, 0))
        return p
    }()

    // Built in deviceRGB: `NSBitmapImageRep.setColor` writes into the rep's own space, and a
    // grayscale colour handed to an RGB rep lands as nothing.
    static func colour(_ hex: UInt32) -> NSColor {
        NSColor(deviceRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    static let black = colour(0x000000)
    static let white = colour(0xFFFFFF)
    /// The grey ramp's steps the surfaces use.
    static let grey55 = colour(0x555555)
    static let grey88 = colour(0x888888)
    static let greyAA = colour(0xAAAAAA)
    static let greyBB = colour(0xBBBBBB)
    static let greyDD = colour(0xDDDDDD)

    /// The nearest colour of the table, for every colour at 5 bits a channel (32 768 entries,
    /// built once): the lookup that makes a whole icon cost one table read per pixel.
    private static let nearest: [UInt8] = {
        var t = [UInt8](repeating: 0, count: 32 * 32 * 32)
        let pal = palette.map { (Int($0.r), Int($0.g), Int($0.b)) }
        for key in 0..<t.count {
            let r = ((key >> 10) & 31) << 3 | 4, g = ((key >> 5) & 31) << 3 | 4, b = (key & 31) << 3 | 4
            var best = 0, bestD = Int.max
            for (i, c) in pal.enumerated() {
                let dr = r - c.0, dg = g - c.1, db = b - c.2
                let d = 3 * dr * dr + 4 * dg * dg + 2 * db * db   // green weighs most, as the eye does
                if d < bestD { bestD = d; best = i }
            }
            t[key] = UInt8(best)
        }
        return t
    }()

    /// The table's colour nearest to `r, g, b`.
    static func snap(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (r: UInt8, g: UInt8, b: UInt8) {
        palette[Int(nearest[Int(r >> 3) << 10 | Int(g >> 3) << 5 | Int(b >> 3)])]
    }

    /// An icon in the 256 colours at `points`, `scale` device pixels each: resampled smoothly
    /// to those pixels, then every pixel snapped to the table and its alpha to all or nothing.
    /// Byte by byte — `colorAt`/`setColor` would allocate an NSColor per pixel.
    static func icon(_ image: NSImage, points: CGFloat, scale: CGFloat = 2) -> NSImage {
        let px = max(1, Int((points * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bytes = rep.bitmapData else { return image }
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: points, height: points), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let row = rep.bytesPerRow
        for y in 0..<px {
            var p = bytes + y * row
            for _ in 0..<px {
                let a = Int(p[3])
                if a < 128 {
                    p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0
                } else {
                    // The rep is premultiplied: the colour is darker than it is until divided out.
                    let r = UInt8(min(255, Int(p[0]) * 255 / a)), g = UInt8(min(255, Int(p[1]) * 255 / a)), b = UInt8(min(255, Int(p[2]) * 255 / a))
                    let c = snap(r, g, b)
                    p[0] = c.r; p[1] = c.g; p[2] = c.b; p[3] = 255
                }
                p += 4
            }
        }
        let img = NSImage(size: NSSize(width: points, height: points))
        img.addRepresentation(rep)
        return img
    }
}
