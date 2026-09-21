import AppKit

/// The 1-bit Mac's drawing, for the themes that ask for it (`menuBar.monochrome`): every
/// picture becomes black and white with the greys dithered, as a compact Mac's screen showed
/// them, and the patterns the era drew its greys with.
enum MonoArt {

    /// Whether the active theme draws its menus and strip in black and white.
    static var active: Bool { ThemeManager.shared.activeTheme?.config.hasMonochromeMenus == true }

    /// Bayer 4×4 ordered dither: a grey becomes a pattern of black and white pixels.
    private static let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]].map { $0.map { ($0 + 0.5) / 16 } }

    /// `image` in black, white and dithered greys; transparent pixels stay transparent. Not
    /// cached here (an object identifier outlives its image and would hand back the wrong
    /// picture): callers keep the result.
    static func oneBit(_ image: NSImage) -> NSImage {
        // The picture's own pixels, not a TIFF drawn at its point size: a 256 px icon told to
        // be 16 pt would otherwise be sampled down before the lines were kept.
        let own = image.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }
        guard let src = own ?? image.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) }) else { return image }
        let w = src.pixelsWide, h = src.pixelsHigh
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        // Device colours throughout: `setColor` takes the rep's own space, and a catalog
        // colour (`.black`, `.clear`) lands as nothing at all.
        let black = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        let clear = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
        for y in 0..<h {
            for x in 0..<w {
                guard let c = src.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { out.setColor(clear, atX: x, y: y); continue }
                let a = c.alphaComponent
                if a < 0.5 { out.setColor(clear, atX: x, y: y); continue }
                let lum = Double(0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent)
                // Dark and light go straight to black and white (the lines and faces of the
                // pixel art stay crisp); only the middle greys are dithered.
                let dark = lum < 0.4 || (lum < 0.72 && lum < 0.4 + 0.32 * bayer[y % 4][x % 4])
                out.setColor(dark ? black : white, atX: x, y: y)
            }
        }
        let img = NSImage(size: image.size)
        img.addRepresentation(out)
        return img
    }

    /// Draw with `body` (flipped coordinates, as the strip's modules draw) into a `size`
    /// picture at `scale` and return it in black and white. Through a flipped view, so text
    /// comes out the right way up.
    static func oneBit(size: NSSize, scale: CGFloat, _ body: @escaping (NSRect) -> Void) -> NSImage? {
        let canvas = FlippedCanvas(frame: NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        canvas.scale = scale
        canvas.body = body
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return nil }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let img = NSImage(size: canvas.bounds.size)
        img.addRepresentation(rep)
        let bit = oneBit(img)
        bit.size = size
        return bit
    }

    private final class FlippedCanvas: NSView {
        var scale: CGFloat = 1
        var body: ((NSRect) -> Void)?
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            body?(NSRect(x: 0, y: 0, width: bounds.width / scale, height: bounds.height / scale))
        }
    }

    /// `image` at `points` (2× pixels) in 1 bit: the full-size picture is thresholded first,
    /// then reduced block by block — a block with enough black in it stays black — so the
    /// 1 px lines of a 256 px icon survive the way down to 32 px, where resampling would
    /// have greyed them out of existence.
    static func oneBit(_ image: NSImage, points: CGFloat, scale: CGFloat = 2) -> NSImage {
        let big = oneBit(image)
        guard let src = big.representations.first as? NSBitmapImageRep else { return big }
        // Reduced to the pixels the screen will actually show (a 1× display halves them
        // again otherwise, and the thin lines go with the dropped rows).
        let target = max(8, Int(points * scale))
        let w = src.pixelsWide, h = src.pixelsHigh
        guard w > target, h > target else { big.size = NSSize(width: points, height: points); return big }
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: target, pixelsHigh: target, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return big }
        let black = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        let clear = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
        for ty in 0..<target {
            for tx in 0..<target {
                let x0 = tx * w / target, x1 = max(x0 + 1, (tx + 1) * w / target)
                let y0 = ty * h / target, y1 = max(y0 + 1, (ty + 1) * h / target)
                var opaque = 0, dark = 0, total = 0
                for y in y0..<y1 { for x in x0..<x1 {
                    total += 1
                    guard let c = src.colorAt(x: x, y: y), c.alphaComponent >= 0.5 else { continue }
                    opaque += 1
                    if c.redComponent < 0.5 { dark += 1 }
                } }
                if opaque * 2 < total { out.setColor(clear, atX: tx, y: ty) }
                else { out.setColor(dark * 10 >= total ? black : white, atX: tx, y: ty) }   // a thin line in the block keeps it black
            }
        }
        out.size = NSSize(width: points, height: points)
        let img = NSImage(size: NSSize(width: points, height: points))
        img.addRepresentation(out)
        return img
    }

    /// The 50 % grey pattern: black and white in a checkerboard, the era's "gray".
    static let gray: NSColor = {
        let img = NSImage(size: NSSize(width: 2, height: 2))
        img.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 1, height: 1).fill(); NSRect(x: 1, y: 1, width: 1, height: 1).fill()
        img.unlockFocus()
        return NSColor(patternImage: img)
    }()

    /// A vertical groove: a dotted black line.
    static let dots: NSColor = {
        let img = NSImage(size: NSSize(width: 1, height: 2))
        img.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1, height: 2).fill()
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        return NSColor(patternImage: img)
    }()
}
