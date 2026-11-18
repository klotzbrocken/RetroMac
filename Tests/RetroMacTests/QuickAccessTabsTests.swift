import XCTest
import SwiftUI
@testable import RetroMac

/// The Themes menu and the flyout list the youngest era first; the flyout's Quick Access
/// keeps one row of eight per family tab.
final class QuickAccessTabsTests: XCTestCase {
    private func themes() throws -> [ThemeBundle] {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Themes")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "retromactheme" }
            .map { try ThemeBundle(url: $0, isBuiltIn: true) }
    }

    func testYoungestEraFirst() throws {
        let apple = ThemeManager.byAge(try themes().filter { ThemeManager.category(of: $0) == "Apple" })
        let years = apple.compactMap { $0.config.release?.year }
        XCTAssertEqual(years, years.sorted(by: >))
        XCTAssertEqual(apple.first?.name, "Mountain Lion")
        let i = apple.firstIndex { $0.name == "Mac OS X Tiger" }!, j = apple.firstIndex { $0.name == "Mac OS X" }!
        XCTAssertLessThan(i, j, "10.4 before 10.0")
    }

    func testCrownedAppleAndWindowsWearTheirLogo() throws {
        let all = try themes()
        let xp = all.first { $0.name == "Windows XP" }!, tiger = all.first { $0.name == "Mac OS X Tiger" }!
        XCTAssertNotNil(ThemeManager.familyLogo(for: tiger))
        XCTAssertEqual(ThemeManager.displayName(for: xp.name, marker: false), "Windows XP")
        if let futurama = all.first(where: { $0.name.lowercased().contains("futurama") }) {
            XCTAssertNil(ThemeManager.familyLogo(for: futurama), "the others keep the 💯")
        }
    }

    func testPreviousSlotsGoToTheirTabFirstThenTheFamilyFills() {
        typealias T = LauncherModel.ThemeItem
        let items = [T(name: "Win7", icon: nil, tab: "Windows"), T(name: "ML", icon: nil, tab: "Apple"),
                     T(name: "XP", icon: nil, tab: "Windows"), T(name: "BeOS", icon: nil, tab: "Various")]
        let tabs = LauncherView.sorted(previous: ["XP", "", "Gone"], into: items)
        XCTAssertEqual(tabs["Windows"], ["XP", "Win7"])
        XCTAssertEqual(tabs["Apple"], ["ML"])
        XCTAssertEqual(tabs["Various"], ["BeOS"])
        let many = (0..<12).map { T(name: "A\($0)", icon: nil, tab: "Apple") }
        XCTAssertEqual(LauncherView.sorted(previous: [], into: many)["Apple"]?.count, 8)
    }
}

/// With RETROMAC_SNAPSHOT_DIR set, the flyout is drawn to flyout.png.
final class FlyoutSnapshotTests: XCTestCase {
    @MainActor
    func testFlyoutDraws() throws {
        guard let out = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] else { throw XCTSkip("snapshot only") }
        let host = NSHostingView(rootView: LauncherView(onClose: {}))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 640)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame.size = size
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out).appendingPathComponent("flyout.png"))
    }
}
