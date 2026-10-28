import AppKit
import XCTest
@testable import RetroMac

/// Draws every title bar style, front and behind, with the shipped drawing code, and checks each
/// picture has something in it. With RETROMAC_GALLERY=<folder> it also writes the pictures and a
/// gallery.html beside them (Scripts/render-gallery.sh); see docs/fidelity/README.md.
final class TitleBarGalleryTests: XCTestCase {

    func testEveryTitleBarDrawsAndTheGalleryIsWritten() throws {
        let out = ProcessInfo.processInfo.environment["RETROMAC_GALLERY"].map { URL(fileURLWithPath: $0) }
        if let out { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        var rows: [String] = []
        for style in TitleBarOverlayController.Style.allCases where style.isBar {
            var cells: [String] = []
            for front in [true, false] {
                let size = NSSize(width: 420, height: TitleBarOverlayController.stripHeight(style))
                let view = TitleBarOverlayView(frame: NSRect(origin: .zero, size: size))
                view.configure(style: style, title: "Untitled — TextEdit", icon: nil, isFront: front,
                               lights: [:], deadZoneWidth: 0, zoomed: false)
                let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: rep)
                XCTAssertGreaterThan(Self.distinctColours(rep), 1, "\(style) front=\(front) draws nothing")
                guard let out else { continue }
                let name = "titlebar-\(style)-\(front ? "front" : "behind").png"
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name))
                cells.append("<figure><img src=\"\(name)\" width=\"\(Int(size.width))\"><figcaption>\(front ? "front" : "behind")</figcaption></figure>")
            }
            rows.append("<section><h2>\(style)</h2>\(cells.joined())</section>")
        }
        guard let out else { return }
        let html = """
        <!doctype html><meta charset="utf-8"><title>RetroMac title bars</title>
        <style>body{font:13px -apple-system,sans-serif;background:#808080;color:#fff;margin:24px}
        section{margin-bottom:20px}h2{font-size:13px;margin:0 0 6px}figure{display:inline-block;margin:0 16px 0 0}
        img{image-rendering:pixelated;display:block}figcaption{font-size:11px;opacity:.8}</style>
        <h1>Title bars, as the shipped code draws them</h1>
        \(rows.joined(separator: "\n"))
        """
        try html.write(to: out.appendingPathComponent("gallery.html"), atomically: true, encoding: .utf8)
    }

    /// Up to a few distinct colours: a blank or single-colour picture has one.
    private static func distinctColours(_ rep: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                seen.insert(UInt32(c.redComponent * 255) << 24 | UInt32(c.greenComponent * 255) << 16
                            | UInt32(c.blueComponent * 255) << 8 | UInt32(c.alphaComponent * 255))
                if seen.count > 4 { return seen.count }
            }
        }
        return seen.count
    }
}
