import XCTest
@testable import RetroMac

/// The Apps tab: one entry per app, the right release file picked, and nothing offered for
/// install that RetroMac cannot install.
final class AppCatalogTests: XCTestCase {

    func testEntriesAreUnique() {
        let c = AppCatalog.catalogue
        XCTAssertEqual(c.count, 14)
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

    /// The release files as they are named today: one disk image each, never the update zip,
    /// the Windows builds or the checksum files beside them.
    func testNewAppsPickTheirDiskImage() throws {
        let files: [String: [String]] = [
            "retrolux": ["retrolux-0.8.dmg", "retrolux-0.8.zip", "appcast.xml"],
            "retroncommander": ["retron-commander-1.0-macos-universal.dmg", "retron-commander-1.0-macos-universal.zip"],
            "macsplorer": ["macsplorer-macos.zip", "macsplorer-macos.zip.sha256", "macsplorer-linux-x86_64.tar.gz"],
            "arose": ["arose-screensaver-v1.0.3-macos-universal.dmg", "arose-screensaver-v1.0.3-macos-universal.dmg.sha256",
                      "arose-screensaver-v1.0.3-macos-update.zip", "arose-screensaver-v1.0.3-windows-x64.scr"],
        ]
        for (id, assets) in files {
            let app = try XCTUnwrap(AppCatalog.catalogue.first { $0.id == id })
            guard case .github(_, let matches) = app.source else { return XCTFail("\(id) comes from GitHub") }
            XCTAssertEqual(assets.filter(matches).count, 1, id)
        }
    }

    /// Open Scrantic's checksums.txt, as its release writes it.
    func testCastawayReadsItsChecksum() {
        let text = """
        3472d1d109b22e1da3a7ff404974e4cc05f1ea7a1f3fa382d0d2092c6359f78e  open-scrantic-linux-x64
        5a24b7b42ae602af6fad235e5cc5adbfdf7d07d8cbe0ba8677f6dd5e6b982957  open-scrantic-macos
        """
        XCTAssertEqual(JohnnyCastaway.checksum(for: "open-scrantic-macos", in: text),
                       "5a24b7b42ae602af6fad235e5cc5adbfdf7d07d8cbe0ba8677f6dd5e6b982957")
        XCTAssertNil(JohnnyCastaway.checksum(for: "open-scrantic-windows-x64.exe", in: text))
    }

    func testCastawayOnlyOnHisWindows() {
        XCTAssertTrue(JohnnyCastaway.belongs(onThemeID: "com.retromac.microsoft.windows31"))
        XCTAssertTrue(JohnnyCastaway.belongs(onThemeID: "com.retromac.microsoft.windows95"))
        XCTAssertTrue(JohnnyCastaway.belongs(onThemeID: "com.retromac.microsoft.windowsme"))
        XCTAssertFalse(JohnnyCastaway.belongs(onThemeID: "com.retromac.microsoft.windowsxp"))
        XCTAssertFalse(JohnnyCastaway.belongs(onThemeID: "com.retromac.apple.snow-leopard"))
    }

    func testStoreOnlyAppIsNotInstalledByRetroMac() throws {
        let paint = try XCTUnwrap(AppCatalog.catalogue.first { $0.id == "mojavepaint" })
        XCTAssertFalse(AppCatalog.canInstall(paint))
    }
}
