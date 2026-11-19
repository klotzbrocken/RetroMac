// Draws every picture of the Amiga Workbench 4.1 theme: the desktop and dock icons (each with
// its selected state), the reconstructed 2008 backdrop and the AmigaOS 4.1 boot splash.
// Nothing is copied from a theme pack: the shapes are drawn here after the 2008 AmigaOne
// screenshots (Screenshots-2008, Referenzdetails-2008), the TAWS and Mason icons only looked at.
// Deterministic: the same bytes on every run.
//
//   swift Scripts/amiga-assets.swift            (writes into the theme bundle)
import AppKit

let bundle = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Themes/AmigaWorkbench41.retromactheme")
let iconDir = bundle.appendingPathComponent("icons")
try? FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Plumbing

func color(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat(v >> 16 & 255) / 255, CGFloat(v >> 8 & 255) / 255, CGFloat(v & 255) / 255, a])!
}
/// A canvas `w`×`h` units at `scale` pixels per unit, y running down.
func canvas(_ w: Int, _ h: Int, scale: CGFloat = 1, opaque: Bool = false) -> CGContext {
    let c = CGContext(data: nil, width: Int(CGFloat(w) * scale), height: Int(CGFloat(h) * scale), bitsPerComponent: 8, bytesPerRow: 0,
                      space: srgb, bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    c.translateBy(x: 0, y: CGFloat(h) * scale)
    c.scaleBy(x: scale, y: -scale)
    c.interpolationQuality = .high
    return c
}
func write(_ img: CGImage, _ url: URL, jpeg: Bool = false) {
    let rep = NSBitmapImageRep(cgImage: img)
    let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])! : rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
    print("wrote", url.lastPathComponent)
}
func linear(_ c: CGContext, _ path: CGPath, _ stops: [(CGFloat, UInt32)], from a: CGPoint, to b: CGPoint, alpha: CGFloat = 1) {
    let g = CGGradient(colorsSpace: srgb, colors: stops.map { color($0.1, alpha) } as CFArray, locations: stops.map { $0.0 })!
    c.saveGState(); c.addPath(path); c.clip(); c.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]); c.restoreGState()
}
func radial(_ c: CGContext, clip: CGPath?, center: CGPoint, radius: CGFloat, _ stops: [(CGFloat, UInt32, CGFloat)]) {
    let g = CGGradient(colorsSpace: srgb, colors: stops.map { color($0.1, $0.2) } as CFArray, locations: stops.map { $0.0 })!
    c.saveGState(); if let clip { c.addPath(clip); c.clip() }
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    c.restoreGState()
}
func stroke(_ c: CGContext, _ path: CGPath, _ col: UInt32, _ w: CGFloat, alpha: CGFloat = 1) {
    c.saveGState(); c.addPath(path); c.setStrokeColor(color(col, alpha)); c.setLineWidth(w); c.setLineJoin(.round); c.strokePath(); c.restoreGState()
}
func fill(_ c: CGContext, _ path: CGPath, _ col: UInt32, alpha: CGFloat = 1) {
    c.saveGState(); c.addPath(path); c.setFillColor(color(col, alpha)); c.fillPath(); c.restoreGState()
}
func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) }); p.closeSubpath(); return p
}
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func text(_ s: String, font: String, size: CGFloat) -> CGPath {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: f]))
    let out = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
        for i in 0..<n {
            guard let g = CTFontCreatePathForGlyph(f, glyphs[i], nil) else { continue }
            // Glyph space runs up; the canvas runs down.
            out.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: 0).scaledBy(x: 1, y: -1))
        }
    }
    return out
}

// MARK: - The Boing ball

