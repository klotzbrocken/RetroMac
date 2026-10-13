import XCTest
@testable import RetroMac

/// Mountain Lion's own About This Mac, Apple menu and Downloads pile. With RETROMAC_SNAPSHOT_DIR set
/// the About window and the pile are drawn to ml-about.png and ml-pile.png.
final class MountainLionMenuTests: XCTestCase {
    func testAboutReadsThisMac() {
        let f = MountainLionAboutWindow.facts()
        XCTAssertTrue(f.version.hasPrefix("Version \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)."))
        XCTAssertFalse(f.processor.isEmpty)
        XCTAssertTrue(f.memory.hasSuffix(" GB"))
        XCTAssertFalse(f.disk.isEmpty)
    }

    func testTheMenuIsTenEightsRowForRow() {
        let titles = AppleMenuController.shared.mountainLionItems().map(\.title)
        XCTAssertEqual(Array(titles.prefix(4)), ["About This Mac", "Software Update\u{2026}", "App Store\u{2026}", ""])
        XCTAssertTrue(titles.contains("Force Quit\u{2026}"))
        XCTAssertTrue(titles.contains("Restart\u{2026}"))
        XCTAssertTrue(titles.last?.hasPrefix("Log Out ") == true)
        XCTAssertFalse(titles.contains("Location"))
    }

    @MainActor
    func testSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] else { return }
        MountainLionAboutWindow.shared.show()
        let about = try XCTUnwrap(NSApp.windows.first { $0.title == "About This Mac" }?.contentView)
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        if let rep = about.bitmapImageRepForCachingDisplay(in: about.bounds) {
            about.cacheDisplay(in: about.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ml-about.png"))
        }
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        let newest = StackPreview.newestFiles(in: downloads, limit: 3)
        let pile = StackPreview.pile(newest.map { (NSWorkspace.shared.icon(forFile: $0.path), false) }, size: 128)
        let rep = NSBitmapImageRep(data: pile.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ml-pile.png"))
    }
}
