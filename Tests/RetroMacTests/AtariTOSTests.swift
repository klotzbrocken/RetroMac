import XCTest
@testable import RetroMac

/// Atari TOS 4.04 (Lastenheft „Atari TOS 4.04 für RetroMac“): the manifest, the GEM geometry
/// measured off the 640 × 480 screenshots, the desktop's layout and the APPS scan.
final class AtariTOSTests: XCTestCase {
    private let bundle = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/Themes/AtariTOS404.retromactheme")

    func testManifestAndEveryIconItNames() throws {
        let theme = try ThemeBundle(url: bundle, isBuiltIn: true)
        let c = theme.config
        XCTAssertEqual(c.id, "com.retromac.atari.tos404")
        XCTAssertEqual(c.chrome?.style, "gem")
        XCTAssertEqual(RetroFrameTheme.legacyKeyFromName(c.name), "gem", "an imported copy without chrome.style keeps GEM")
        XCTAssertNotNil(SwitcherCapability.matrix[c.id ?? ""])
        for file in Set(c.iconMappings.values) + [c.fallbackIcon ?? "?", "gem_disk.png", "gem_trash.png", "gem_trash_full.png"] {
            XCTAssertNotNil(theme.iconResource(file), file)
            XCTAssertNotNil(theme.iconResource(file.replacingOccurrences(of: ".png", with: "_sel.png")), "\(file) has no selected state")
        }
    }

    /// `_2.png`: " Desk " covers 16 … 63, the titles follow each other a space either side.
    func testMenuBarTitlesSitWhereGEMPutThem() {
        XCTAssertEqual(GEMMenuBarView.titleRect(0), NSRect(x: 16, y: 0, width: 48, height: 18))
        XCTAssertEqual(GEMMenuBarView.titleRect(1).minX, 64)
        XCTAssertEqual(GEMMenuBarView.titleRect(3), NSRect(x: 160, y: 0, width: 72, height: 18))
    }

    /// `_3.png`: 16 pt rows in a 1 pt line, as wide as the longest entry and five cells more.
    func testPulldownSize() throws {
        let items = GEMMenus.items("View")
        let rep = try XCTUnwrap(PlatinumMenuController.shared.snapshot(items, look: .gem))
        XCTAssertEqual(rep.size.width, CGFloat("Show as Icons".count + 5) * 8 + 2)
        XCTAssertEqual(rep.size.height, CGFloat(items.count) * 16 + 2)
    }

    func testLabelsInTheSmallFont() {
        XCTAssertEqual(GEMChrome.smallLabel("Macintosh HD"), "MACINTOSH HD")
        XCTAssertEqual(GEMChrome.smallLabel("Über Café"), "ÜBER CAFE")
        XCTAssertEqual(GEMChrome.smallLabel("Microsoft PowerPoint"), "MICROSOFT P.", "twelve cells, the cut marked")
        XCTAssertEqual(GEMChrome.smallLabel("Notes™"), "NOTES?")
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ÄÖÜ" { XCTAssertNotNil(GEMChrome.small[ch], String(ch)) }
    }

    /// Drives down the left from the top, TRASH in the bottom left corner, installed apps down the
    /// right; a saved cell wins when it is on screen and free.
    func testDesktopLayout() {
        let ids = ["boot", "apps", "vol:/Volumes/X", "trash", "app:/Applications/A.app"]
        let fresh = GEMDesktopView.layout(ids, saved: [:], columns: 10, rows: 8)
        XCTAssertTrue(fresh["boot"]! == (0, 0)); XCTAssertTrue(fresh["apps"]! == (0, 1)); XCTAssertTrue(fresh["vol:/Volumes/X"]! == (0, 2))
        XCTAssertTrue(fresh["trash"]! == (0, 7)); XCTAssertTrue(fresh["app:/Applications/A.app"]! == (9, 0))
        let moved = GEMDesktopView.layout(ids, saved: ["apps": [4, 3], "trash": [40, 2], "boot": [4, 3]], columns: 10, rows: 8)
        XCTAssertTrue(moved["boot"]! == (4, 3), "saved and free")
        XCTAssertTrue(moved["apps"]! == (0, 0), "its saved cell taken: the next free one")
        XCTAssertTrue(moved["trash"]! == (0, 7), "off screen: back to its corner")
    }

    /// `_2.png`: FLOPPY DISK A above the drives, GAMES after them, the program column down the right
    /// edge; each built-in icon is an original from DESKICON.RSC with its selected picture.
    func testFloppyGamesAndTheProgramColumn() throws {
        let ids = ["floppy", "boot", "apps", "games", "trash"] + GEMDesktopView.links.map { "link:" + $0.name } + ["link:README"]
        let l = GEMDesktopView.layout(ids, saved: [:], columns: 10, rows: 8)
        XCTAssertTrue(l["floppy"]! == (0, 0)); XCTAssertTrue(l["boot"]! == (0, 1)); XCTAssertTrue(l["games"]! == (0, 3))
        XCTAssertTrue(l["link:TEXTEDIT"]! == (9, 0)); XCTAssertTrue(l["link:README"]! == (9, 4))
        let theme = try ThemeBundle(url: bundle, isBuiltIn: true)
        for icon in GEMDesktopView.links.map(\.icon) + ["gem_floppy", "gem_games", "gem_text"] {
            XCTAssertNotNil(theme.iconResource(icon + ".png"), icon); XCTAssertNotNil(theme.iconResource(icon + "_sel.png"), icon)
        }
    }

    /// Apps one level into vendor folders, none deeper; a link and an installed copy count once.
    func testAppsScanFindsEachAppOnce() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gemapps-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        for p in ["A.app", "Vendor/B.app", "Vendor/Deep/C.app", "A.app/Contents/Helpers/H.app"] {
            try fm.createDirectory(at: root.appendingPathComponent(p), withIntermediateDirectories: true)
        }
        try fm.createSymbolicLink(at: root.appendingPathComponent("Link.app"), withDestinationURL: root.appendingPathComponent("A.app"))
        let found = GEMApps.scan(roots: [root], extra: [root.appendingPathComponent("A.app"), URL(fileURLWithPath: "/nowhere/Z.app")])
        XCTAssertEqual(Set(found.map { $0.url.lastPathComponent }), ["A.app", "B.app"])
        XCTAssertEqual(GEMApps.sorted(found, byType: false).map(\.name), ["A", "B"])
    }
}
