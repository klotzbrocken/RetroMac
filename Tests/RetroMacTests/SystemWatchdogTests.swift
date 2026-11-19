import XCTest
@testable import RetroMac

final class SystemWatchdogTests: XCTestCase {
    /// Only `--watchdog <pid>` makes a watchdog; anything else starts the app as usual.
    func testWatchedPIDParsing() {
        XCTAssertEqual(SystemWatchdog.watchedPID(in: ["RetroMac", "--watchdog", "4242"]), 4242)
        XCTAssertNil(SystemWatchdog.watchedPID(in: ["RetroMac"]))
        XCTAssertNil(SystemWatchdog.watchedPID(in: ["RetroMac", "--watchdog"]))
        XCTAssertNil(SystemWatchdog.watchedPID(in: ["RetroMac", "--watchdog", "abc"]))
        XCTAssertNil(SystemWatchdog.watchedPID(in: ["RetroMac", "--watchdog", "1"]), "never launchd")
        XCTAssertNil(SystemWatchdog.watchedPID(in: ["RetroMac", "--rescue-desktop"]))
    }
}
