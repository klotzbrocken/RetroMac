import XCTest
@testable import RetroMac

/// The Apple cover follows the menu bar of a full-screen Space the way macOS drives it: down at
/// the top edge, held while the pointer is over it or a menu is open, gone after.
final class AppleCoverFullScreenTests: XCTestCase {
    func reveal(_ was: Bool, _ y: CGFloat, menu: Bool = false) -> Bool {
        RainbowAppleController.barRevealed(was: was, pointerY: y, screenTop: 956, barHeight: 33, menuOpen: menu)
    }

    func testTopEdgeBringsTheBarDown() {
        XCTAssertTrue(reveal(false, 956))
        XCTAssertTrue(reveal(false, 955.5))
    }

    func testInsideTheBarAreaOnlyWhileAlreadyDown() {
        XCTAssertFalse(reveal(false, 940))
        XCTAssertTrue(reveal(true, 940))
        XCTAssertTrue(reveal(true, 923))
    }

    func testLeavingTheBarHidesItUnlessAMenuIsOpen() {
        XCTAssertFalse(reveal(true, 600))
        XCTAssertTrue(reveal(true, 600, menu: true))
        XCTAssertFalse(reveal(false, 600, menu: true))
    }

    func testPointerOnAnotherScreen() {
        XCTAssertFalse(reveal(false, -.greatestFiniteMagnitude))
    }
}
