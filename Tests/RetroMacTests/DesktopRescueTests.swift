import XCTest
@testable import RetroMac

/// Rescue Desktop (Lastenheft 3.0): which windows count as out of reach, and where they go.
/// Quartz coordinates: origin top-left of the main display, y downwards.
final class DesktopRescueTests: XCTestCase {
    typealias R = DesktopRescue
    let laptop = CGRect(x: 0, y: 25, width: 1470, height: 931)          // visible frame under the menu bar
    let leftOfIt = CGRect(x: -1920, y: 0, width: 1920, height: 1080)    // a display to the left: negative x

    func testAWindowOnScreenIsReachable() {
        XCTAssertTrue(R.titleBarReachable(CGRect(x: 300, y: 200, width: 600, height: 400), screens: [laptop]))
    }

    func testAParkedWindowIsNot() {
        // Where WindowShade parks a window on a single laptop display: one point in from the edge.
        XCTAssertFalse(R.titleBarReachable(CGRect(x: 1469, y: 904, width: 600, height: 400), screens: [laptop]))
    }

    func testATitleBarUnderTheMenuBarIsNot() {
        XCTAssertFalse(R.titleBarReachable(CGRect(x: 300, y: 0, width: 600, height: 400), screens: [laptop]))
    }

    func testHalfOffTheEdgeIsFineWhileEnoughOfTheBarShows() {
        XCTAssertTrue(R.titleBarReachable(CGRect(x: 1300, y: 200, width: 600, height: 400), screens: [laptop]))
        XCTAssertFalse(R.titleBarReachable(CGRect(x: 1400, y: 200, width: 600, height: 400), screens: [laptop]))
    }

    func testASmallWindowNeedsOnlyWhatItHas() {
        XCTAssertTrue(R.titleBarReachable(CGRect(x: 100, y: 100, width: 80, height: 20), screens: [laptop]))
    }

    func testASecondDisplayWithNegativeCoordinates() {
        let w = CGRect(x: -1000, y: 300, width: 800, height: 500)
        XCTAssertTrue(R.titleBarReachable(w, screens: [laptop, leftOfIt]))
        XCTAssertFalse(R.titleBarReachable(w, screens: [laptop]), "that display unplugged: out of reach")
    }

    func testABroughtBackWindowLandsWholeTitleBarOnTheNearestScreen() {
        let parked = CGRect(x: 1469, y: 904, width: 600, height: 400)
        let o = R.rescueOrigin(for: parked, screens: [laptop, leftOfIt])
        XCTAssertTrue(R.titleBarReachable(CGRect(origin: o, size: parked.size), screens: [laptop]))
        XCTAssertEqual(o, CGPoint(x: 870, y: 904), "size kept, moved just far enough in")
    }

    func testAWindowLeftOnAnUnpluggedDisplayComesToTheNearestOne() {
        let lost = CGRect(x: -1500, y: 200, width: 800, height: 500)
        let o = R.rescueOrigin(for: lost, screens: [laptop])
        XCTAssertEqual(o.x, 0)
        XCTAssertTrue(R.titleBarReachable(CGRect(origin: o, size: lost.size), screens: [laptop]))
    }

    func testABarAboveTheScreenComesDownBelowTheMenuBar() {
        let o = R.rescueOrigin(for: CGRect(x: 300, y: -200, width: 600, height: 400), screens: [laptop])
        XCTAssertEqual(o, CGPoint(x: 300, y: 25))
    }

    func testTheReportLine() {
        XCTAssertEqual(R.sweepLine(.init()).status, .done)
        XCTAssertEqual(R.sweepLine(.init(moved: 2, failed: 0)).status, .done)
        XCTAssertEqual(R.sweepLine(.init(moved: 1, failed: 1)).status, .failed, "a window that did not answer is no success")
    }
}