/// The red and white ball, shaded per pixel: 16 segments round, 8 bands down, tilted 18° the way
/// the ball always leans, lit from the top left with a highlight.
func ball(diameter px: Int, tilt: Double = -0.32, spin: Double = 0.25, translucent: Bool = false) -> CGImage {
    let n = px, ss = 3
    var data = [UInt8](repeating: 0, count: n * n * 4)
    let lx = -0.45, ly = -0.55, lz = 0.70
    let ll = sqrt(lx * lx + ly * ly + lz * lz)
    for y in 0..<n { for x in 0..<n {
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for sy in 0..<ss { for sx in 0..<ss {
            let u = (Double(x) + (Double(sx) + 0.5) / Double(ss)) / Double(n) * 2 - 1
            let v = (Double(y) + (Double(sy) + 0.5) / Double(ss)) / Double(n) * 2 - 1
            let d = u * u + v * v
            guard d <= 1 else { continue }
            let z = sqrt(1 - d)
            // Tilt round the view axis, then read longitude and latitude.
            let xr = u * cos(tilt) - v * sin(tilt), yr = u * sin(tilt) + v * cos(tilt)
            let lon = atan2(xr, z) + spin, lat = asin(max(-1, min(1, yr)))
            let red = (Int(floor(lon / (.pi / 8) + 64)) + Int(floor(lat / (.pi / 8) + 64))) & 1 == 0
            let base: (Double, Double, Double) = red ? (0.84, 0.10, 0.12) : (0.97, 0.96, 0.96)
            let lambert = max(0, (u * lx + v * ly + z * lz) / ll)
            let spec = pow(max(0, (u * lx + v * ly + z * (lz + 1)) / sqrt(lx * lx + ly * ly + (lz + 1) * (lz + 1))), 40)
            let k = 0.38 + 0.72 * lambert
            r += min(1, base.0 * k + 0.75 * spec); g += min(1, base.1 * k + 0.75 * spec); b += min(1, base.2 * k + 0.75 * spec)
            a += translucent ? 0.93 : 1
        }}
        let m = Double(ss * ss)
        let i = (y * n + x) * 4
        // premultiplied: the colour sums already carry one count per covered sample
        let cover = a / m
        data[i] = UInt8(min(255, r / m * 255 * (translucent ? 0.93 : 1))); data[i + 1] = UInt8(min(255, g / m * 255 * (translucent ? 0.93 : 1)))
        data[i + 2] = UInt8(min(255, b / m * 255 * (translucent ? 0.93 : 1))); data[i + 3] = UInt8(min(255, cover * 255))
    }}
    let c = CGContext(data: &data, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: srgb,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return c.makeImage()!
}

// MARK: - Icons (48 units square, written at 96 px)

typealias Painter = (CGContext) -> Void

/// The soft shadow the Workbench draws under its icons, down and to the right.
func withShadow(_ c: CGContext, _ body: Painter) {
    c.saveGState()
    c.setShadow(offset: CGSize(width: 1.6, height: -1.6), blur: 1.8, color: color(0x000000, 0.45))
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    body(c)
    c.endTransparencyLayer()
    c.restoreGState()
}

func harddrive(_ c: CGContext) {
    let top = poly([(11, 10), (35, 10), (41.5, 21), (4.5, 21)])
    linear(c, top, [(0, 0xF6F6F6), (1, 0xC6C6C6)], from: CGPoint(x: 0, y: 10), to: CGPoint(x: 0, y: 21))
    radial(c, clip: top, center: CGPoint(x: 31, y: 14.5), radius: 5.5, [(0, 0xFFFFFF, 1), (0.5, 0xFFFFFF, 0.55), (1, 0xFFFFFF, 0)])
    let front = rrect(4.5, 21, 37, 12.5, 1.5)
    linear(c, front, [(0, 0xEDEDED), (0.12, 0xFAFAFA), (0.2, 0xDCDCDC), (1, 0xA9A9A9)], from: CGPoint(x: 0, y: 21), to: CGPoint(x: 0, y: 33.5))
    let all = CGMutablePath(); all.addPath(top); all.addPath(front)
    stroke(c, top, 0x7C7C7C, 0.6); stroke(c, front, 0x6A6A6A, 0.6)
    fill(c, rrect(8, 27, 2.2, 3, 0.4), 0x2FC12F); fill(c, rrect(8.4, 27.3, 1, 1, 0.3), 0xC8FFC8)
    fill(c, rrect(11.6, 27, 2.2, 3, 0.4), 0xEBD31D); fill(c, rrect(12, 27.3, 1, 1, 0.3), 0xFFF8C0)
    fill(c, poly([(5.5, 32.2), (40.5, 32.2), (40.5, 33), (5.5, 33)]), 0x8A8A8A, alpha: 0.6)
}
func systemDrive(_ c: CGContext) {
    harddrive(c)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 1, height: -1.5), blur: 1.5, color: color(0x000000, 0.5))
    c.draw(ball(diameter: 120), in: CGRect(x: 23.5, y: 18, width: 21, height: 21))
    c.restoreGState()
}
func floppy(_ c: CGContext) {
    let body = poly([(7, 4.5), (37, 4.5), (41, 8.5), (41, 43.5), (7, 43.5)])
    linear(c, body, [(0, 0x6E8AC9), (1, 0x3D5799)], from: CGPoint(x: 7, y: 4), to: CGPoint(x: 41, y: 44))
    stroke(c, poly([(8.2, 5.7), (36.5, 5.7), (39.8, 9), (39.8, 42.3), (8.2, 42.3)]), 0x9DB2E2, 0.6, alpha: 0.8)
    stroke(c, body, 0x223566, 0.7)
    let shutter = CGPath(rect: CGRect(x: 15, y: 4.5, width: 18.5, height: 13), transform: nil)
    linear(c, shutter, [(0, 0xFDFDFD), (0.45, 0xD6D6D6), (1, 0x9C9C9C)], from: CGPoint(x: 15, y: 0), to: CGPoint(x: 33.5, y: 0))
    stroke(c, shutter, 0x6F6F6F, 0.5)
    fill(c, CGPath(rect: CGRect(x: 27.3, y: 6.5, width: 3.6, height: 9.5), transform: nil), 0x3D5799)
    let label = rrect(11, 22, 26, 21.5, 1.5)
    linear(c, label, [(0, 0xFFFFFF), (0.85, 0xF2F2F2), (1, 0xD8D8D8)], from: CGPoint(x: 0, y: 22), to: CGPoint(x: 0, y: 43.5))
    stroke(c, label, 0x8090B8, 0.5)
    fill(c, CGPath(rect: CGRect(x: 8.2, y: 40.2, width: 1.8, height: 1.8), transform: nil), 0x1C2A55)
    fill(c, CGPath(rect: CGRect(x: 38, y: 40.2, width: 1.8, height: 1.8), transform: nil), 0x1C2A55)
}
func ramChip(_ c: CGContext) {
    // Pins first, under the slab: four down each slanted side.
    for i in 0..<4 {
        let t = CGFloat(i) / 3
        let lx = 11.5 - 5.5 * t, ly = 14 + 15 * t
        fill(c, poly([(lx, ly), (lx - 3.4, ly - 0.6), (lx - 3.9, ly + 1.5), (lx - 0.4, ly + 2.1)]), 0xE6E6E6)
        let rx = 36.5 + 5.5 * t
        fill(c, poly([(rx, ly), (rx + 3.4, ly - 0.6), (rx + 3.9, ly + 1.5), (rx + 0.4, ly + 2.1)]), 0xE6E6E6)
    }
    let slab = poly([(12.5, 11.5), (35.5, 11.5), (42, 31), (6, 31)])
    linear(c, slab, [(0, 0x585858), (0.5, 0x2A2A2A), (1, 0x101010)], from: CGPoint(x: 0, y: 11.5), to: CGPoint(x: 0, y: 31))
    radial(c, clip: slab, center: CGPoint(x: 30, y: 20.5), radius: 6, [(0, 0xFFFFFF, 1), (0.3, 0xE8E8E8, 0.7), (1, 0x808080, 0)])
    let edge = poly([(6, 31), (42, 31), (42, 34), (6, 34)])
    linear(c, edge, [(0, 0x1A1A1A), (1, 0x000000)], from: CGPoint(x: 0, y: 31), to: CGPoint(x: 0, y: 34))
    stroke(c, slab, 0x000000, 0.5)
}
/// A Workbench drawer: the blue cabinet front with its silver handle (TAWS DefDrawer as the model).
func drawer(_ c: CGContext) {
    let body = rrect(5.5, 9, 37, 34, 3)
    linear(c, body, [(0, 0x6B8FD8), (0.5, 0x4766B3), (1, 0x2D4688)], from: CGPoint(x: 0, y: 9), to: CGPoint(x: 0, y: 43))
    let lid = rrect(5.5, 9, 37, 5.5, 3)
    linear(c, lid, [(0, 0xB4C8F0), (1, 0x7E9DDB)], from: CGPoint(x: 0, y: 9), to: CGPoint(x: 0, y: 14.5))
    fill(c, CGPath(rect: CGRect(x: 7, y: 29, width: 34, height: 0.8), transform: nil), 0xA9BEEA, alpha: 0.85)
    fill(c, CGPath(rect: CGRect(x: 7, y: 29.8, width: 34, height: 0.6), transform: nil), 0x1E2F62, alpha: 0.5)
    let handle = rrect(15.5, 33.5, 17, 3.6, 1.8)
    linear(c, handle, [(0, 0xFFFFFF), (0.5, 0xD0D0D0), (1, 0x7E7E7E)], from: CGPoint(x: 0, y: 33.5), to: CGPoint(x: 0, y: 37.1))
    fill(c, rrect(16, 37.1, 16, 0.9, 0.45), 0x16244E, alpha: 0.65)
    stroke(c, body, 0x1A2A58, 0.7)
    // The gloss down the left of the cabinet.
    linear(c, rrect(6.5, 15, 4, 13, 1.5), [(0, 0xFFFFFF), (1, 0xFFFFFF)], from: .zero, to: CGPoint(x: 1, y: 0), alpha: 0.12)
}
func drawerWith(_ emblem: @escaping Painter) -> Painter { { c in drawer(c); emblem(c) } }

