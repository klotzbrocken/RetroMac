// Builds the Windows NT Workstation 4.0 wallpaper: the NT splash artwork (a modern redraw)
// with its three typing errors set right, centred at 48 % width on RetroMac's teal #058182.
// swift Scripts/nt-wallpaper.swift <artwork 3840x2160 png> <out png>
import AppKit

let a = CommandLine.arguments
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!
let W = src.pixelsWide, H = src.pixelsHigh
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
src.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()

/// Clears a band of text: every column blends from the pixel above the band to the one below,
/// which keeps the sky's gradient and the starfield's dark.
func erase(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {          // top-left coordinates
    for x in x0...x1 {
        var top = [Int](repeating: 0, count: 4), bottom = top
        rep.getPixel(&top, atX: x, y: y0 - 1); rep.getPixel(&bottom, atX: x, y: y1 + 1)
        for y in y0...y1 {
            let f = Double(y - y0) / Double(y1 - y0)
            var p = (0..<4).map { Int(Double(top[$0]) * (1 - f) + Double(bottom[$0]) * f) }
            rep.setPixel(&p, atX: x, y: y)
        }
    }
}
/// Sets a line of Arial between two x positions, on a baseline (top-left coordinates).
func line(_ text: String, left: CGFloat, right: CGFloat, baseline: CGFloat, color: NSColor) {
    let probe = NSAttributedString(string: text, attributes: [.font: NSFont(name: "ArialMT", size: 100)!])
    let size = 100 * (right - left) / probe.size().width
    let s = NSAttributedString(string: text, attributes: [.font: NSFont(name: "ArialMT", size: size)!, .foregroundColor: color])
    let font = NSFont(name: "ArialMT", size: size)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    s.draw(at: NSPoint(x: left, y: CGFloat(H) - baseline + font.descender))
    NSGraphicsContext.restoreGraphicsState()
}

let grey = NSColor(white: 0.80, alpha: 1)
erase(3190, 203, 3705, 320)
line("Copyright \u{00A9} 1985-1996", left: 3200, right: 3695, baseline: 255, color: grey)
line("Microsoft Corporation", left: 3261, right: 3687, baseline: 302, color: grey)
erase(515, 1995, 3300, 2075)
line("This product is protected by US and international copyright laws as described in the About Box.",
     left: 528, right: 3277, baseline: 2055, color: .black)

// The wallpaper: 16:10, the artwork 48 % wide, centred, never stretched. Drawn in sRGB at 8 bits
// so the teal is exactly #058182 (AppKit's own canvas would be Display P3 at 2x).
let outW = 3200, outH = 2000
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(colorSpace: srgb, components: [5 / 255, 129 / 255, 130 / 255, 1])!)
ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
let w = CGFloat(outW) * 0.48, h = w * CGFloat(H) / CGFloat(W)
ctx.interpolationQuality = .high
ctx.draw(rep.cgImage!, in: CGRect(x: (CGFloat(outW) - w) / 2, y: (CGFloat(outH) - h) / 2, width: w, height: h))
let bmp = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: URL(fileURLWithPath: a[2]))
if a.count > 3 { try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3])) }   // the fixed artwork, for checking
