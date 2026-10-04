import XCTest
import CoreGraphics
@testable import RetroMac

/// Where a rolled-up window is parked, and the record that brings it back after a crash.
final class WindowShadeTests: XCTestCase {

    private typealias C = TitleBarOverlayController
    private let window = CGSize(width: 800, height: 600)
    private let main = CGRect(x: 0, y: 0, width: 1470, height: 956)

    private func hidden(_ screens: [CGRect]) -> Bool {
        let spot = C.parkingSpot(for: window, screens: screens)
        return C.visibleArea(CGRect(origin: spot, size: window), screens: screens) <= 1
    }

    func testOneScreen() { XCTAssertTrue(hidden([main])) }

    func testADisplayBelowTheMainOne() {
        // Maik's desk: a second display under the main one — the main display's bottom corners
        // would put the window straight onto it.
        XCTAssertTrue(hidden([main, CGRect(x: 0, y: 956, width: 1920, height: 1080)]))
    }

    func testADisplayToTheRight() {
        XCTAssertTrue(hidden([main, CGRect(x: 1470, y: 0, width: 1920, height: 1080)]))
    }

    func testADisplayToTheLeftAndOneBelow() {
        XCTAssertTrue(hidden([main, CGRect(x: -1280, y: 0, width: 1280, height: 832), CGRect(x: 0, y: 956, width: 1920, height: 1080)]))
    }

    func testAWindowStillOnScreenIsNotParked() {
        XCTAssertFalse(C.isOutOfSight(CGRect(x: 100, y: 100, width: 800, height: 600), screens: [main]))
        XCTAssertFalse(C.isOutOfSight(CGRect(x: CGFloat.nan, y: 0, width: 800, height: 600), screens: [main]), "no position read back")
        XCTAssertTrue(C.isOutOfSight(CGRect(x: main.maxX - 1, y: main.maxY - 1, width: 800, height: 600), screens: [main]))
        // Measured on a MacBook: the window was parked one point in from the right, but macOS
        // kept 52 points of its height on screen.
        XCTAssertTrue(C.isOutOfSight(CGRect(x: main.maxX - 1, y: main.maxY - 52, width: 600, height: 400), screens: [main]))
        XCTAssertFalse(C.isOutOfSight(CGRect(x: main.maxX - 40, y: main.maxY - 52, width: 600, height: 400), screens: [main]))
    }

    func testTheRecoveryRecordSurvivesARoundTrip() throws {
        let record = C.ShadeRecord(frame: CGRect(x: 120, y: 80, width: 800, height: 600), pid: 4242, bundleID: "com.apple.TextEdit")
        let data = try JSONEncoder().encode(["1234": record])
        XCTAssertEqual(C.decodeShadeRecovery(data), [1234: record])
        XCTAssertTrue(C.decodeShadeRecovery(Data("junk".utf8)).isEmpty)
    }

    /// Putting windows back: only a window that still exists and would not move keeps its record.
    func testOnlyWindowsThatWouldNotMoveStayOnRecord() {
        let r = C.ShadeRecord(frame: CGRect(x: 10, y: 20, width: 300, height: 200), pid: 1, bundleID: "x")
        let left = C.remainingShadeRecords([(1, r, .restored), (2, r, .gone), (3, r, .failed)])
        XCTAssertEqual(Array(left.keys), [3])
    }
}
