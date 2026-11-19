import XCTest
@testable import RetroMac

final class AmigaChromeTests: XCTestCase {

    /// A window gets only the gadgets it has: no zoom gadget without a zoom button, and the
    /// right-hand ones run depth, zoom, iconify from the outside in, the closer alone on the left.
    func testGadgetsFollowTheWindowsAbilities() {
        let all = AmigaChrome.titleGadgets(width: 310, kinds: [.close, .iconify, .zoom, .depth])
        XCTAssertEqual(all.map(\.0), [.close, .depth, .zoom, .iconify])
        let close = all[0].1, depth = all[1].1, zoom = all[2].1, iconify = all[3].1
        XCTAssertEqual(close.minX, 12)
        XCTAssertEqual(depth.maxX, 310 - 12, "12 pt in from the right edge, as on the reference")
        XCTAssertLessThan(zoom.maxX, depth.minX)
        XCTAssertLessThan(iconify.maxX, zoom.minX)
        for (_, r) in all { XCTAssertEqual(r.midY, AmigaChrome.barHeight / 2, accuracy: 1, "centred on the bar") }

        let requester = AmigaChrome.titleGadgets(width: 310, kinds: [.close, .depth])
        XCTAssertFalse(requester.contains { $0.0 == .zoom || $0.0 == .iconify })
        XCTAssertEqual(requester.first { $0.0 == .depth }?.1, depth, "depth keeps its place whatever else is there")
    }

    func testDepthSendsTheFrontWindowBackAndBringsAnyOtherForward() {
        XCTAssertTrue(AmigaChrome.depthSendsBack(isFrontmost: true))
        XCTAssertFalse(AmigaChrome.depthSendsBack(isFrontmost: false))
    }

    /// Sent to the back, a window lets every window it covers come up, in their own order;
    /// windows elsewhere on the screen are left alone.
    func testDepthRaisesWhatTheWindowCovers() {
        let front = CGRect(x: 100, y: 100, width: 400, height: 300)
        let below: [(Int, CGRect)] = [(2, CGRect(x: 0, y: 0, width: 1920, height: 1000)),
                                      (3, CGRect(x: 1200, y: 100, width: 300, height: 300)),
                                      (4, CGRect(x: 450, y: 350, width: 200, height: 200))]
        XCTAssertEqual(AmigaChrome.windowsToRaise(behind: front, below: below), [2, 4])
        XCTAssertEqual(AmigaChrome.windowsToRaise(behind: front, below: [(Int, CGRect)]()), [])
    }

    /// The bands are the reference's rows: 31 each, edge rows dark, the active bar blue.
    func testBandsAreTheMeasuredRows() {
        XCTAssertEqual(AmigaChrome.activeRows.count, 31)
        XCTAssertEqual(AmigaChrome.inactiveRows.count, 31)
        XCTAssertEqual(AmigaChrome.screenRows.count, 31)
        let c = AmigaChrome.activeRows[15].usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(c.blueComponent, c.redComponent + 0.2, "the active bar is blue")
        XCTAssertEqual(AmigaChrome.kind(.depth), .depth)
        XCTAssertEqual(AmigaChrome.kind(.iconify), .minimize)
    }
}
