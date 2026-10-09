import XCTest
@testable import RetroMac

/// VoiceOver finds its place among a view's children by identity: the same control must be
/// the same element at every question, or VoiceOver stops after the second one.
final class AccessibleHotspotTests: XCTestCase {
    @MainActor
    func testTheSameControlIsTheSameElement() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let r = NSRect(x: 30, y: 0, width: 20, height: 24)
        let a = AccessibleHotspot.make(in: view, label: "Clock, 16:52", rect: r) {}
        let b = AccessibleHotspot.make(in: view, label: "Clock, 16:53", rect: r) {}
        XCTAssertTrue(a === b)
        XCTAssertEqual(b.accessibilityLabel(), "Clock, 16:53")
        let other = AccessibleHotspot.make(in: view, label: "Clock, 16:53", rect: r.offsetBy(dx: 40, dy: 0)) {}
        XCTAssertFalse(a === other, "two of the same name in a row stay two")
    }
}
