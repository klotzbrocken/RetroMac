import AppKit

/// The four greys of a PowerBook 150's screen — `#000000`, `#555555`, `#AAAAAA`, `#FFFFFF` —
/// and the drawing that keeps a theme inside them (`menuBar.palette: "grays4"`). Every colour
/// a picture brings is snapped to the nearest of the four; nothing is dithered, blurred or
/// antialiased, and a picture that has to shrink is reduced block by block so its 1 px lines
/// survive instead of turning into a grey mist.
enum FourGrays {

    /// Whether the active theme is limited to the four greys.
    static var active: Bool { ThemeManager.shared.activeTheme?.config.hasFourGreys == true }

    // Built in deviceRGB, not deviceWhite: `NSBitmapImageRep.setColor` writes a colour into
    // the rep's own space, and a grayscale colour handed to an RGB rep lands as nothing.
    private static func grey(_ v: Double, alpha: Double = 1) -> NSColor {
        NSColor(deviceRed: v, green: v, blue: v, alpha: alpha)
    }
    static let black = grey(0)
    static let dark = grey(0x55 / 255.0)     // #555555
    static let light = grey(0xAA / 255.0)    // #AAAAAA
    static let white = grey(1)
    static let clear = grey(0, alpha: 0)
    /// The four, dark to light, and their luminance in 0…1.
    static let levels: [(color: NSColor, value: Double)] = [(black, 0), (dark, 0x55 / 255.0), (light, 0xAA / 255.0), (white, 1)]

    /// The nearest of the four to a luminance.
    static func snap(_ lum: Double) -> NSColor {
        var best = levels[0]
        for l in levels where abs(l.value - lum) < abs(best.value - lum) { best = l }
        return best.color
    }

    /// `image` with every pixel snapped to the four greys; transparent pixels stay transparent.
    /// Not cached here (an image object outlives its identity): callers keep the result.
    static func quantize(_ image: NSImage) -> NSImage {
        guard let src = deviceRGB(image) else { return image }
        let w = src.pixelsWide, h = src.pixelsHigh
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        for y in 0..<h {
            for x in 0..<w {
                guard let c = src.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent >= 0.5 else {
                    out.setColor(clear, atX: x, y: y); continue
                }
                let lum = Double(0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent)
                out.setColor(snap(lum), atX: x, y: y)
            }
        }
        let img = NSImage(size: image.size)
        img.addRepresentation(out)
        return img
    }

    /// The picture's own pixels in a bitmap this code can read colour by colour: its largest
    /// bitmap representation redrawn into deviceRGB (a cached snapshot rep, a CGImage rep or a
    /// planar TIFF answers `colorAt` with nothing at all). Never resampled — a 256 px icon
    /// stays 256 px here, so nothing is lost before it is snapped.
    private static func deviceRGB(_ image: NSImage) -> NSBitmapImageRep? {
        // Whatever the picture is made of, end up with a bitmap whose pixels can be read one
        // by one: its own bitmap rep if it has one, else its TIFF, else a CGImage. Each
        // candidate is tried on a pixel first — a planar or CMYK rep answers `colorAt` with
        // nothing, and a picture that looks empty would be quantised to nothing.
        // Usable means readable AND not empty: a rep whose pixels all come back transparent
        // (a TIFF of a picture drawn with `lockFocus` in a process with no window server) is
        // no good, and quantising it would hand back nothing at all.
        func usable(_ rep: NSBitmapImageRep?) -> NSBitmapImageRep? {
            guard let rep, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
            let stepX = max(1, rep.pixelsWide / 16), stepY = max(1, rep.pixelsHigh / 16)
            for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
                for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent >= 0.5 { return rep }
                }
            }
            return nil
        }
        if let own = usable(image.representations.compactMap({ $0 as? NSBitmapImageRep }).max(by: { $0.pixelsWide < $1.pixelsWide })) {
            return own
        }
        if let tiff = image.tiffRepresentation, let rep = usable(NSBitmapImageRep(data: tiff)) { return rep }
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let rep = usable(NSBitmapImageRep(cgImage: cg)) { return rep }
        return nil
    }

    /// `image` at `points`, shown at `scale` device pixels each, in the four greys. The picture
    /// is reduced block by block (nearest neighbour, never smoothed): a block is as dark as its
    /// darkest quarter, so a 1 px line of a 256 px icon is still a line at 16 pt.
    static func quantize(_ image: NSImage, points: CGFloat, scale: CGFloat = 2) -> NSImage {
        let big = quantize(image)
        guard let src = big.representations.first as? NSBitmapImageRep else { return big }
        let target = max(8, Int(points * scale))
        let w = src.pixelsWide, h = src.pixelsHigh
        guard w > target, h > target else { big.size = NSSize(width: points, height: points); return big }
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: target, pixelsHigh: target, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return big }
        for ty in 0..<target {
            for tx in 0..<target {
                let x0 = tx * w / target, x1 = max(x0 + 1, (tx + 1) * w / target)
                let y0 = ty * h / target, y1 = max(y0 + 1, (ty + 1) * h / target)
                var opaque = 0, total = 0
                var darkest = 1.0
                var sum = 0.0
                for y in y0..<y1 { for x in x0..<x1 {
                    total += 1
                    guard let c = src.colorAt(x: x, y: y), c.alphaComponent >= 0.5 else { continue }
                    opaque += 1
                    let v = Double(c.redComponent)
                    sum += v
                    if v < darkest { darkest = v }
                } }
                if opaque * 2 < total { out.setColor(clear, atX: tx, y: ty); continue }
                // A block with any real ink in it keeps that ink (a thin line survives); an
                // even block takes its own average.
                let mean = sum / Double(max(1, opaque))
                out.setColor(snap(darkest < 0.5 && mean - darkest > 0.2 ? darkest : mean), atX: tx, y: ty)
            }
        }
        out.size = NSSize(width: points, height: points)
        let img = NSImage(size: NSSize(width: points, height: points))
        img.addRepresentation(out)
        return img
    }

    /// Draw with `body` (flipped coordinates, as the strip's modules draw) into a `size` picture
    /// at `scale`, and return it in the four greys.
    static func quantize(size: NSSize, scale: CGFloat, _ body: @escaping (NSRect) -> Void) -> NSImage? {
        let canvas = FlippedCanvas(frame: NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        canvas.scale = scale
        canvas.body = body
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return nil }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let img = NSImage(size: canvas.bounds.size)
        img.addRepresentation(rep)
        let out = quantize(img)
        out.size = size
        return out
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
}
