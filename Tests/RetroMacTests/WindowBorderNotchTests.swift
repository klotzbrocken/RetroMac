import XCTest
import AppKit
@testable import RetroMac

/// With square corners requested, the frame paints the sliver macOS leaves in every rounded
/// corner, in all four corners, not just the ones a particular coordinate system favours.
final class WindowBorderNotchTests: XCTestCase {
    func testAllFourCornerNotchesAreFilled() {
        let size = CGSize(width: 200, height: 120)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let blue = NSColor.fromHex("#2A63D8")
        WindowBorderController.drawBorder(.solid(color: blue, width: 4, topRadius: 0, bottomRadius: 0), into: ctx, size: size)
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[y * ctx.bytesPerRow + x * 4 + 3] }
        // One point inside each inner corner, just inside the 4pt ring: outside the 12pt arc,
        // so it must be painted. And the window's middle must stay clear.
        for (x, y) in [(5, 5), (194, 5), (5, 114), (194, 114)] {
            XCTAssertGreaterThan(alpha(x, y), 200, "corner notch at \(x),\(y) is not painted")
        }
        XCTAssertEqual(alpha(100, 60), 0, "the window's middle must stay clear")
        XCTAssertEqual(alpha(30, 60), 0, "the edge beyond the notch must stay clear")
    }
}
