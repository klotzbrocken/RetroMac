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

final class AmigaDrawerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AmigaDrawerTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("Docs"), withIntermediateDirectories: true)
        try "hello".write(to: dir.appendingPathComponent("ReadMe.txt"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2]).write(to: dir.appendingPathComponent("blob.xyz123"))
        try Data([3]).write(to: dir.appendingPathComponent("game.xyz456"))
        try Data([4]).write(to: dir.appendingPathComponent("game.xyz456.info"))
        try Data([5]).write(to: dir.appendingPathComponent(".hidden.txt"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Only icons: the drawer, the text project and the object with its .info; never the .info
    /// itself or a hidden file. All files adds the unknown blob, still no .info, nothing hidden.
    func testShowOnlyIconsAndAllFiles() {
        let only = AmigaDrawer.items(in: dir, allFiles: false)
        XCTAssertEqual(only.map(\.name), ["Docs", "game.xyz456", "ReadMe.txt"])
        XCTAssertEqual(only.first { $0.name == "Docs" }?.kind, .drawer)
        XCTAssertEqual(only.first { $0.name == "game.xyz456" }?.info?.lastPathComponent, "game.xyz456.info")
        XCTAssertNil(only.first { $0.name == "ReadMe.txt" }?.info)
        let all = AmigaDrawer.items(in: dir, allFiles: true)
        XCTAssertEqual(all.map(\.name), ["blob.xyz123", "Docs", "game.xyz456", "ReadMe.txt"])
        XCTAssertFalse(all.contains { $0.name.hasSuffix(".info") || $0.name.hasPrefix(".") })
    }

    func testSnapshotRoundTrip() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "AmigaDrawerTests"))
        defer { d.removePersistentDomain(forName: "AmigaDrawerTests") }
        XCTAssertEqual(AmigaDrawer.loadSnapshot("/x", d), AmigaDrawer.Snapshot())
        let s = AmigaDrawer.Snapshot(frame: [10, 20, 300, 200], icons: ["Docs": [6, 6]], allFiles: true)
        AmigaDrawer.saveSnapshot(s, "/x", d)
        XCTAssertEqual(AmigaDrawer.loadSnapshot("/x", d), s)
        AmigaDrawer.saveSnapshot(AmigaDrawer.Snapshot(), "/x", d)   // Unsnapshot of everything: nothing kept
        XCTAssertNil(d.object(forKey: AmigaDrawer.defaultsKey("/x")))
    }

    /// The System drawer is a fixed list: Prefs, Utilities, Tools, Fonts, Trashcan and the
    /// startup disk, nothing outside it.
    func testSystemDrawerIsTheFixedList() {
        let items = AmigaDrawer.systemItems()
        XCTAssertEqual(Array(items.map(\.name).prefix(5)), ["Prefs", "Utilities", "Tools", "Fonts", "Trashcan"])
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(Set(items.compactMap { $0.url?.path }.filter { !$0.hasSuffix(".app") }),
                       ["/Applications/Utilities", "/Applications", "/Library/Fonts", "/"])
        XCTAssertEqual(AmigaRAMDisk.resolve(AmigaDrawer.systemToken), "/")
    }
}
