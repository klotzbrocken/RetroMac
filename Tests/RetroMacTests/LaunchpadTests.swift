import XCTest
@testable import RetroMac

/// Mountain Lion's Launchpad: forty apps a page in eight columns, the rest on further pages.
/// With RETROMAC_SNAPSHOT_DIR set it is drawn to launchpad.png over the Lion wallpaper.
final class LaunchpadTests: XCTestCase {
    @MainActor
    func testAPageHoldsFortyAppsInEightColumns() throws {
        let apps = (0..<45).map { LaunchpadController.App(name: "App \($0)", url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari") }
        let view = LaunchpadView(frame: NSRect(x: 0, y: 0, width: 1470, height: 919), controller: .shared)
        view.show(Array(apps.prefix(LaunchpadController.perPage)), page: 0, of: 2)
        XCTAssertEqual(view.grid.subviews.count, 40)
        XCTAssertEqual(Set(view.grid.subviews.map { $0.frame.midX.rounded() }).count, 8)
        XCTAssertEqual(Set(view.grid.subviews.map { $0.frame.minY.rounded() }).count, 5)

        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] else { return }
        let real = LaunchpadController.installedApps()
        view.show(Array(real.prefix(LaunchpadController.perPage)), page: 0, of: 2)
        let wall = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Themes/MacOSX-Aqua.retromactheme/wallpaper.jpg")
        view.setBackground(LaunchpadController.blurred(wall))
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("launchpad.png"))
    }
}
