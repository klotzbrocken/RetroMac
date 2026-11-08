import XCTest
import AppKit
@testable import RetroMac

/// Mac OS X 10.0's Apple menu: its rows in their order, and the Aqua menu drawn to 10.0's
/// measurements (set RETROMAC_SNAPSHOT_DIR to keep a picture of it).
final class AquaAppleMenuTests: XCTestCase {

    func testTheRowsAreTenPointZerosInItsOrder() {
        let rows = AppleMenuController.shared.macOSXItems().map { $0.title.isEmpty ? "—" : $0.title }
        XCTAssertEqual(rows, ["About This Mac", "Get Mac OS X Software\u{2026}", "—", "System Preferences\u{2026}", "Dock",
                              "Location", "—", "Recent Items", "—", "Force Quit\u{2026}", "—", "Sleep", "Restart",
                              "Shut Down", "—", "Log Out\u{2026}"])
        XCTAssertEqual(AppleMenuController.shared.macOSXItems().last?.shortcut, "\u{21E7}\u{2318}Q")
    }

    /// Location lists this Mac's own network locations (by the names macOS shows, "Automatisch"
    /// on a German Mac) with the one in use ticked, as many as scselect knows, and ends in
    /// Network Preferences. No more "Automatic" ticked on every Mac.
    func testLocationIsTheMacsOwn() throws {
        let rows = AppleMenuController.locationRows()
        XCTAssertEqual(rows.last?.title, "Network Preferences\u{2026}")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scselect")
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let sets = out.split(separator: "\n").filter { $0.contains("\t(") }
        let named = rows.filter { !$0.title.isEmpty && $0.title != "Network Preferences\u{2026}" }
        XCTAssertEqual(named.count, sets.count)
        XCTAssertEqual(named.filter(\.ticked).count, sets.contains { $0.hasPrefix(" *") } ? 1 : 0)
    }

    func testTheAquaMenuHasTenPointZerosRowsAndGaps() throws {
        let items = AppleMenuController.shared.macOSXItems()
        let rep = try XCTUnwrap(PlatinumMenuController.shared.snapshot(items, look: .aqua, hovered: 4))
        // 11 rows of 19 pt, 5 gaps of 12 pt, 4 above and 3 below: 276 pt, as 10.0.4's menu.
        XCTAssertEqual(rep.size.height, 11 * 19 + 5 * 12 + 7)
        if let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("aqua-apple-menu.png"))
        }
    }
}
