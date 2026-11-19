import XCTest
@testable import RetroMac

final class AmigaWorkbenchTests: XCTestCase {

    private var bundle: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes/AmigaWorkbench41.retromactheme")
    }

    /// "RAM:" is the private RAM Disk in the user's own temp folder, never the shared /tmp;
    /// every other path is expanded as before.
    func testRAMDiskIsPrivate() {
        let ram = AmigaRAMDisk.resolve("RAM:")
        XCTAssertTrue(ram.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertFalse(ram.hasPrefix("/tmp"))
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: ram, isDirectory: &isDir) && isDir.boolValue, "made on first use")
        XCTAssertEqual(AmigaRAMDisk.resolve("~"), NSHomeDirectory())
        XCTAssertEqual(AmigaRAMDisk.resolve("/"), "/")
    }

    /// The screen bar counts like the Workbench: thousands with commas, whatever the locale.
    func testBytesFreeGrouping() {
        XCTAssertEqual(AmigaScreenBarController.grouped(178_593_792), "178,593,792")
        XCTAssertEqual(AmigaScreenBarController.grouped(512), "512")
    }

    /// A window reaching up under a bar at the top of the work area comes down below it,
    /// though it does not touch the dock at the bottom.
    func testWindowsKeepOutOfTheScreenBar() {
        let visible = CGRect(x: 0, y: 31, width: 1440, height: 869)   // AX coordinates: the bar above y 31
        let dock = CGRect(x: 900, y: 836, width: 540, height: 64)
        let under = CGRect(x: 100, y: 10, width: 600, height: 400)
        XCTAssertEqual(WorkArea.adjusted(frame: under, visible: visible, bar: dock)?.minY, 31)
        XCTAssertNil(WorkArea.adjusted(frame: CGRect(x: 100, y: 40, width: 600, height: 400), visible: visible, bar: dock))
    }

    /// Every desktop and dock icon the theme names exists, each with its selected state; the
    /// pictures are the theme's own (drawn by Scripts/amiga-assets.swift).
    func testManifestPicturesExist() throws {
        let theme = try ThemeBundle(url: bundle, isBuiltIn: true)
        let cfg = theme.config
        XCTAssertEqual(cfg.chrome?.style, "amiga")
        XCTAssertTrue(cfg.isAmiga)
        XCTAssertEqual(cfg.dock.labelsBelow, true)
        XCTAssertNotNil(theme.rootResource(cfg.wallpaper ?? ""), "the default wallpaper")
        let icons = (cfg.desktopIcons ?? []).map(\.icon) + Array(cfg.iconMappings.values)
        XCTAssertFalse(icons.isEmpty)
        for name in icons {
            XCTAssertNotNil(theme.iconResource(name), "\(name) missing")
            let sel = (name as NSString).deletingPathExtension + "-sel.png"
            XCTAssertNotNil(theme.iconResource(sel), "\(sel) missing")
        }
        XCTAssertEqual(cfg.desktopIcons?.first { $0.name == "RAM Disk" }?.path, AmigaRAMDisk.token)
        XCTAssertNil(cfg.desktopIcons?.first { $0.type == "tvfolder" || $0.type == "cpumonitor" }, "no widgets on the Workbench")
    }
}
