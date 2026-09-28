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
