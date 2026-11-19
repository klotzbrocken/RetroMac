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

    /// A normal quit leaves its pid behind; the watchdog of that process sees it, another's does not.
    func testCleanExitMark() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "SystemWatchdogTests"))
        defer { d.removePersistentDomain(forName: "SystemWatchdogTests") }
        XCTAssertFalse(SystemWatchdog.endedCleanly(getpid(), d))
        SystemWatchdog.markCleanExit(d)
        XCTAssertTrue(SystemWatchdog.endedCleanly(getpid(), d))
        XCTAssertFalse(SystemWatchdog.endedCleanly(getpid() + 1, d), "a crash of the next run is still recovered")
    }
}