func prefsEmblem(_ c: CGContext) {
    let ring = CGPath(ellipseIn: CGRect(x: 15, y: 4.5, width: 18, height: 18), transform: nil)
    linear(c, ring, [(0, 0xFAFAFA), (1, 0x9AA2B4)], from: CGPoint(x: 0, y: 4.5), to: CGPoint(x: 0, y: 22.5))
    let face = CGPath(ellipseIn: CGRect(x: 17.3, y: 6.8, width: 13.4, height: 13.4), transform: nil)
    linear(c, face, [(0, 0x5E79B8), (1, 0xA9BCE6)], from: CGPoint(x: 0, y: 6.8), to: CGPoint(x: 0, y: 20.2))
    stroke(c, ring, 0x4A5470, 0.6)
    // The slider knob of the Prefs emblem: a bar across and a yellow stem.
    fill(c, rrect(19.5, 11, 9, 2.6, 1), 0xF0F0F0); stroke(c, rrect(19.5, 11, 9, 2.6, 1), 0x404858, 0.4)
    fill(c, rrect(23.1, 13.4, 1.8, 5.2, 0.5), 0xE8C21C)
}
func utilitiesEmblem(_ c: CGContext) {
    c.saveGState(); c.translateBy(x: 24, y: 16); c.rotate(by: -.pi / 4 * 1.0)
    let shaft = CGPath(rect: CGRect(x: -0.9, y: -2, width: 1.8, height: 16), transform: nil)
    linear(c, shaft, [(0, 0xEDEDED), (1, 0x7C7C7C)], from: CGPoint(x: -1, y: 0), to: CGPoint(x: 1, y: 0))
    fill(c, poly([(-0.9, 14), (0.9, 14), (0, 16)]), 0x5E5E5E)
    let handle = rrect(-2.6, -15, 5.2, 13.5, 2.4)
    linear(c, handle, [(0, 0xE05A3A), (0.5, 0xB02818), (1, 0x6A1208)], from: CGPoint(x: -2.6, y: 0), to: CGPoint(x: 2.6, y: 0))
    for k in 0..<3 { fill(c, CGPath(rect: CGRect(x: -2.6, y: -12 + CGFloat(k) * 3.2, width: 5.2, height: 0.6), transform: nil), 0x5A0E06, alpha: 0.6) }
    stroke(c, handle, 0x3A0804, 0.4)
    c.restoreGState()
}
func ballEmblem(_ c: CGContext) {
    c.saveGState(); c.setShadow(offset: CGSize(width: 0.8, height: -1.2), blur: 1.2, color: color(0, 0.45))
    c.draw(ball(diameter: 120), in: CGRect(x: 15, y: 3.5, width: 18, height: 18)); c.restoreGState()
}
func fontEmblem(_ c: CGContext) {
    let f = text("F", font: "Georgia-Bold", size: 22)
    c.saveGState(); c.translateBy(x: 17.5, y: 23)
    linear(c, f, [(0, 0xF57CE0), (1, 0xA0168A)], from: CGPoint(x: 0, y: -16), to: CGPoint(x: 0, y: 0))
    stroke(c, f, 0x4A0A40, 0.5)
    c.restoreGState()
}
func trashcan(_ c: CGContext) {
    let body = poly([(13, 15), (35, 15), (33, 43), (15, 43)])
    linear(c, body, [(0, 0x8C8C8C), (0.3, 0xF4F4F4), (0.55, 0xC8C8C8), (1, 0x6E6E6E)], from: CGPoint(x: 13, y: 0), to: CGPoint(x: 35, y: 0))
    for k in 0..<5 {
        let x = 17 + CGFloat(k) * 3.6
        fill(c, poly([(x, 18), (x + 0.9, 18), (x + 0.75, 40), (x + 0.1, 40)]), 0x5A5A5A, alpha: 0.45)
    }
    stroke(c, body, 0x4A4A4A, 0.6)
    let lid = CGPath(ellipseIn: CGRect(x: 10, y: 10.5, width: 28, height: 7), transform: nil)
    linear(c, lid, [(0, 0xFFFFFF), (1, 0x8E8E8E)], from: CGPoint(x: 0, y: 10.5), to: CGPoint(x: 0, y: 17.5))
    stroke(c, lid, 0x4A4A4A, 0.6)
    let knob = rrect(20, 7.2, 8, 4, 2)
    linear(c, knob, [(0, 0xF0F0F0), (1, 0x8A8A8A)], from: CGPoint(x: 0, y: 7.2), to: CGPoint(x: 0, y: 11.2))
    stroke(c, knob, 0x4A4A4A, 0.5)
}
/// The default project: a sheet with its corner turned up at the bottom right (DefProject).
func project(_ c: CGContext) {
    let sheet = poly([(11, 4.5), (37, 4.5), (37, 36), (30, 43.5), (11, 43.5)])
    linear(c, sheet, [(0, 0xFDFDFD), (1, 0xE2E2E2)], from: CGPoint(x: 11, y: 4.5), to: CGPoint(x: 37, y: 43.5))
    stroke(c, sheet, 0xA4A4A4, 0.6)
    let fold = poly([(37, 36), (30, 43.5), (30.5, 36.5)])
    linear(c, fold, [(0, 0xFFFFFF), (1, 0xC4C4C4)], from: CGPoint(x: 30, y: 36), to: CGPoint(x: 37, y: 43))
    stroke(c, fold, 0x9A9A9A, 0.5)
}
/// A small AmigaOS window: the blue bar with its gadgets, the body below (the base of Shell and Tool).
func miniWindow(_ c: CGContext, body bodyStops: [(CGFloat, UInt32)], title: String?) {
    let frame = rrect(5.5, 7, 37, 35, 1.5)
    fill(c, frame, 0x6A8CCB)
    let bar = CGPath(rect: CGRect(x: 6, y: 7.5, width: 36, height: 7), transform: nil)
    linear(c, bar, [(0, 0x5179BA), (1, 0xA9C6EC)], from: CGPoint(x: 0, y: 7.5), to: CGPoint(x: 0, y: 14.5))
    let closer = CGPath(rect: CGRect(x: 8, y: 9.4, width: 3.2, height: 3.2), transform: nil)
    fill(c, closer, 0xE6EEF0); stroke(c, closer, 0x2C3540, 0.5)
    stroke(c, CGPath(rect: CGRect(x: 35, y: 9, width: 3, height: 3), transform: nil), 0x2C3540, 0.5)
    let depthFront = CGPath(rect: CGRect(x: 36.6, y: 10.4, width: 3, height: 3), transform: nil)
    fill(c, depthFront, 0xE6EEF0); stroke(c, depthFront, 0x2C3540, 0.5)
    if let title {
        c.saveGState(); c.translateBy(x: 13, y: 13.3)
        fill(c, text(title, font: "DejaVuSans-Bold", size: 5.3), 0x101010)
        c.restoreGState()
    }
    let body = CGPath(rect: CGRect(x: 7.5, y: 15.5, width: 33, height: 25), transform: nil)
    linear(c, body, bodyStops, from: CGPoint(x: 0, y: 15.5), to: CGPoint(x: 0, y: 40.5))
    stroke(c, body, 0x2A3A6A, 0.5)
    stroke(c, frame, 0x1A244D, 0.7)
}
/// The Shell as the 2008 AmiDock shows it: a small window, pale grey inside, the prompt "OS4:>"
/// and a red cursor block (the TAWS set's pink one is a later look).
func shell(_ c: CGContext) {
    miniWindow(c, body: [(0, 0xEEF1F5), (1, 0xC4CCD8)], title: nil)
    c.saveGState(); c.translateBy(x: 9.5, y: 23)
    fill(c, text("OS4:>", font: "DejaVuSans-Bold", size: 6.2), 0x5A5E66)
    c.restoreGState()
    fill(c, CGPath(rect: CGRect(x: 29.6, y: 17.8, width: 3, height: 5.2), transform: nil), 0xE04A44)
    stroke(c, CGPath(rect: CGRect(x: 29.6, y: 17.8, width: 3, height: 5.2), transform: nil), 0x8A1A16, 0.4)
}
func tool(_ c: CGContext) {
    miniWindow(c, body: [(0, 0xF2F2F2), (1, 0xCFCFCF)], title: nil)
    // A cog in the window: the program as such.
    let cog = CGMutablePath()
    let cx: CGFloat = 24, cy: CGFloat = 28
    for k in 0..<16 {
        let a = CGFloat(k) * .pi / 8, r: CGFloat = k % 2 == 0 ? 8.2 : 6.4
        let a2 = a + .pi / 8
        let p1 = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)), p2 = CGPoint(x: cx + r * cos(a2), y: cy + r * sin(a2))
        if k == 0 { cog.move(to: p1) } else { cog.addLine(to: p1) }
        cog.addLine(to: p2)
    }
    cog.closeSubpath()
    cog.addEllipse(in: CGRect(x: cx - 2.6, y: cy - 2.6, width: 5.2, height: 5.2))
    c.saveGState(); c.addPath(cog); c.clip(using: .evenOdd)
    c.drawLinearGradient(CGGradient(colorsSpace: srgb, colors: [color(0xC4CBDA), color(0x5A6684)] as CFArray, locations: [0, 1])!,
                         start: CGPoint(x: 0, y: 19), end: CGPoint(x: 0, y: 37), options: [])
    c.restoreGState()
    stroke(c, cog, 0x2C3448, 0.5)
}
/// MultiView on the AmiDock: a magnifier with a clear glass and a dark rim, the brown handle.
func multiview(_ c: CGContext) { magnifier(c, at: CGPoint(x: 19, y: 19), radius: 14.5) }

