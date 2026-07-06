import AppKit
import ImageIO

/// Procedural cursors — authored as 1-bit pixel art (no licensing constraints). Cursors
/// are drawn as a BLACK silhouette with an automatic 1px WHITE halo (the macOS/classic-Mac
/// pointer is black filled with a white outline — a white-filled shape just looks blank on
/// a light background). Antialiasing is off so the pixels stay crisp; doubled for Retina.
extension CursorThemeManager {

    /// Which cursor set a theme uses, keyed by the theme's INTERNAL name. Snow Leopard is
    /// added later (from the converted Soqueroeu/blueslime pack).
    static func cursorSet(for name: String) -> [CursorSlot: CursorFrames]? {
        switch name {
        case "Mac OS 6 classic":                        return loadBundledSet("Cursors/AppleSystem6")
        case "Mac OS 9.2 Classic":                      return loadBundledSet("Cursors/AppleSystem9")
        case "Mac OS X":                                return loadBundledSet("Cursors/MacOSX")
        case "Windows 3.1":                             return loadBundledSet("Cursors/Retrosmart")
        case "Windows XP":                              return loadBundledSet("Cursors/WindowsXP", scale: AppSettings.shared.xpCursorScale)
        default:                                        return nil
        }
    }

    /// A drawn black default-look pointer — the last-resort restore if no originals were
    /// captured (e.g. capture failed). Normally restore uses the captured originals.
    static func fallbackArrow() -> CursorFrames? {
        CursorFrames(images: [vectorArrow(fill: .black, outline: .white, lineWidth: 1.6)], frameCount: 1,
                     size: CGSize(width: 16, height: 16),
                     hotspot: CGPoint(x: 1, y: 1), frameDuration: 0)
    }

    // MARK: - Bundled cursor sets (converted packs → sprite sheet PNG + manifest)

    /// Load a bundled cursor set from `Resources/<subdir>` (a `manifest.json` keyed by
    /// CursorSlot rawValue + one `<slot>.png` sprite sheet per entry). Used for the Mac OS X
    /// (.cur/.ani) and retrosmart (X11/XPM) packs — same on-disk schema.
    static func loadBundledSet(_ subdir: String, scale: CGFloat = 1.0) -> [CursorSlot: CursorFrames]? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent(subdir, isDirectory: true),
              let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return nil }
        var set: [CursorSlot: CursorFrames] = [:]
        for (key, meta) in manifest {
            guard let slot = CursorSlot(rawValue: key),
                  let fc = meta["frameCount"] as? Int, fc >= 1,
                  let size = meta["size"] as? [Double], size.count == 2,
                  let hot = meta["hotspot"] as? [Double], hot.count == 2 else { continue }
            let dur = (meta["dur"] as? Double) ?? 0
            let url = dir.appendingPathComponent("\(key).png")   // one (possibly stacked) sprite sheet
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            set[slot] = CursorFrames(images: [normalized(img)], frameCount: fc,
                                     size: CGSize(width: size[0] * scale, height: size[1] * scale),
                                     hotspot: CGPoint(x: hot[0] * scale, y: hot[1] * scale), frameDuration: CGFloat(dur))
        }
        return set.isEmpty ? nil : set
    }

    /// A pointer drawn as a filled polygon with an outline. Vector, AA off, Retina-doubled.
    /// Tip (hotspot) at ~(1,1). `fill: .black, outline: .white` = macOS default look;
    /// `fill: .white, outline: .black` = the classic Mac pointer.
    private static func vectorArrow(fill: NSColor, outline: NSColor, lineWidth: CGFloat) -> CGImage {
        let pt: CGFloat = 16, scale: CGFloat = 2
        let px = Int(pt * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 4 * px, bitsPerPixel: 32)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.setShouldAntialias(false)
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: (pt - y) * scale) }
        let pts = [P(1, 1), P(1, 13), P(4.5, 9.5), P(7, 15), P(9, 14), P(6.5, 8.5), P(11, 8.5)]
        func path() { cg.beginPath(); cg.move(to: pts[0]); pts.dropFirst().forEach { cg.addLine(to: $0) }; cg.closePath() }
        cg.setStrokeColor(outline.cgColor); cg.setLineWidth(scale * lineWidth); cg.setLineJoin(.round)
        path(); cg.strokePath()
        cg.setFillColor(fill.cgColor)
        path(); cg.fillPath()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    /// Re-draw a loaded image into the exact bitmap format the CGS cursor API accepts
    /// (calibrated RGB, premultiplied, hard pixels). Loading a PNG straight from ImageIO
    /// yields a colour-managed image the private API silently refuses to display — MaCursor
    /// hits the same and rebuilds each rep; this is that normalisation.
    private static func normalized(_ img: CGImage) -> CGImage {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }
}
