import XCTest
@testable import RetroMac

/// The Solaris 8 Front Panel and a subpanel lay out at their measured sizes; with
/// RETROMAC_SNAPSHOT_DIR set, both are drawn to PNGs for comparing against the reference.
final class CDESnapshotTests: XCTestCase {
    private func theme() throws -> ThemeBundle {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes/Solaris8-CDE.retromactheme")
        return try ThemeBundle(url: url, isBuiltIn: true)
    }

    private func snapshot(_ view: NSView, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"],
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    @MainActor
    func testFrontPanel() throws {
        let t = try theme()
        XCTAssertEqual(t.config.id, "com.retromac.sun.solaris8-cde")
        XCTAssertTrue(t.config.hidesDock, "the Front Panel stands in for the dock")
        let v = CDEFrontPanelView(theme: t)
        XCTAssertEqual(v.frame.size, NSSize(width: 956, height: 86))
        try snapshot(v, "cde-frontpanel.png")
    }

    @MainActor
    func testSubpanel() throws {
        let v = CDESubpanel(kind: .help, theme: try theme())
        XCTAssertEqual(v.frame.width, 208, "the width of the Solaris 8 Help subpanel")
        try snapshot(v, "cde-subpanel-help.png")
    }
}
