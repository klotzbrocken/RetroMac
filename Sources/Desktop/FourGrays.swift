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

    /// The snap table: a byte's luminance to one of the four, built once.
    private static let table: [UInt8] = (0...255).map { v -> UInt8 in
        let levels: [UInt8] = [0, 0x55, 0xAA, 0xFF]
        return levels.min { abs(Int($0) - Int(v)) < abs(Int($1) - Int(v)) } ?? 0
    }

    /// `image` with every pixel snapped to the four greys, at its own size.
    static func quantize(_ image: NSImage) -> NSImage {
        quantize(image, points: image.size.width > 0 ? image.size.width : 16, scale: 1, keepSize: true)
    }

    /// `image` at `points`, shown at `scale` device pixels each, in the four greys. The picture
    /// is reduced block by block (nearest neighbour, never smoothed): a block takes its own
    /// average, and a block with a thin dark line in it keeps the line.
    ///
    /// Byte by byte, not colour by colour: `colorAt`/`setColor` allocate an NSColor per pixel,
    /// which on a 512 px icon is a quarter of a million objects — that is what made the Apple
    /// menu crawl once every icon went through here.
    static func quantize(_ image: NSImage, points: CGFloat, scale: CGFloat = 2, keepSize: Bool = false) -> NSImage {
        guard let src = deviceRGB(image), let srcBytes = src.bitmapData else { return image }
        let w = src.pixelsWide, h = src.pixelsHigh
        let srcRow = src.bytesPerRow, srcPix = src.samplesPerPixel
        let targetW = keepSize ? w : max(1, min(w, Int((points * scale).rounded())))
        let targetH = keepSize ? h : max(1, min(h, Int((points * scale).rounded())))
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: targetW, pixelsHigh: targetH,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let outBytes = out.bitmapData else { return image }
        let outRow = out.bytesPerRow
        let alphaFirst = src.bitmapFormat.contains(.alphaFirst)
        let premultiplied = !src.bitmapFormat.contains(.alphaNonpremultiplied)

        for ty in 0..<targetH {
            let y0 = ty * h / targetH, y1 = max(y0 + 1, (ty + 1) * h / targetH)
            for tx in 0..<targetW {
                let x0 = tx * w / targetW, x1 = max(x0 + 1, (tx + 1) * w / targetW)
                var opaque = 0, total = 0, sum = 0, darkest = 255
                for y in y0..<y1 {
                    var p = srcBytes + y * srcRow + x0 * srcPix
                    for _ in x0..<x1 {
                        total += 1
                        let a = Int(alphaFirst ? p[0] : p[srcPix - 1])
                        if a >= 128 {
                            opaque += 1
                            let o = alphaFirst ? 1 : 0
                            var r = Int(p[o]), g = Int(p[o + 1]), b = Int(p[o + 2])
                            // Premultiplied bytes are darker than the colour is; undo that
                            // before deciding which grey the pixel belongs to.
                            if premultiplied, a > 0, a < 255 {
                                r = min(255, r * 255 / a); g = min(255, g * 255 / a); b = min(255, b * 255 / a)
                            }
                            let lum = (r * 77 + g * 151 + b * 28) >> 8
                            sum += lum
                            if lum < darkest { darkest = lum }
                        }
                        p += srcPix
                    }
                }
                let o = outBytes + ty * outRow + tx * 4
                if opaque * 2 < total { o[0] = 0; o[1] = 0; o[2] = 0; o[3] = 0; continue }
                let mean = sum / max(1, opaque)
                let value = (darkest < 128 && mean - darkest > 50) ? darkest : mean
                let g = table[value]
                o[0] = g; o[1] = g; o[2] = g; o[3] = 255
            }
        }
        let size = keepSize ? image.size : NSSize(width: points, height: points)
        out.size = size
        let img = NSImage(size: size)
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

    /// An icon for a four-grey theme: grey, but with every grey there is. The theme's surfaces
    /// (menus, strip, frames) keep to the four; pictures snapped to the four came out as
    /// blotches, so a picture only loses its colour. Resampled smoothly to the pixels it is
    /// shown at, then turned to luminance byte by byte; alpha is kept as it is.
    static func greyscale(_ image: NSImage, points: CGFloat, scale: CGFloat = 2) -> NSImage {
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
        // The rep is premultiplied RGBA; luminance of premultiplied values is the premultiplied
        // luminance, so the grey stays correctly weighted by its alpha.
        let row = rep.bytesPerRow
        for y in 0..<px {
            var p = bytes + y * row
            for _ in 0..<px {
                let lum = UInt8((Int(p[0]) * 77 + Int(p[1]) * 151 + Int(p[2]) * 28) >> 8)
                p[0] = lum; p[1] = lum; p[2] = lum
                p += 4
            }
        }
        let img = NSImage(size: NSSize(width: points, height: points))
        img.addRepresentation(rep)
        return img
    }

    /// Draw with `body` (flipped coordinates, as the strip's modules draw) into a `size`
    /// picture at `scale`, and return it in greyscale with every grey kept — the strip's
    /// modules, as the icons are.
    static func greyscale(size: NSSize, scale: CGFloat, _ body: @escaping (NSRect) -> Void) -> NSImage? {
        let canvas = FlippedCanvas(frame: NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        canvas.scale = scale
        canvas.body = body
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return nil }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let img = NSImage(size: canvas.bounds.size)
        img.addRepresentation(rep)
        // Same pixel count, same crisp edges: the art is pixel art, only its colour goes.
        return greyscalePixels(img, size: size)
    }

    /// `image` in greyscale at its own pixels, shown at `size` — for pixel art, where a smooth
    /// resample would blur the edges.
    static func greyscalePixels(_ image: NSImage, size: NSSize? = nil) -> NSImage {
        guard let src = deviceRGB(image) else { return image }
        let w = src.pixelsWide, h = src.pixelsHigh
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let out = rep.bitmapData, let inp = src.bitmapData else { return image }
        let srcRow = src.bytesPerRow, srcPix = src.samplesPerPixel, outRow = rep.bytesPerRow
        let alphaFirst = src.bitmapFormat.contains(.alphaFirst)
        let premultiplied = !src.bitmapFormat.contains(.alphaNonpremultiplied)
        for y in 0..<h {
            var p = inp + y * srcRow
            var q = out + y * outRow
            for _ in 0..<w {
                let a = Int(alphaFirst ? p[0] : p[srcPix - 1])
                let o = alphaFirst ? 1 : 0
                // The output rep is premultiplied: luminance of premultiplied RGB is the
                // premultiplied grey. A non-premultiplied source is premultiplied on the way.
                var lum = (Int(p[o]) * 77 + Int(p[o + 1]) * 151 + Int(p[o + 2]) * 28) >> 8
                if !premultiplied { lum = lum * a / 255 }
                q[0] = UInt8(lum); q[1] = UInt8(lum); q[2] = UInt8(lum); q[3] = UInt8(a)
                p += srcPix; q += 4
            }
        }
        let shown = size ?? image.size
        rep.size = shown
        let img = NSImage(size: shown)
        img.addRepresentation(rep)
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
