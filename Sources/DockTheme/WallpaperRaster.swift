import AppKit

/// PARKED. Complete and tested, but nothing calls it.
///
/// A fixed era raster — a tube's scanlines or a flat panel's cell grid — keyed to the screen's
/// pixel grid and baked into whatever it is given. It carried the dock and the desktop icons for
/// an afternoon and was replaced by Live Wallpaper Plus, which runs the SELECTED shader over the
/// same surfaces in one screen-space pass instead of a fixed pattern.
///
/// Kept rather than deleted because it solves a problem that pattern cannot: it needs no GPU pass
/// and no capture, it survives a screenshot, and its phase cannot drift. If the shader route ever
/// proves too expensive, wiring this back is one call.
///
/// The era raster on the dock and the desktop icons, at device-pixel resolution.
///
/// This is the second half of Live Wallpaper: the desktop picture is filtered live by whichever
/// shader is selected, and the furniture in front of it carries this instead. Running the
/// SELECTED shader over the furniture as well was built and rejected on the evidence: the shaders
/// compute their pattern from the position inside the picture they are handed, so filtering the
/// bar, each dock tile and each desktop icon separately restarts the raster in every one of them
/// and the scanlines do not line up — and magnifying a dock tile scales its finished bitmap, so
/// its lines grow with it. A fixed raster keyed to the SCREEN grid has neither problem, needs no
/// GPU pass, and measured smooth where the shader route did not.
///
/// It used to live in the screen shader, and it could not stay there. On a 1x 1080p panel a
/// raster needs three screen pixels to be resolved at all, and three screen pixels is also the
/// stroke width of the text on the desktop, so the raster and the content compete for the same
/// pixels. Three variants were built and measured on a text specimen and on a live frame:
///
/// - no raster at all, which leaves only a tone curve and reads as a grey filter;
/// - a uniform raster at a three pixel pitch, which measured 26% row modulation on a live
///   frame — a venetian blind across the whole screen;
/// - a raster gated to the smooth parts of the picture, which left a measured 3 to 8 percent
///   bright halo around every piece of text and so read as haze.
///
/// No strength setting resolves that, because the conflict is one of resolution and not of
/// degree. What does resolve it is moving the raster to the one surface nobody reads. Here it
/// can be strong enough to actually see, it costs nothing to work in, it is computed once when
/// the wallpaper is set rather than every frame, and it lands on exact device pixels — which a
/// shader running over a scaled screen capture cannot guarantee.
enum WallpaperRaster {

    /// Which era's raster to bake in. The raw values are persisted in `AppSettings`.
    enum Kind: String, CaseIterable {
        case off
        case crt
        case tft

        var label: String {
            switch self {
            case .off: return "None"
            case .crt: return "CRT scanlines"
            case .tft: return "TFT cell grid"
            }
        }

        /// Goes into the cached file name. Without it a changed raster would never reach the
        /// screen, because the file for that theme and that wallpaper already exists — the same
        /// trap the menu-bar tint fell into before its style got a cache tag.
        var cacheTag: String { rawValue }
    }

    /// One screen pixel per cell would be invisible and two land on the Nyquist limit, where
    /// consecutive rows carry almost the same phase and the modulation cancels. Three is the
    /// floor, measured.
    static let cell = 3

    /// How deep the scanline trough goes, as a fraction. Generous, because this is wallpaper.
    static let crtScanDepth = 0.38
    /// The RGB triad on top of the scanlines. Mean-cancelling over a full cell, so it adds
    /// chroma texture without tinting the picture. Kept well under the scan depth on purpose: at
    /// 0.18 the two modulations were comparable and the result read as a dot grid, which is a
    /// shadow-mask monitor seen through a magnifier, not a tube seen from a chair. A tube reads
    /// as LINES, so the lines have to dominate.
    static let crtMaskDepth = 0.07
    /// How dark the panel's row gap is; the column gap is 60% of it, the way a panel looked.
    static let tftMatrixStrength = 0.30

    /// How much of the wallpaper's raster the desktop furniture gets. The dock and the icon
    /// labels carry text, and a 38% trough over 11pt type is the same mistake this whole design
    /// exists to avoid. The wallpaper has nothing to read, the dock has.
    static let furnitureScale = 0.55