func magnifier(_ c: CGContext, at o: CGPoint, radius R: CGFloat) {
    let k = R / 14.5
    c.saveGState(); c.translateBy(x: o.x + 12 * k, y: o.y + 12 * k); c.rotate(by: .pi / 4)
    let handle = rrect(0, -2.8 * k, 17 * k, 5.6 * k, 2.8 * k)
    linear(c, handle, [(0, 0xE0A060), (0.5, 0xA0581A), (1, 0x5A2C06)], from: CGPoint(x: 0, y: -2.8 * k), to: CGPoint(x: 0, y: 2.8 * k))
    stroke(c, handle, 0x3A1A04, 0.5)
    c.restoreGState()
    let rim = CGPath(ellipseIn: CGRect(x: o.x - R, y: o.y - R, width: 2 * R, height: 2 * R), transform: nil)
    linear(c, rim, [(0, 0x4A4A4A), (1, 0x0C0C0C)], from: CGPoint(x: o.x - R, y: o.y - R), to: CGPoint(x: o.x + R, y: o.y + R))
    let g = R - 2.6 * k
    let glass = CGPath(ellipseIn: CGRect(x: o.x - g, y: o.y - g, width: 2 * g, height: 2 * g), transform: nil)
    radial(c, clip: glass, center: CGPoint(x: o.x - 4 * k, y: o.y - 5 * k), radius: 2 * g,
           [(0, 0xFFFFFF, 0.95), (0.5, 0xE6E6E8, 0.85), (1, 0xA4A6AC, 0.85)])
    let shine = CGMutablePath(); shine.addArc(center: o, radius: g - 2.5 * k, startAngle: .pi * 1.05, endAngle: .pi * 1.5, clockwise: false)
    stroke(c, shine, 0xFFFFFF, 1.4 * k, alpha: 0.9)
}

