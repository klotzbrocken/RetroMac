import XCTest
@testable import RetroMac

/// The Halloween theme: a glass dock with a few cracks and a glowing ember rim, the pumpkin
/// for the Apple. With RETROMAC_SNAPSHOT_DIR set the dock is drawn to halloween-dock.png.
final class HalloweenThemeTests: XCTestCase {
    private func theme() throws -> ThemeBundle {
        try ThemeBundle(url: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Themes/Halloween.retromactheme"), isBuiltIn: true)
    }

    func testTheManifest() throws {
        let c = try theme().config
        XCTAssertEqual(c.dock.borderStyle, "ember")
        XCTAssertEqual(c.dock.glassCracks, true)
        XCTAssertEqual(c.menuBarAppleStyleDefault, 7)
        XCTAssertEqual(c.appearance, "dark")
    }

    func testThePumpkinIsTheSystemEmojiTrimmed() {
        let p = RainbowAppleController.pumpkin()
        XCTAssertGreaterThan(p.size.width, 50)
        XCTAssertEqual(p.size.width / p.size.height, 1, accuracy: 0.25)
    }

    private final class Backdrop: NSView {
        let wallpaper: NSImage?, bar: NSRect, color: NSColor
        init(frame: NSRect, wallpaper: NSImage?, bar: NSRect, color: NSColor) {
            self.wallpaper = wallpaper; self.bar = bar; self.color = color; super.init(frame: frame); wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError() }
        override func draw(_ dirtyRect: NSRect) {
            wallpaper?.draw(in: bounds, from: NSRect(x: 0, y: 0, width: wallpaper!.size.width, height: wallpaper!.size.width * bounds.height / bounds.width), operation: .copy, fraction: 1)
            let path = NSBezierPath(roundedRect: bar, xRadius: 20, yRadius: 20)
            color.setFill(); path.fill()
            DockView.drawGlassCracks(in: bar, clip: path, alpha: 1)
        }
    }

    @MainActor
    func testSnapshot() throws {
        let t = try theme()
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] else { return }
        let bar = NSRect(x: 60, y: 14, width: 600, height: 70)
        let view = Backdrop(frame: NSRect(x: 0, y: 0, width: 720, height: 200),
                            wallpaper: NSImage(contentsOf: t.url.appendingPathComponent("wallpaper.jpg")),
                            bar: bar, color: NSColor.fromHex(t.config.dock.backgroundColor))
        let rim = EmberRim()
        view.layoutSubtreeIfNeeded(); view.display()
        rim.update(host: view.layer!, barRect: bar, cornerRadius: 20)
        let scale: CGFloat = 2
        let w = Int(view.bounds.width * scale), h = Int(view.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        view.layer!.render(in: ctx)
        if let cg = ctx.makeImage() { try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("halloween-dock.png")) }
    }
}
