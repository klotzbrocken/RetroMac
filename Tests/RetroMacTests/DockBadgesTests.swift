import XCTest
@testable import RetroMac

/// Badges only where the theme's system had them: a count on a Windows 95 taskbar or a NeXT
/// dock would be invented history.
final class DockBadgesTests: XCTestCase {
    func testOnlyTheSystemsThatHadBadges() {
        XCTAssertEqual(DockBadges.style(forThemeID: "com.retromac.apple.aqua-cheetah"), .cheetah)
        XCTAssertEqual(DockBadges.style(forThemeID: "com.retromac.apple.snow-leopard"), .leopard)
        XCTAssertEqual(DockBadges.style(forThemeID: "com.retromac.apple.mountain-lion"), .leopard)
        XCTAssertEqual(DockBadges.style(forThemeID: "com.retromac.microsoft.windows7"), .win7)
        for none in ["com.retromac.microsoft.windowsvista", "com.retromac.microsoft.windowsxp",
                     "com.retromac.microsoft.windows95", "com.retromac.microsoft.windows31",
                     "com.retromac.apple.macos9", "com.retromac.next.nextstep", "com.retromac.be.beos5",
                     "com.retromac.seasonal.halloween", "com.retromac.microsoft.windows311-de", ""] {
            XCTAssertNil(DockBadges.style(forThemeID: none), none)
        }
        XCTAssertNil(DockBadges.style(forThemeID: nil))
    }

    func testPillGrowsWithTheNumber() {
        let one = DockBadgeArt.macBadge("3", style: .leopard, height: 20).size.width
        let three = DockBadgeArt.macBadge("128", style: .leopard, height: 20).size.width
        XCTAssertGreaterThan(three, one)
    }
}