func notepad(_ c: CGContext) {
    let pad = rrect(7, 9, 28, 34, 1.5)
    linear(c, pad, [(0, 0xA8DE8E), (1, 0x5AA43E)], from: CGPoint(x: 0, y: 9), to: CGPoint(x: 0, y: 43))
    stroke(c, pad, 0x2E5A1E, 0.6)
    let sheet = CGPath(rect: CGRect(x: 9.5, y: 13, width: 23, height: 27.5), transform: nil)
    linear(c, sheet, [(0, 0xFFFFFF), (1, 0xEAF2E4)], from: CGPoint(x: 0, y: 13), to: CGPoint(x: 0, y: 40.5))
    for k in 0..<6 { fill(c, CGPath(rect: CGRect(x: 11, y: 18 + CGFloat(k) * 3.7, width: 20, height: 0.5), transform: nil), 0x7AA0D8, alpha: 0.8) }
    for k in 0..<6 { fill(c, CGPath(ellipseIn: CGRect(x: 10 + CGFloat(k) * 4.2, y: 7.5, width: 2.4, height: 3.4), transform: nil), 0x5A5A5A) }
    // The pencil across the pad.
    c.saveGState(); c.translateBy(x: 40, y: 6); c.rotate(by: .pi * 0.68)
    let body = CGPath(rect: CGRect(x: 0, y: -2.2, width: 24, height: 4.4), transform: nil)
    linear(c, body, [(0, 0xFFD45A), (0.5, 0xF09A18), (1, 0xA85A06)], from: CGPoint(x: 0, y: -2.2), to: CGPoint(x: 0, y: 2.2))
    fill(c, poly([(24, -2.2), (29, 0), (24, 2.2)]), 0xF2D2A8); fill(c, poly([(27.4, -0.7), (29, 0), (27.4, 0.7)]), 0x303030)
    fill(c, CGPath(rect: CGRect(x: -2.6, y: -2.2, width: 2.6, height: 4.4), transform: nil), 0xE07070)
    stroke(c, body, 0x6A3A04, 0.4)
    c.restoreGState()
}
func unarc(_ c: CGContext) {
    // A carton, its flaps open.
    let front = poly([(9, 20), (33, 22), (33, 43), (9, 41)])
    linear(c, front, [(0, 0xD8A060), (1, 0x9A6020)], from: CGPoint(x: 0, y: 20), to: CGPoint(x: 0, y: 43))
    let side = poly([(33, 22), (41, 17), (41, 37), (33, 43)])
    linear(c, side, [(0, 0xB07A3A), (1, 0x7A4810)], from: CGPoint(x: 33, y: 0), to: CGPoint(x: 41, y: 0))
    let inside = poly([(9, 20), (17, 15), (41, 17), (33, 22)])
    fill(c, inside, 0x4A2A0A)
    let flapL = poly([(9, 20), (17, 15), (13, 6), (5, 11)])
    linear(c, flapL, [(0, 0xE6B47A), (1, 0xB47A3A)], from: CGPoint(x: 5, y: 6), to: CGPoint(x: 17, y: 20))
    let flapR = poly([(33, 22), (41, 17), (46, 25), (38, 30)])
    linear(c, flapR, [(0, 0xE6B47A), (1, 0xA06A2A)], from: CGPoint(x: 33, y: 17), to: CGPoint(x: 46, y: 30))
    fill(c, poly([(19, 21), (23, 21.3), (23, 42.3), (19, 42)]), 0xEAD8A8, alpha: 0.85)   // the tape
    for p in [front, side, flapL, flapR] { stroke(c, p, 0x4A2808, 0.55) }
    magnifier(c, at: CGPoint(x: 21, y: 25), radius: 10)   // Unarc looks into the archive
}

