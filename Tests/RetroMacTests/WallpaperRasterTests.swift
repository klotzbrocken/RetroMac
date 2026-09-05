import XCTest
@testable import RetroMac

/// The raster is pure pixel arithmetic, so the things that went wrong when it lived in the
/// shader can be asserted here instead of squinted at: that it never brightens (a raster centred
/// on 1.0 clips on anything bright and turns into a wash), that it actually modulates (a soft
/// falloff at a three pixel cell measured 0.3% on screen, i.e. it was not there), and that the
/// colour triad cancels (an uncancelled one dyes the whole desktop).
final class WallpaperRasterTests: XCTestCase {

    private let w = 90, h = 90

    private func flatBuffer(_ value: UInt8 = 180) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            px[i] = value; px[i+1] = value; px[i+2] = value
        }
        return px
    }

    private func rowMeans(_ px: [UInt8]) -> [Double] {
        (0..<h).map { y in
            var s = 0.0
            for x in 0..<w {
                let i = (y * w + x) * 4
                s += (Double(px[i]) + Double(px[i+1]) + Double(px[i+2])) / 3
            }
            return s / Double(w)
        }
    }

    func testOffLeavesEveryPixelAlone() {
        var px = flatBuffer()
        let before = px
        WallpaperRaster.apply(to: &px, width: w, height: h, bytesPerRow: w * 4, kind: .off)
        XCTAssertEqual(px, before)
    }

    func testCRTNeverBrightensAPixel() {
        var px = flatBuffer()
        WallpaperRaster.apply(to: &px, width: w, height: h, bytesPerRow: w * 4, kind: .crt)
        for i in stride(from: 0, to: px.count, by: 4) {
            XCTAssertLessThanOrEqual(px[i], 180)
            XCTAssertLessThanOrEqual(px[i+1], 180)
            XCTAssertLessThanOrEqual(px[i+2], 180)
        }
    }

    func testTFTNeverBrightensAPixel() {
        var px = flatBuffer()
        WallpaperRaster.apply(to: &px, width: w, height: h, bytesPerRow: w * 4, kind: .tft)
        for i in stride(from: 0, to: px.count, by: 4) {
            XCTAssertLessThanOrEqual(px[i], 180)
        }
    }

    func testCRTScanlineIsActuallyThere() {
        var px = flatBuffer()
        WallpaperRaster.apply(to: &px, width: w, height: h, bytesPerRow: w * 4, kind: .crt)
        let means = rowMeans(px)
        let phase = (0..<3).map { k in
            stride(from: k, to: h, by: 3).map { means[$0] }.reduce(0, +) / Double(h / 3)
        }
        // The lit row against the darkest trough, as a fraction of the lit row.
        let depth = (phase.max()! - phase.min()!) / phase.max()!
        XCTAssertGreaterThan(depth, 0.20, "the scanline has to be visible, not theoretical")
        // Every row inside a cell must differ, or the pattern has a period of 1 and is a filter.
        XCTAssertNotEqual(phase[0], phase[1])
    }

    func testTFTDarkensExactlyOneRowInThree() {
        var px = flatBuffer()
        WallpaperRaster.apply(to: &px, width: w, height: h, bytesPerRow: w * 4, kind: .tft)
        let means = rowMeans(px)
        let gap = means.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        let lit = means.enumerated().filter { $0.offset % 3 != 0 }.map(\.element)
        XCTAssertLessThan(gap.max()!, lit.min()!, "the gap row must be darker than every lit row")
        XCTAssertEqual(Set(lit.map { ($0 * 100).rounded() }).count, 1, "lit rows must match")
    }

    func testTriadDoesNotTintThePicture() {
        for kind in [WallpaperRaster.Kind.crt, .tft] {
            var px = flatBuffer()
            WallpaperRaster.apply(to: &px, width: w, height: h, bytesPerRow: w * 4, kind: kind)
            var totals = [0.0, 0.0, 0.0]
            for i in stride(from: 0, to: px.count, by: 4) {
                for c in 0..<3 { totals[c] += Double(px[i+c]) }
            }
            let spread = (totals.max()! - totals.min()!) / totals.max()!
            XCTAssertLessThan(spread, 0.01, "\(kind) leaves a colour cast of \(spread * 100)%")
        }
    }

    /// Not an assertion: writes the baked wallpaper out so it can be looked at 1:1.
    /// Set RETROMAC_RASTER_PREVIEW=<image path> and RETROMAC_RASTER_PREVIEW_OUT=<dir>.
    func testRenderRasterPreview() throws {
        let env = ProcessInfo.processInfo.environment
        guard let src = env["RETROMAC_RASTER_PREVIEW"] else {
            throw XCTSkip("Set RETROMAC_RASTER_PREVIEW=<image path> to render a preview.")
        }
        let out = env["RETROMAC_RASTER_PREVIEW_OUT"] ?? NSTemporaryDirectory()
        let img = try XCTUnwrap(NSImage(contentsOfFile: src))
        for kind in [WallpaperRaster.Kind.crt, .tft] {
            let rep = try XCTUnwrap(WallpaperRaster.rendered(
                img, pixelSize: CGSize(width: 1920, height: 1080), kind: kind))
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: out).appendingPathComponent("wp-\(kind.rawValue).png")
            try png.write(to: url)
            print("[raster] \(url.path)")
        }
    }

    // MARK: - The overlay that puts the same raster on the dock and the desktop icons

    func testFurnitureTileIsWeakerThanTheWallpaper() {
        // The wallpaper has nothing to read on it, the dock has. If the furniture ever gets the
        // full trough, that is the 11pt-type mistake this whole design exists to avoid.
        XCTAssertLessThan(WallpaperRaster.furnitureScale, 1.0)
        let full = WallpaperRaster.factors(kind: .crt).row.min()!
        let soft = WallpaperRaster.factors(kind: .crt, strength: WallpaperRaster.furnitureScale).row.min()!
        XCTAssertGreaterThan(soft, full)
    }

    func testFurnitureTileIsNilWhenOff() {
        XCTAssertNil(WallpaperRaster.furnitureTile(kind: .off, scale: 2))
    }

    func testFurnitureTileMapsOneCellToOneDevicePixel() throws {
        for scale in [CGFloat(1), 2] {
            let tile = try XCTUnwrap(WallpaperRaster.furnitureTile(kind: .crt, scale: scale))
            let rep = try XCTUnwrap(tile.representations.first)
            XCTAssertEqual(rep.pixelsWide, WallpaperRaster.cell)
            XCTAssertEqual(tile.size.width, CGFloat(WallpaperRaster.cell) / scale, accuracy: 0.001)
        }
    }

    /// The operator is the whole safety argument for laying this over the dock, so it gets
    /// asserted rather than assumed: `.sourceAtop` must darken what is already drawn and leave
    /// pixels with no alpha completely alone, or the wallpaper behind the dock's transparent
    /// margin would be rastered a second time. Measured against the alternatives: `.multiply`
    /// and `.plusDarker` both paint into the transparent half.
    func testSourceAtopDarkensContentAndSparesTransparentPixels() throws {
        let side = 12
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4, bitsPerPixel: 32))
        let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side / 2, height: side).fill()
        let tile = try XCTUnwrap(WallpaperRaster.furnitureTile(kind: .crt, scale: 1))
        ctx.compositingOperation = .sourceAtop
        NSColor(patternImage: tile).setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()

        let data = try XCTUnwrap(rep.bitmapData)
        var rows = Set<Int>(), darkened = false
        for y in 0..<side {
            for x in (side / 2)..<side {
                XCTAssertEqual(data[y * rep.bytesPerRow + x * 4 + 3], 0,
                               "transparent pixel at \(x),\(y) was painted")
            }
            XCTAssertEqual(data[y * rep.bytesPerRow + 3], 255, "opaque half lost its alpha")
            let v = data[y * rep.bytesPerRow]
            rows.insert(Int(v))
            if v < 255 { darkened = true }
        }
        XCTAssertTrue(darkened, "the raster did not darken the opaque half at all")
        XCTAssertGreaterThan(rows.count, 1, "every row came out the same: no raster")
    }

    // MARK: - The raster baked into an icon

    func testRasteredReturnsTheOriginalWhenOff() {
        let img = NSImage(size: NSSize(width: 16, height: 16))
        XCTAssertTrue(WallpaperRaster.rastered(img, pointSize: NSSize(width: 16, height: 16),
                                               scale: 1, kind: .off) === img)
    }

    /// The raster has to be laid down at the size the icon is SHOWN at. If this ever renders at
    /// the artwork's own size instead, a three pixel pattern gets scaled into noise.
    func testRasteredRendersAtTheDisplayedSize() throws {
        let img = NSImage(size: NSSize(width: 128, height: 128))
        img.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 128, height: 128).fill(); img.unlockFocus()
        for scale in [CGFloat(1), 2] {
            let out = WallpaperRaster.rastered(img, pointSize: NSSize(width: 48, height: 48),
                                               scale: scale, kind: .crt)
            let rep = try XCTUnwrap(out.representations.first)
            XCTAssertEqual(rep.pixelsWide, Int(48 * scale))
            XCTAssertEqual(out.size.width, 48, accuracy: 0.001)
        }
    }

    func testRasteredKeepsTheIconsOwnTransparency() throws {
        // A 24x24 icon that is opaque on the left half only, like any real icon's silhouette.
        let img = NSImage(size: NSSize(width: 24, height: 24))
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 24).fill()
        img.unlockFocus()

        let out = WallpaperRaster.rastered(img, pointSize: NSSize(width: 24, height: 24),
                                           scale: 1, kind: .crt)
        let rep = try XCTUnwrap(out.representations.first as? NSBitmapImageRep)
        let data = try XCTUnwrap(rep.bitmapData)
        var darkened = false
        for y in 0..<rep.pixelsHigh {
            XCTAssertEqual(data[y * rep.bytesPerRow + 20 * 4 + 3], 0,
                           "the icon's transparent half was filled in at row \(y)")
            if data[y * rep.bytesPerRow + 2 * 4] < 255 { darkened = true }
        }
        XCTAssertTrue(darkened, "the icon came back unrastered")
    }

    func testHonoursRowPadding() {
        // NSBitmapImageRep pads rows; writing past the width would corrupt the next row.
        let padded = w * 4 + 12
        var px = [UInt8](repeating: 7, count: padded * h)
        for y in 0..<h { for x in 0..<w {
            let i = y * padded + x * 4
            px[i] = 180; px[i+1] = 180; px[i+2] = 180; px[i+3] = 255
        }}
        WallpaperRaster.apply(to: &px, width: w, height: h, bytesPerRow: padded, kind: .crt)
        for y in 0..<h {
            for b in (w * 4)..<padded {
                XCTAssertEqual(px[y * padded + b], 7, "padding at row \(y) was overwritten")
            }
        }
    }
}
