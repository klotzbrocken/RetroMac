import XCTest
@testable import RetroMac

/// QNX 6.2.1's shelf, taskbar and Launch menu at their measured sizes; with RETROMAC_SNAPSHOT_DIR
/// set they are drawn to PNGs for comparing against the reference screenshots.
final class PhotonSnapshotTests: XCTestCase {
    private func theme() throws -> ThemeBundle {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes/QNX621-Photon.retromactheme")
        return try ThemeBundle(url: url, isBuiltIn: true)
    }

    private func snapshot(_ view: NSView, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"],
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    @MainActor
    func testShelfAndTaskbar() throws {
        let t = try theme()
        XCTAssertEqual(t.config.id, "com.retromac.qnx.qnx621-photon")
        XCTAssertTrue(t.config.hidesDock, "the shelf and the taskbar stand in for the dock")
        XCTAssertEqual(PhotonShelfView.width, 135)
        XCTAssertEqual(PhotonTaskbarView.height, 31)
        let shelf = PhotonShelfView(theme: t)
        shelf.frame = NSRect(x: 0, y: 0, width: PhotonShelfView.width, height: 575)
        try snapshot(shelf, "photon-shelf.png")
        let bar = PhotonTaskbarView(theme: t)
        bar.frame = NSRect(x: 0, y: 0, width: 800, height: PhotonTaskbarView.height)
        try snapshot(bar, "photon-taskbar.png")
    }

    func testTheShelfStartsAsThe621OneDid() {
        XCTAssertEqual(PhotonShelfView.makeGroups().map(\.title),
                       ["Applications", "Utilities", "Configure", "System Monitor", "CD Player", "World View"])
        XCTAssertEqual(PhotonShelfView.collapsedByDefault, ["utilities", "cdplayer", "worldview"])
    }

    func testLaunchCategories() {
        XCTAssertEqual(PhotonLaunchMenu.category(of: "/x.app", category: "public.app-category.developer-tools", internet: []), "Development")
        XCTAssertEqual(PhotonLaunchMenu.category(of: "/x.app", category: "public.app-category.music", internet: []), "MultiMedia")
        XCTAssertEqual(PhotonLaunchMenu.category(of: "/x.app", category: nil, internet: ["/x.app"]), "Internet", "what opens web pages is Internet")
        XCTAssertEqual(PhotonLaunchMenu.category(of: "/x.app", category: nil, internet: []), "Utilities")
    }

    func testTheClockReadsAsPhotonsDid() {
        var c = DateComponents(); c.year = 2004; c.month = 1; c.day = 11; c.hour = 17; c.minute = 45
        XCTAssertEqual(PhotonTaskbarView.clockText(Calendar.current.date(from: c)!), "Sun-11 05:45PM")
    }
}