/// One icon in its two states. The selected one: darker, with the orange glow AmigaOS 4 puts
/// round a selected icon (the …Sel images of the default set).
func icon(_ name: String, _ paint: @escaping Painter) {
    let scale: CGFloat = 2
    let c = canvas(48, 48, scale: scale)
    withShadow(c, paint)
    let normal = c.makeImage()!
    write(normal, iconDir.appendingPathComponent("\(name).png"))

    let s = canvas(48, 48, scale: scale)
    // The glow: the icon's own outline, blurred orange.
    s.saveGState()
    s.setShadow(offset: .zero, blur: 3.2 * scale, color: color(0xFF9A10, 1))
    s.beginTransparencyLayer(auxiliaryInfo: nil)
    paint(s); paint(s)   // twice: one pass of the blur is too faint beside the Sel images
    s.endTransparencyLayer()
    s.restoreGState()
    s.saveGState()
    s.setShadow(offset: .zero, blur: 1.2 * scale, color: color(0xFFC040, 1))
    s.beginTransparencyLayer(auxiliaryInfo: nil)
    paint(s)
    // Darkened as the Sel images are: the face takes on shade, the shape stays.
    s.setBlendMode(.sourceAtop)
    s.setFillColor(color(0x0A1430, 0.42))
    s.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
    s.endTransparencyLayer()
    s.restoreGState()
    write(s.makeImage()!, iconDir.appendingPathComponent("\(name)-sel.png"))
}

// The fonts the icons letter with: DejaVu from the bundle, as the theme ships it.
for f in ["DejaVuSans.ttf", "DejaVuSans-Bold.ttf"] {
    CTFontManagerRegisterFontsForURL(bundle.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts/\(f)") as CFURL, .process, nil)
}

icon("harddrive", harddrive)
icon("harddrive-system", systemDrive)
icon("floppy", floppy)
icon("ramdisk", ramChip)
icon("drawer", drawer)
icon("drawer-prefs", drawerWith(prefsEmblem))
icon("drawer-utilities", drawerWith(utilitiesEmblem))
icon("drawer-system", drawerWith(ballEmblem))
icon("drawer-fonts", drawerWith(fontEmblem))
icon("trashcan", trashcan)
icon("project", project)
icon("tool", tool)
icon("shell", shell)
icon("multiview", multiview)
icon("notepad", notepad)
icon("unarc", unarc)

// MARK: - Clouds

/// Value noise, smoothed, in octaves: the cloud cover of the backdrop. A fixed seed.
struct Noise {
    var perm: [Int]
    init(seed: UInt64) {
        var s = seed
        perm = Array(0..<256)
        for i in stride(from: 255, to: 0, by: -1) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            perm.swapAt(i, Int((s >> 33) % UInt64(i + 1)))
        }
        perm += perm
    }
    func v(_ x: Int, _ y: Int) -> Double { Double(perm[(perm[x & 255] + y) & 511]) / 255 }
    func smooth(_ x: Double, _ y: Double) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = v(xi, yi), b = v(xi + 1, yi), c = v(xi, yi + 1), d = v(xi + 1, yi + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }
    func fbm(_ x: Double, _ y: Double, octaves: Int = 7) -> Double {
        var t = 0.0, amp = 0.5, f = 1.0
        for _ in 0..<octaves { t += amp * smooth(x * f, y * f); f *= 2.03; amp *= 0.5 }
        return t
    }
}

