import XCTest
@testable import RetroMac

final class AppMoverTests: XCTestCase {
    func testOnlyTheDiskImageAndDownloadsAskToMove() {
        let home = "/Users/x"
        XCTAssertTrue(AppMover.needsMove("/Volumes/RetroMac/RetroMac.app", home: home))
        XCTAssertTrue(AppMover.needsMove("/Users/x/Downloads/RetroMac.app", home: home))
        XCTAssertTrue(AppMover.needsMove("/private/var/folders/ab/T/AppTranslocation/1234/d/RetroMac.app", home: home))
        XCTAssertFalse(AppMover.needsMove("/Applications/RetroMac.app", home: home))
        XCTAssertFalse(AppMover.needsMove("/Users/x/Applications/RetroMac.app", home: home))
        XCTAssertFalse(AppMover.needsMove("/Users/x/Projects/RetroMac/build/RetroMac.app", home: home))
    }
}
