import XCTest
@testable import RetroMac

/// Snow Leopard's dock reflections: they follow a magnified icon and fade out on the shelf
/// instead of being cut off by the screen edge ("the reflection of the icon is chopped").
final class DockReflectionTests: XCTestCase {
    private func item(in dock: NSView, at origin: NSPoint, size: CGFloat) throws -> DockItemView {
        let theme = try ThemeBundle(url: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Themes/MacOSX-SnowLeopard.retromactheme"), isBuiltIn: true).config
        let item = DockItemView(bundleID: "com.apple.finder", frame: NSRect(origin: origin, size: NSSize(width: size, height: size)))
        dock.addSubview(item)
        item.updateIcon(NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true })
        item.updateTheme(theme)
        return item
    }

    func testTheReflectionFollowsAMagnifiedIcon() throws {
        let dock = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let item = try item(in: dock, at: NSPoint(x: 100, y: 14), size: 52)
        // Magnification resizes the item from the same floor.
        item.frame = NSRect(x: 90, y: 14, width: 94, height: 94)
        let strip = try XCTUnwrap(item.reflectionLayer)
        XCTAssertEqual(strip.frame.width, 90, accuracy: 0.5)          // the icon's width, inset 2 on each side
        XCTAssertEqual(strip.frame.minX, 2, accuracy: 0.5)
        XCTAssertEqual(strip.frame.maxY, 2, accuracy: 0.5)            // right under the icon
        XCTAssertGreaterThanOrEqual(item.frame.minY + strip.frame.minY, -0.5)   // not below the dock
    }

    func testItFadesTowardsTheBottom() throws {
        let dock = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let strip = try XCTUnwrap(try item(in: dock, at: NSPoint(x: 100, y: 14), size: 52).reflectionLayer)
        let fade = try XCTUnwrap(strip.mask as? CAGradientLayer)
        XCTAssertGreaterThan(fade.startPoint.y, fade.endPoint.y)      // opaque (first colour) at the top on the Mac
    }
}