/// The sky with clouds as RGBA, `mix` choosing the light: the 2008 backdrop's grey-blue haze.
func clouds(_ W: Int, _ H: Int, seed: UInt64, sky: (UInt32, UInt32, UInt32), density: (Double) -> Double) -> [UInt8] {
    let n = Noise(seed: seed)
    var px = [UInt8](repeating: 255, count: W * H * 4)
    func comp(_ v: UInt32, _ s: UInt32) -> Double { Double(v >> s & 255) }
    let scale = 5.2 / Double(W)
    for y in 0..<H {
        let fy = Double(y) / Double(H)
        // Sky: darker at the top, lighter towards the horizon.
        let top = sky.0, mid = sky.1, bot = sky.2
        let (a, b, t) = fy < 0.55 ? (top, mid, fy / 0.55) : (mid, bot, (fy - 0.55) / 0.45)
        let sr = comp(a, 16) + (comp(b, 16) - comp(a, 16)) * t
        let sg = comp(a, 8) + (comp(b, 8) - comp(a, 8)) * t
        let sb = comp(a, 0) + (comp(b, 0) - comp(a, 0)) * t
        let dens = density(fy)
        for x in 0..<W {
            let fx = Double(x) * scale, fyy = Double(y) * scale * 1.6
            // Warped fbm: soft, billowing cover rather than fog.
            let w = n.fbm(fx * 0.5 + 13.1, fyy * 0.5 + 7.7, octaves: 3)
            var c = n.fbm(fx + w * 1.6, fyy + w * 1.2)
            c = max(0, min(1, (c - (0.62 - 0.32 * dens)) * 2.6))
            let shade = 0.80 + 0.20 * n.fbm(fx * 2 + 40, fyy * 2 + 40, octaves: 4)
            let cr = 238 * shade, cg = 242 * shade, cb = 246 * shade
            let i = (y * W + x) * 4
            px[i] = UInt8(min(255, sr + (cr - sr) * c)); px[i + 1] = UInt8(min(255, sg + (cg - sg) * c))
            px[i + 2] = UInt8(min(255, sb + (cb - sb) * c)); px[i + 3] = 255
        }
    }
    return px
}
func image(_ px: inout [UInt8], _ W: Int, _ H: Int) -> CGImage {
    let c = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: srgb,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return c.makeImage()!
}

/// "AmigaOS" with its "4.1": set from system faces as outlines (Verdana Bold for the name,
/// Georgia Bold Italic for the version), then coloured and bevelled the way the 2008 logo is.
func logo(_ c: CGContext, at origin: CGPoint, height capH: CGFloat, name nameStops: [(CGFloat, UInt32)], edge: UInt32,
          version vStops: [(CGFloat, UInt32)]) {
    let size = capH / 0.727
    let name = text("AmigaOS", font: "Verdana-Bold", size: size)
    let ver = text("4.1", font: "Georgia-BoldItalic", size: size * 0.62)
    let nb = name.boundingBoxOfPath
    c.saveGState()
    c.translateBy(x: origin.x, y: origin.y)
    c.setShadow(offset: CGSize(width: size * 0.03, height: -size * 0.04), blur: size * 0.06, color: color(0, 0.55))
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    linear(c, name, nameStops, from: CGPoint(x: 0, y: -capH), to: .zero)
    stroke(c, name, edge, size * 0.012)
    c.translateBy(x: nb.maxX + size * 0.08, y: capH * 0.16)
    linear(c, ver, vStops, from: CGPoint(x: 0, y: -capH * 0.6), to: .zero)
    stroke(c, ver, edge, size * 0.01)
    c.endTransparencyLayer()
    c.restoreGState()
}

// MARK: - The backdrop: Workbench, 2008 (reconstruction)

