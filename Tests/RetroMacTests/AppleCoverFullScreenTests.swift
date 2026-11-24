import XCTest
@testable import RetroMac

/// The Apple cover follows the menu bar in a full-screen Space: up when the bar is down, gone
/// while it is pushed above the display.
final class AppleCoverFullScreenTests: XCTestCase {
    let display = CGRect(x: 0, y: 0, width: 1470, height: 956)

    func testBarDownOnThisDisplay() {
        XCTAssertTrue(RainbowAppleController.barIsDown([CGRect(x: 0, y: 0, width: 1470, height: 33)], displayTop: display))
    }

    func testBarPushedAboveOrMissing() {
        XCTAssertFalse(RainbowAppleController.barIsDown([CGRect(x: 0, y: -33, width: 1470, height: 33)], displayTop: display))
        XCTAssertFalse(RainbowAppleController.barIsDown([CGRect(x: 0, y: -12, width: 1470, height: 33)], displayTop: display))
        XCTAssertFalse(RainbowAppleController.barIsDown([], displayTop: display))
    }

    func testBarOnAnotherDisplayDoesNotCount() {
        let right = CGRect(x: 1470, y: 0, width: 1920, height: 1080)
        XCTAssertFalse(RainbowAppleController.barIsDown([CGRect(x: 0, y: 0, width: 1470, height: 33)], displayTop: right))
        XCTAssertTrue(RainbowAppleController.barIsDown([CGRect(x: 1470, y: 0, width: 1920, height: 25)], displayTop: right))
    }
}
