import XCTest
@testable import RetroMac

final class Win7AeroTests: XCTestCase {
    // A 1440×900 screen with the menu bar (25) on top, in Accessibility coordinates (y down),
    // and a 40-point taskbar along the bottom.
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let bar = CGRect(x: 0, y: 860, width: 1440, height: 40)

    func testWorkAreaLeavesOutTheBarOnItsSide() {
        XCTAssertEqual(WorkArea.usable(visible: visible, bar: bar), CGRect(x: 0, y: 25, width: 1440, height: 835))
        let left = CGRect(x: 0, y: 25, width: 70, height: 875)
        XCTAssertEqual(WorkArea.usable(visible: visible, bar: left), CGRect(x: 70, y: 25, width: 1370, height: 875))
    }

    func testAWindowUnderTheBarMovesUpAndATallOneShrinks() {
        // Fits: moved up just clear of the bar, same size.
        XCTAssertEqual(WorkArea.adjusted(frame: CGRect(x: 100, y: 500, width: 600, height: 400), visible: visible, bar: bar),
                       CGRect(x: 100, y: 460, width: 600, height: 400))
        // Too tall: the work area's height.
        XCTAssertEqual(WorkArea.adjusted(frame: CGRect(x: 100, y: 25, width: 600, height: 875), visible: visible, bar: bar),
                       CGRect(x: 100, y: 25, width: 600, height: 835))
        // Clear of the bar already: left alone.
        XCTAssertNil(WorkArea.adjusted(frame: CGRect(x: 100, y: 100, width: 600, height: 400), visible: visible, bar: bar))
    }

    func testSnapTargets() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let area = WorkArea.usable(visible: visible, bar: bar)
        XCTAssertEqual(SnapGeometry.target(cursor: CGPoint(x: 0, y: 400), screen: screen, workArea: area),
                       CGRect(x: 0, y: 25, width: 720, height: 835))
        XCTAssertEqual(SnapGeometry.target(cursor: CGPoint(x: 1439, y: 400), screen: screen, workArea: area),
                       CGRect(x: 720, y: 25, width: 720, height: 835))
        XCTAssertEqual(SnapGeometry.target(cursor: CGPoint(x: 700, y: 10), screen: screen, workArea: area), area)
        XCTAssertNil(SnapGeometry.target(cursor: CGPoint(x: 700, y: 400), screen: screen, workArea: area))
    }

    func testShakeFiresOnceForAQuickShakeOnly() {
        var shake = ShakeDetector(startX: 500)
        var fired = 0
        let xs: [CGFloat] = [500, 560, 500, 440, 500, 560, 500, 440, 500, 560]
        for (i, x) in xs.enumerated() where shake.add(x: x, time: Double(i) * 0.05) { fired += 1 }
        XCTAssertEqual(fired, 1)

        // The same moves spread over seconds are a slow drag, not a shake.
        var slow = ShakeDetector(startX: 500)
        XCTAssertFalse(xs.enumerated().contains { slow.add(x: $1, time: Double($0) * 0.5) })

        // A drag across the screen is never a shake.
        var drag = ShakeDetector(startX: 500)
        XCTAssertFalse([560, 620, 700, 650, 600].contains { drag.add(x: $0, time: 0.1) })
    }
}
