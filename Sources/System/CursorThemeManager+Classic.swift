import AppKit

/// Procedural cursors — authored as 1-bit pixel art (no licensing constraints). Cursors
/// are drawn as a BLACK silhouette with an automatic 1px WHITE halo (the macOS/classic-Mac
/// pointer is black filled with a white outline — a white-filled shape just looks blank on
/// a light background). Antialiasing is off so the pixels stay crisp; doubled for Retina.
extension CursorThemeManager {

    /// Which cursor set a theme uses, keyed by the theme's INTERNAL name. Snow Leopard is
    /// added later (from the converted Soqueroeu/blueslime pack).
    static func cursorSet(for name: String) -> [CursorSlot: CursorFrames]? {
        switch name {
        case "Mac OS 6 classic", "Mac OS 9.2 Classic": return classicMacSet()
        default: return nil
        }
    }

    /// A standard black pointer used to "restore" — turning the override off doesn't reveal
    /// the built-in cursors on Tahoe (the slot goes blank/white), and NSCursor.arrow.image
    /// is empty outside a full app context, so we draw the macOS default-look arrow.
    static func standardCursorSet() -> [CursorSlot: CursorFrames] {
        [.arrow: CursorFrames(frames: [vectorArrow(fill: .black, outline: .white, lineWidth: 1.6)],
                              size: CGSize(width: 16, height: 16),
                              hotspot: CGPoint(x: 1, y: 1), frameDuration: 0),
         .ibeam: CursorFrames(frames: [image(silhouette: iBeam)],
                              size: CGSize(width: 8, height: 16),
                              hotspot: CGPoint(x: 4, y: 8), frameDuration: 0)]
    }

    // MARK: - Classic Mac set

    private static func classicMacSet() -> [CursorSlot: CursorFrames] {
        // The classic Mac pointer is WHITE-filled with a black outline (vs the black macOS
        // default) — that's the visible retro difference from the restored cursor.
        [.arrow: CursorFrames(frames: [vectorArrow(fill: .white, outline: .black, lineWidth: 1.2)],
                              size: CGSize(width: 16, height: 16),
                              hotspot: CGPoint(x: 1, y: 1), frameDuration: 0),
         .ibeam: CursorFrames(frames: [image(silhouette: iBeam)],
                              size: CGSize(width: 8, height: 16),
                              hotspot: CGPoint(x: 4, y: 8), frameDuration: 0),
         .wait:  CursorFrames(frames: [image(faced: watchFrame1), image(faced: watchFrame2)],
                              size: CGSize(width: 16, height: 16),
                              hotspot: CGPoint(x: 8, y: 8), frameDuration: 0.4)]
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

    // MARK: - Renderers

    /// Render a BLACK silhouette (`X`) with an auto 1px WHITE halo on adjacent transparent
    /// cells. Retina-doubled, hard pixels.
    private static func image(silhouette rows: [String], scale: Int = 2) -> CGImage {
        let h = rows.count
        let w = rows.map { $0.count }.max() ?? h
        var black = Array(repeating: Array(repeating: false, count: w), count: h)
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() where ch == "X" || ch == "#" { black[r][c] = true }
        }
        func isBlack(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < h && c >= 0 && c < w && black[r][c] }
        return draw(w: w, h: h, scale: scale) { r, c in
            if black[r][c] { return .black }
            for dr in -1...1 { for dc in -1...1 where isBlack(r + dr, c + dc) { return .white } }
            return nil
        }
    }

    /// Render a grid with explicit `X` = black, `.` = white, space = transparent (used for
    /// the watch face, which needs its own white interior — no auto-halo).
    private static func image(faced rows: [String], scale: Int = 2) -> CGImage {
        let h = rows.count
        let w = rows.map { $0.count }.max() ?? h
        let arr = rows.map { Array($0) }
        return draw(w: w, h: h, scale: scale) { r, c in
            let ch = c < arr[r].count ? arr[r][c] : " "
            switch ch { case "X", "#": return .black; case ".", "o": return .white; default: return nil }
        }
    }

    private static func draw(w: Int, h: Int, scale: Int, color: (Int, Int) -> NSColor?) -> CGImage {
        let pw = w * scale, ph = h * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 4 * pw, bitsPerPixel: 32)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.setShouldAntialias(false)
        for r in 0..<h {
            for c in 0..<w {
                guard let col = color(r, c) else { continue }
                col.setFill()
                cg.fill(CGRect(x: c * scale, y: (h - 1 - r) * scale, width: scale, height: scale))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    // MARK: - Silhouettes (X = filled; white outline is added automatically)

    private static let iBeam: [String] = [
        "XXXXX",
        "  X  ",
        "  X  ",
        "  X  ",
        "  X  ",
        "  X  ",
        "  X  ",
        "  X  ",
        "  X  ",
        "  X  ",
        "  X  ",
        "XXXXX",
    ]

    // Wristwatch (black outline, white face, black hands) — replaces the beach ball.
    private static let watchFrame1: [String] = [
        "     XXX     ",
        "     X.X     ",
        "   XXXXXXX   ",
        "  X.......X  ",
        " X....X....X ",
        " X....X....X ",
        "X.....X.....X",
        "X.....XXXX..X",
        " X.........X ",
        " X.........X ",
        "  X.......X  ",
        "   XXXXXXX   ",
        "     X.X     ",
        "     XXX     ",
    ]
    private static let watchFrame2: [String] = [
        "     XXX     ",
        "     X.X     ",
        "   XXXXXXX   ",
        "  X.......X  ",
        " X.........X ",
        " X....X....X ",
        "X.....X.....X",
        "X.....X.....X",
        " X....XXX..X ",
        " X.........X ",
        "  X.......X  ",
        "   XXXXXXX   ",
        "     X.X     ",
        "     XXX     ",
    ]
}
