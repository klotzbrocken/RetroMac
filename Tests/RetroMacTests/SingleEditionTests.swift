import XCTest
@testable import RetroMac

final class SingleEditionTests: XCTestCase {

    func testTheEditionKeyPicksTheEdition() {
        XCTAssertEqual(Edition.edition(for: "snowleopard")?.themeID, "com.retromac.apple.snow-leopard")
        XCTAssertNil(Edition.edition(for: nil))          // the full RetroMac
        XCTAssertNil(Edition.edition(for: "something"))
        // The test bundle is the full app: none of the edition's gates are on.
        XCTAssertFalse(Edition.isSingle)
    }

    func testTheCountdownRunsDownToZeroAndStays() {
        var r = SingleWelcome.lockSeconds
        var steps = 0
        while r > 0 { r = SingleWelcome.tick(r); steps += 1 }
        XCTAssertEqual(steps, 6)
        XCTAssertEqual(SingleWelcome.tick(0), 0)
    }

    func testTheFullAppLinkSaysWhereTheVisitComesFrom() {
        XCTAssertEqual(URL(string: "https://myretromac.app/?ref=snowleopard")?.query, "ref=snowleopard")
        XCTAssertTrue(Edition.fullAppURL.absoluteString.hasPrefix("https://myretromac.app/?ref="))
    }
}
