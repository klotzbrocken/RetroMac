import XCTest
@testable import RetroMac

/// The historic window switcher (Lastenheft 3.0, 8): its release matrix and the focus cycle.
final class WindowSwitcherTests: XCTestCase {
    private func bundledThemeIDs() throws -> [String] {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "retromactheme" }
            .compactMap { try JSONSerialization.jsonObject(with: Data(contentsOf: $0.appendingPathComponent("theme.json"))) as? [String: Any] }
            .compactMap { $0["id"] as? String }
    }

    /// SW-A1: every theme has an explicit entry; one that has none starts nothing.
    func testEveryThemeHasAnEntry() throws {
        let ids = try bundledThemeIDs()
        XCTAssertGreaterThan(ids.count, 20)
        for id in ids { XCTAssertNotNil(SwitcherCapability.matrix[id], "\(id) has no switcher entry") }
        XCTAssertFalse(SwitcherCapability.forTheme("com.example.unknown").isAvailable)
        XCTAssertFalse(SwitcherCapability.forTheme(nil).isAvailable)
    }

    /// SW-A2: Cheetah gets no Exposé, CDE no Alt+Tab panel.
    func testNothingAnEraDidNotHave() {
        XCTAssertEqual(SwitcherCapability.forTheme("com.retromac.apple.aqua-cheetah").mode, .none)
        XCTAssertEqual(SwitcherCapability.forTheme("com.retromac.sun.solaris8-cde").mode, .focusCycle)
        XCTAssertEqual(SwitcherCapability.forTheme("com.retromac.apple.snow-leopard").mode, .expose)
    }

    /// SW-02: a mode whose reference is not in yet stays off.
    func testPendingStaysOff() {
        let xp = SwitcherCapability.forTheme("com.retromac.microsoft.windowsxp")
        XCTAssertEqual(xp.mode, .altTab)
        XCTAssertFalse(xp.isAvailable)
        XCTAssertFalse(SwitcherCapability.forTheme("com.retromac.microsoft.windowsvista").isAvailable)
    }

    func testTheCycleGoesRoundBothWays() {
        XCTAssertEqual(WindowSwitcher.nextIndex(0, count: 3, backward: false), 1)
        XCTAssertEqual(WindowSwitcher.nextIndex(2, count: 3, backward: false), 0)
        XCTAssertEqual(WindowSwitcher.nextIndex(0, count: 3, backward: true), 2)
        XCTAssertEqual(WindowSwitcher.nextIndex(0, count: 0, backward: true), 0)
    }
}
