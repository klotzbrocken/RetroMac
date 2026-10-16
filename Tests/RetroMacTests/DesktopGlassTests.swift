import XCTest
@testable import RetroMac

/// Desktop Glass films the rectangle under its window; a flipped or offset rectangle shows
/// the wrong part of the screen.
final class DesktopGlassTests: XCTestCase {
    func testMainDisplayFlipsToTopLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let glass = CGRect(x: 100, y: 600, width: 400, height: 300)   // top edge at 900
        XCTAssertEqual(DesktopGlassController.displayRect(glass, in: screen), CGRect(x: 100, y: 82, width: 400, height: 300))
    }

    func testSecondDisplayIsOwnOrigin() {
        let screen = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let glass = CGRect(x: 1612, y: 580, width: 200, height: 100)
        XCTAssertEqual(DesktopGlassController.displayRect(glass, in: screen), CGRect(x: 100, y: 200, width: 200, height: 100))
    }
}
