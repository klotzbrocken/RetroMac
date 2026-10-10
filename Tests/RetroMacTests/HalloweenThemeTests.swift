import XCTest
@testable import RetroMac

/// The Halloween theme: a grimy glass dock with a glowing ember rim, the pumpkin
/// for the Apple. With RETROMAC_SNAPSHOT_DIR set the dock is drawn to halloween-dock.png.
final class HalloweenThemeTests: XCTestCase {
    private func theme() throws -> ThemeBundle {
        try ThemeBundle(url: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Themes/Halloween.retromactheme"), isBuiltIn: true)
    }

    func testTheManifest() throws {
        let c = try theme().config
        XCTAssertEqual(c.dock.borderStyle, "ember")
        XCTAssertEqual(c.dock.dirtyGlass, true)
        XCTAssertEqual(c.menuBarAppleStyleDefault, 7)
        XCTAssertEqual(c.appearance, "dark")
        // A desktop of RetroMac's own, so a right-click reaches its wallpaper menu; the user's
        // Desktop folder stays one double-click away while the Finder's icons are hidden.
        XCTAssertEqual(c.desktopIcons?.map(\.path), ["/", "~/Desktop"])
    }

    /// macOS 26+ answers with the current icon style (read only); the theme asks for tinted.
    func testTheIconStyleCanBeRead() throws {
        XCTAssertEqual(try theme().config.iconStyle, "tinted")
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { return }
        XCTAssertNotNil(IconStyle.current())
        XCTAssertEqual(IconStyle.Value([8, 0, 1]), IconStyle.tinted)
    }

    func testThePumpkinIsTheSystemEmojiTrimmed() {
        let p = RainbowAppleController.pumpkin()
        XCTAssertGreaterThan(p.size.width, 50)
        XCTAssertEqual(p.size.width / p.size.height, 1, accuracy: 0.25)
    }

    private final class Backdrop: NSView {
        let wallpaper: NSImage?, path: NSBezierPath, color: NSColor
        init(frame: NSRect, wallpaper: NSImage?, path: NSBezierPath, color: NSColor) {
            self.wallpaper = wallpaper; self.path = path; self.color = color; super.init(frame: frame); wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError() }
        override func draw(_ dirtyRect: NSRect) {
            wallpaper?.draw(in: bounds, from: NSRect(x: 0, y: 0, width: wallpaper!.size.width, height: wallpaper!.size.width * bounds.height / bounds.width), operation: .copy, fraction: 1)
            color.setFill(); path.fill()
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            DockView.dirtImage.draw(in: path.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    @MainActor
    func testSnapshot() throws {
        let t = try theme()
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] else { return }
        let bar = NSRect(x: 60, y: 14, width: 600, height: 70)
        var icons = (0..<9).map { NSRect(x: 80 + CGFloat($0) * 62, y: 24, width: 50, height: 50) }
        for (i, size) in [(1, 56.0), (2, 68.0), (3, 80.0), (4, 68.0), (5, 56.0)] { icons[i].size = NSSize(width: size, height: size) }
        let shape = DockView.bulgePath(bar: bar, radius: 20, icons: icons)
        let view = Backdrop(frame: NSRect(x: 0, y: 0, width: 720, height: 200),
                            wallpaper: NSImage(contentsOf: t.url.appendingPathComponent("wallpaper.jpg")),
                            path: shape, color: NSColor.fromHex(t.config.dock.backgroundColor))
        let rim = EmberRim()
        view.layoutSubtreeIfNeeded(); view.display()
        rim.update(host: view.layer!, path: shape.cgPath, restBar: bar)
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

/// Where the hidden Mac Dock goes decides where windows minimise to.
final class RubberBandTests: XCTestCase {
    /// At rest the bar is the plain rounded bar; a magnified icon lifts the top edge over itself
    /// by what it grew, and the edge is back down well to either side.
    func testTheTopFollowsTheMagnifiedIcon() {
        let bar = NSRect(x: 0, y: 16, width: 400, height: 70)
        let rest = (0..<6).map { NSRect(x: 20 + CGFloat($0) * 60, y: 26, width: 50, height: 50) }
        XCTAssertEqual(DockView.bulgePath(bar: bar, radius: 20, icons: rest).bounds.maxY, bar.maxY, accuracy: 0.5)
        var magnified = rest
        magnified[2] = NSRect(x: 135, y: 26, width: 80, height: 80)   // grew by 30
        let path = DockView.bulgePath(bar: bar, radius: 20, icons: magnified)
        XCTAssertEqual(path.bounds.maxY, bar.maxY + 30, accuracy: 1)
        XCTAssertFalse(path.contains(NSPoint(x: 30, y: bar.maxY + 5)), "far from the icon the edge is down")
        XCTAssertTrue(path.contains(NSPoint(x: 175, y: bar.maxY + 25)), "over the icon it is up")
    }
}

final class SystemDockEdgeTests: XCTestCase {
    func testBesideALittleLowerIsNotBelow() {
        let monitor = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertFalse(DockController.isBelow(NSRect(x: -1280, y: -84, width: 1280, height: 832), primary: monitor))
        XCTAssertTrue(DockController.isBelow(NSRect(x: 200, y: -832, width: 1280, height: 832), primary: monitor))
    }
}

/// The rubber band is recomputed at every step of the magnification: it must stay cheap.
final class RubberBandContinuityTests: XCTestCase {
    /// The mouse sliding a few points must move the arch a few points, never a whole icon.
    func testTheArchMovesSmoothly() {
        let bar = NSRect(x: 0, y: 16, width: 900, height: 70)
        func icons(mouse: CGFloat) -> [NSRect] {
            (0..<14).map { i -> NSRect in
                let x = 20 + CGFloat(i) * 62 + 25
                let t = max(0, 1 - abs(x - mouse) / 150)
                let size = 50 * (1 + 0.6 * t * t * (3 - 2 * t))
                return NSRect(x: x - size / 2, y: 26, width: size, height: size)
            }
        }
        var last: NSRect?
        for mouse in stride(from: CGFloat(300), through: 420, by: 2) {
            let box = DockView.bulgePath(bar: bar, radius: 20, icons: icons(mouse: mouse)).bounds
            if let last { XCTAssertLessThan(abs(box.maxY - last.maxY), 3); XCTAssertLessThan(abs(box.midX - last.midX), 6) }
            last = box
        }
    }
}

final class RubberBandCostTests: XCTestCase {
    func testOneStepIsCheap() {
        let bar = NSRect(x: 75, y: 16, width: 900, height: 70)
        var icons = (0..<14).map { NSRect(x: 90 + CGFloat($0) * 62, y: 26, width: 50, height: 50) }
        for (i, s) in [(5, 58.0), (6, 70.0), (7, 80.0), (8, 70.0), (9, 58.0)] { icons[i].size = NSSize(width: s, height: s) }
        let start = CACurrentMediaTime()
        for _ in 0..<100 {
            let p = DockView.bulgePath(bar: bar, radius: 20, icons: icons).cgPath
            _ = p.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 2)
        }
        let perStep = (CACurrentMediaTime() - start) / 100
        print("[RubberBand] one step: \(String(format: "%.2f", perStep * 1000)) ms")
        XCTAssertLessThan(perStep, 0.004, "a step must leave the frame most of its 8–16 ms")
    }
}