do {
    // 16:10 master. Everything that must show sits inside the 4:3 middle (240 px in from each
    // side) and below the band a 16:9 screen crops from the top (90 px), so any monitor shape
    // filled from it keeps the whole logo and the ball, unstretched.
    let W = 2880, H = 1800
    var px = clouds(W, H, seed: 1985, sky: (0x4C7186, 0x6F93A6, 0xA9BCC6)) { fy in 0.35 + 0.65 * fy * fy }
    let sky = image(&px, W, H)
    let c = canvas(W, H, opaque: true)
    c.saveGState(); c.translateBy(x: 0, y: CGFloat(H)); c.scaleBy(x: 1, y: -1)
    c.draw(sky, in: CGRect(x: 0, y: 0, width: W, height: H)); c.restoreGState()
    // The ball, big and low, its lower half lost in cloud (WBPattern, Internet).
    let r: CGFloat = 560, center = CGPoint(x: 240 + 0.46 * 2400, y: 1700)
    c.saveGState(); c.setAlpha(0.92)
    c.draw(ball(diameter: Int(2 * r), tilt: -0.30, spin: 0.18), in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    c.restoreGState()
    // Cloud drifting back over the ball's lower part.
    var mist = clouds(W, H, seed: 2008, sky: (0xA9BCC6, 0xC4D2DA, 0xDCE4E8)) { fy in fy < 0.78 ? 0 : min(1, (fy - 0.78) * 4.5) }
    for i in stride(from: 0, to: mist.count, by: 4) {
        let y = (i / 4) / W
        let fy = Double(y) / Double(H)
        let a = fy < 0.8 ? 0 : min(1, (fy - 0.8) * 5) * 0.85
        let lum = (Double(mist[i]) + Double(mist[i + 1]) + Double(mist[i + 2])) / 3
        let alpha = a * max(0, min(1, (lum - 190) / 45))
        mist[i] = UInt8(Double(mist[i]) * alpha); mist[i + 1] = UInt8(Double(mist[i + 1]) * alpha)
        mist[i + 2] = UInt8(Double(mist[i + 2]) * alpha); mist[i + 3] = UInt8(alpha * 255)
    }
    let mistImg = image(&mist, W, H)
    c.saveGState(); c.translateBy(x: 0, y: CGFloat(H)); c.scaleBy(x: 1, y: -1)
    c.draw(mistImg, in: CGRect(x: 0, y: 0, width: W, height: H)); c.restoreGState()
    // The logo, top right inside the 4:3 area: deep red name, the version in a brighter red.
    let capH: CGFloat = 112
    let size = capH / 0.727
    let nameW = text("AmigaOS", font: "Verdana-Bold", size: size).boundingBoxOfPath.width
    let verW = text("4.1", font: "Georgia-BoldItalic", size: size * 0.62).boundingBoxOfPath.width
    let x = CGFloat(W - 240 - 70) - nameW - size * 0.10 - verW
    logo(c, at: CGPoint(x: x, y: 200 + capH), height: capH,
         name: [(0, 0xA42424), (0.55, 0x7A1212), (1, 0x3E0606)], edge: 0x2A0404,
         version: [(0, 0xE8404A), (1, 0x9A1018)])
    write(c.makeImage()!, bundle.appendingPathComponent("wallpaper-2008.jpg"), jpeg: true)
}

// MARK: - The boot splash (os41-boot.jpg)

do {
    let W = 2880, H = 1800
    let c = canvas(W, H, opaque: true)
    let all = CGPath(rect: CGRect(x: 0, y: 0, width: W, height: H), transform: nil)
    linear(c, all, [(0, 0xF4F6F9), (0.5, 0xFBFCFD), (1, 0xE8EDF3)], from: .zero, to: CGPoint(x: 0, y: H))
    // The soft swooshes behind the logo: wide ribbons of pale blue-grey sweeping across.
    func ribbon(_ y0: CGFloat, _ y1: CGFloat, _ bend: CGFloat, _ thick: CGFloat, _ col: UInt32, _ a: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -100, y: y0))
        p.addCurve(to: CGPoint(x: CGFloat(W) + 100, y: y1), control1: CGPoint(x: CGFloat(W) * 0.35, y: y0 - bend),
                   control2: CGPoint(x: CGFloat(W) * 0.65, y: y1 + bend))
        p.addLine(to: CGPoint(x: CGFloat(W) + 100, y: y1 + thick))
        p.addCurve(to: CGPoint(x: -100, y: y0 + thick * 0.6), control1: CGPoint(x: CGFloat(W) * 0.65, y: y1 + bend + thick),
                   control2: CGPoint(x: CGFloat(W) * 0.35, y: y0 - bend + thick * 0.6))
        p.closeSubpath()
        c.saveGState(); c.setShadow(offset: .zero, blur: 90, color: color(col, a))
        linear(c, p, [(0, col), (1, 0xFFFFFF)], from: CGPoint(x: 0, y: y0), to: CGPoint(x: 0, y: y0 + thick), alpha: a)
        c.restoreGState()
    }
    ribbon(380, 160, 120, 90, 0xB9C7D8, 0.32)
    ribbon(620, 520, -160, 150, 0xC9D5E3, 0.28)
    ribbon(1180, 980, 200, 120, 0xBFCCDC, 0.3)
    ribbon(1480, 1560, -140, 200, 0xD4DDE8, 0.28)
    // The logo in the middle, dark, its version red; the ball above "ga".
    let capH: CGFloat = 150, size = capH / 0.727
    let nameW = text("AmigaOS", font: "Verdana-Bold", size: size).boundingBoxOfPath.width
    let verW = text("4.1", font: "Georgia-BoldItalic", size: size * 0.62).boundingBoxOfPath.width
    let total = nameW + size * 0.10 + verW
    let x = (CGFloat(W) - total) / 2, base = CGFloat(H) / 2 + capH * 0.75
    logo(c, at: CGPoint(x: x, y: base), height: capH,
         name: [(0, 0x5A5A60), (0.5, 0x2A2A2E), (1, 0x0A0A0C)], edge: 0x000000,
         version: [(0, 0xE8404A), (1, 0x9A1018)])
    let d: CGFloat = 190
    c.saveGState(); c.setShadow(offset: CGSize(width: 8, height: -12), blur: 18, color: color(0, 0.35))
    c.draw(ball(diameter: Int(d) * 2, tilt: -0.3, spin: 0.2), in: CGRect(x: x + nameW * 0.40, y: base - capH - d - 40, width: d, height: d))
    c.restoreGState()
    write(c.makeImage()!, bundle.appendingPathComponent("boot-splash.jpg"), jpeg: true)
}
