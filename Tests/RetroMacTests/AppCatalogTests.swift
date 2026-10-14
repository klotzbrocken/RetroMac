import XCTest
@testable import RetroMac

/// The Apps tab: one entry per app, the right release file picked, and nothing offered for
/// install that RetroMac cannot install.
final class AppCatalogTests: XCTestCase {

    func testEntriesAreUnique() {
        let c = AppCatalog.catalogue
        XCTAssertEqual(c.count, 9)
        XCTAssertEqual(Set(c.map(\.id)).count, c.count)
        XCTAssertEqual(Set(c.map(\.bundleID)).count, c.count)
    }

    /// Reframe ships an Apple silicon and an Intel disk image; exactly one must match per Mac,
    /// and never the zip, the blockmap or the Windows and Linux builds.
    func testReframePicksOneDiskImage() throws {
        let reframe = try XCTUnwrap(AppCatalog.catalogue.first { $0.id == "reframe" })
        guard case .github(_, let matches) = reframe.source else { return XCTFail("Reframe comes from GitHub") }
        let assets = ["reframe-1.16.0-arm64-mac.zip", "reframe-1.16.0-arm64.dmg", "reframe-1.16.0-arm64.dmg.blockmap",
                      "reframe-1.16.0-mac.zip", "reframe-1.16.0.appimage", "reframe-1.16.0.dmg", "reframe-1.16.0.exe"]
        XCTAssertEqual(assets.filter(matches).count, 1)
    }

    func testStoreOnlyAppIsNotInstalledByRetroMac() throws {
        let paint = try XCTUnwrap(AppCatalog.catalogue.first { $0.id == "mojavepaint" })
        XCTAssertFalse(AppCatalog.canInstall(paint))
    }
}