    /// The per-channel multiplier for one cell position, shared by the wallpaper baker and the
    /// view overlay so the two can never drift apart.
    static func factors(kind: Kind, strength: Double = 1.0) -> (row: [Double], col: [[Double]]) {
        var rowFactor = [Double](repeating: 1, count: cell)
        var colFactor = [[Double]](repeating: [Double](repeating: 1, count: cell), count: 3)
        guard kind != .off else { return (rowFactor, colFactor) }

        func lobe(_ k: Int, _ c: Int) -> Double {
            let phase = 2 * Double.pi * Double(c) / 3
            return 0.5 + 0.5 * cos(2 * Double.pi * Double(k) / Double(cell) - phase)
        }

        switch kind {
        case .off:
            break
        case .crt:
            for k in 0..<cell {
                let wave = 0.5 + 0.5 * cos(2 * Double.pi * Double(k) / Double(cell))
                // Strictly <= 1. A scanline centred on 1.0 would lift every other row above
                // white, which clips on anything bright and turns a raster into a wash.
                rowFactor[k] = 1 - crtScanDepth * strength * (1 - wave)
            }
            for c in 0..<3 {
                for k in 0..<cell {
                    colFactor[c][k] = 1 - crtMaskDepth * strength * (1 - lobe(k, c))
                }
            }
        case .tft:
            // A hard one-pixel gap, not a soft falloff. A soft one at a three pixel cell leaves
            // two of every three pixels partly dimmed in both axes, the row profile comes out
            // almost uniform, and the grid measured 0.3% on screen — it was not there. The hard
            // edge is also the point of difference against the tube: a panel's gap is a black
            // line, a tube's scanline is a soft cosine.
            for k in 0..<cell { rowFactor[k] = k == 0 ? 1 - tftMatrixStrength * strength : 1 }
            for c in 0..<3 {
                for k in 0..<cell {
                    let gap = k == 0 ? 1 - tftMatrixStrength * 0.6 * strength : 1.0
                    // A whisper of subpixel stripe, mean-cancelling like the tube's triad.
                    colFactor[c][k] = gap * (1 - 0.05 * strength * (1 - lobe(k, c)))
                }
            }
        }
        return (rowFactor, colFactor)
    }

    /// Multiplies the raster into an 8-bit RGBA buffer in place.
    ///
    /// Pure pixel arithmetic on purpose: no `NSImage`, no screen, so the pattern can be asserted
    /// in a test rather than looked at.
    ///
    /// - Parameters:
    ///   - px: RGBA8 pixels, row 0 first. Modified in place.
    ///   - bytesPerRow: may exceed `width * 4`; `NSBitmapImageRep` pads rows.
    static func apply(to px: inout [UInt8], width: Int, height: Int, bytesPerRow: Int,
                      kind: Kind, strength: Double = 1.0) {
        guard kind != .off, width > 0, height > 0, bytesPerRow >= width * 4 else { return }

        // One lookup and one multiply per channel, which keeps a 4K wallpaper well under a
        // frame even on the CPU.
        let (rowFactor, colFactor) = factors(kind: kind, strength: strength)

        for y in 0..<height {
            let rf = rowFactor[y % cell]
            let base = y * bytesPerRow
            for x in 0..<width {
                let i = base + x * 4
                let phase = x % cell
                for c in 0..<3 {
                    let v = Double(px[i + c]) * rf * colFactor[c][phase]
                    px[i + c] = UInt8(max(0, min(255, v.rounded())))
                }
            }
        }
    }

