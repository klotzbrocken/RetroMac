import XCTest
@testable import RetroMac

final class TubeAnnouncementTests: XCTestCase {
    func testOpeningSaysHowToWorkIt() {
        let s = TubeModeController.channelAnnouncement(number: 1, of: 3, name: "Retro", opening: true)
        XCTAssertTrue(s.hasPrefix("TV Tube, Channel 1 of 3, Retro."))
        XCTAssertTrue(s.contains("Escape closes"))
    }

    func testSwitchSaysOnlyTheChannel() {
        XCTAssertEqual(TubeModeController.channelAnnouncement(number: 2, of: 3, name: "Now 90s", opening: false),
                       "Channel 2 of 3, Now 90s")
    }
}
