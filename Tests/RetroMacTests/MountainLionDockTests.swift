import XCTest
@testable import RetroMac

/// Mountain Lion's dock: a frosted shelf with a lit front edge and running lights set into it.
/// With RETROMAC_SNAPSHOT_DIR set it is drawn to mountain-lion-dock.png.
final class MountainLionDockTests: XCTestCase {
    private final class Shelf: NSView {
        override func draw(_ dirtyRect: NSRect) {
            DockView.drawFrostedShelf(NSRect(x: 8, y: 0, width: bounds.width - 16, height: 78 * 0.55), alpha: 1)
        }
    }

    @MainActor
    func testRunningLightsSitOnTheFrontEdge() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Themes/MacOSX-Aqua.retromactheme")
        let theme = try ThemeBundle(url: url, isBuiltIn: true)
        XCTAssertTrue(theme.config.hasFrostedShelf)
        XCTAssertEqual(theme.config.indicator.style, "lightbar")

        let backdrop = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 120))
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor(srgbRed: 0.25, green: 0.33, blue: 0.48, alpha: 1).cgColor
        let shelf = Shelf(frame: backdrop.bounds); backdrop.addSubview(shelf)
        let dock = DockView(frame: backdrop.bounds); backdrop.addSubview(dock)
        var lights: [CALayer] = []
        for (i, id) in ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.Notes", "com.apple.systempreferences"].enumerated() {
            let item = DockItemView(bundleID: id, frame: NSRect(x: 30 + CGFloat(i) * 60, y: 78 * 0.55 - 26, width: 52, height: 52))
            dock.addSubview(item)
            if let u = theme.iconURL(for: id), let img = NSImage(contentsOf: u) { item.updateIcon(img) }
            item.updateTheme(theme.config)
            if i % 2 == 0 {
                item.setRunningIndicator(visible: true, theme: theme.config)
                let light = try XCTUnwrap(item.layer?.sublayers?.last)
                let midY = item.frame.minY + light.frame.midY
                XCTAssertEqual(midY, DockView.frostedFrontHeight / 2, accuracy: 0.5)   // on the front face
                lights.append(light)
            }
            // The reflection ends on the glass, above the front face.
            let strip = try XCTUnwrap(item.reflectionLayer)
            XCTAssertGreaterThanOrEqual(item.frame.minY + strip.frame.minY, DockView.frostedFrontHeight - 0.5)
        }
        XCTAssertEqual(lights.count, 3)

        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"],
              let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { return }
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("mountain-lion-dock.png"))
    }
}