    /// A `cell` x `cell` tile that reproduces the same per-channel multiply when filled with
    /// `.sourceAtop` into a context that has already been drawn into.
    ///
    /// A multiply by `f` is exactly a composite of some colour `C` at alpha `a` where
    /// `(1 - a) + a * C = f`. Picking `a = 1 - min(f)` puts every channel of `C` in range, so a
    /// single pass carries the triad as well as the raster, from the same table the wallpaper is
    /// baked with.
    ///
    /// `.sourceAtop` is what makes this safe: measured against `.multiply` and `.plusDarker`, it
    /// is the only one of the three that leaves pixels with no alpha completely alone. So the
    /// dock's transparent margin stays transparent and the wallpaper behind it keeps the single
    /// raster it was baked with.
    ///
    /// It has to be filled inside the SAME `draw(_:)` that produced the content. Two earlier
    /// attempts went around that and both failed on screen while measuring correctly offline: a
    /// sibling overlay view is composited under any subview that owns a layer, and `DockItemView`
    /// and the icon image views do; and a `CALayer` with `compositingFilter = "multiplyBlendMode"`
    /// was simply not blended at all, which painted the tile over the dock as a white sheet.
    /// Anything the dock draws in its own context is covered here; anything drawn by a subview
    /// carries the raster in its own bitmap instead (see `rastered`).
    static func furnitureTile(kind: Kind, scale: CGFloat) -> NSImage? {
        guard kind != .off, scale > 0 else { return nil }
        let (rowFactor, colFactor) = factors(kind: kind, strength: furnitureScale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cell, pixelsHigh: cell,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: cell * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return nil }
        for y in 0..<cell {
            for x in 0..<cell {
                let f = (0..<3).map { rowFactor[y] * colFactor[$0][x] }
                let a = 1 - (f.min() ?? 1)
                let i = y * rep.bytesPerRow + x * 4
                guard a > 0.0001 else {
                    data[i] = 0; data[i+1] = 0; data[i+2] = 0; data[i+3] = 0
                    continue
                }
                // Premultiplied, which is what NSBitmapImageRep expects by default.
                for c in 0..<3 {
                    let colour = (f[c] - (1 - a)) / a
                    data[i + c] = UInt8(max(0, min(255, (colour * a * 255).rounded())))
                }
                data[i + 3] = UInt8(max(0, min(255, (a * 255).rounded())))
            }
        }
        let img = NSImage(size: NSSize(width: CGFloat(cell) / scale, height: CGFloat(cell) / scale))
        img.addRepresentation(rep)
        return img
    }

    /// `image` redrawn at exactly `pointSize` on this display, with the raster in its pixels.
    ///
    /// The raster has to be laid down at the size the icon is SHOWN at, not at the size the
    /// artwork happens to be: a 128px icon rastered and then scaled to 48pt would smear a three
    /// pixel pattern into nothing. Returns the original untouched when the raster is off, so
    /// callers need no special case.
    static func rastered(_ image: NSImage, pointSize: NSSize, scale: CGFloat, kind: Kind) -> NSImage {
        guard kind != .off, pointSize.width >= 1, pointSize.height >= 1, scale > 0 else { return image }
        let w = Int((pointSize.width * scale).rounded()), h = Int((pointSize.height * scale).rounded())
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: w * 4, bitsPerPixel: 32),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return image }
        let count = rep.bytesPerRow * h
        var px = [UInt8](UnsafeBufferPointer(start: data, count: count))
        // Premultiplied, so scaling the colour channels alone is the whole multiply and the
        // icon's own transparency is untouched.
        apply(to: &px, width: w, height: h, bytesPerRow: rep.bytesPerRow,
              kind: kind, strength: furnitureScale)
        px.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: count) }

        let out = NSImage(size: pointSize)
        out.addRepresentation(rep)
        return out
    }

    /// Which raster the furniture should carry right now, or `.off`.
    ///
    /// Two gates and no third setting. It follows Live Wallpaper actually RUNNING — the scope
    /// flag stays set after the effect is switched off, and reading that instead once put a
    /// raster on the dock while the wallpaper had none. And the era comes from the theme rather
    /// than from a picker: the year is already in the manifest, and a Windows 95 desktop wanting
    /// scanlines while a Windows XP one wants a cell grid is not a choice worth asking about.
    static var current: Kind {
        guard AppSettings.shared.liveWallpaperPlus,
              (NSApp.delegate as? AppDelegate)?.launcherLiveWallpaperActive == true
        else { return .off }
        // 2001 is the line: Windows XP and Mac OS X arrived on flat panels, everything before
        // them on a tube.
        let year = ThemeManager.shared.activeTheme?.config.release?.year ?? 1998
        return year >= 2001 ? .tft : .crt
    }

    /// Renders `image` at `pixelSize` and bakes the raster in. Returns nil for `.off` so callers
    /// can skip the whole step without a special case.
    static func rendered(_ image: NSImage, pixelSize: CGSize, kind: Kind) -> NSBitmapImageRep? {
        guard kind != .off else { return nil }
        let w = Int(pixelSize.width), h = Int(pixelSize.height)
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        let count = rep.bytesPerRow * h
        var px = [UInt8](UnsafeBufferPointer(start: data, count: count))
        apply(to: &px, width: w, height: h, bytesPerRow: rep.bytesPerRow, kind: kind)
        px.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: count) }
        return rep
    }
}
