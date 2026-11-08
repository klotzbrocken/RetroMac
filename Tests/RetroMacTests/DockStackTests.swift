import XCTest
@testable import RetroMac

/// The dock stacks: 10.6's sort orders, its per-folder defaults, and the folder test the grid
/// steps into. With RETROMAC_SNAPSHOT_DIR set the fan and a scrolled grid are drawn to
/// stack-fan.png and stack-grid.png.
final class DockStackTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("stack-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // b.txt newest, then c.pdf, then a.txt; one folder, one hidden file, one app-like package.
        let now = Date()
        for (name, age) in [("a.txt", 300.0), ("c.pdf", 200.0), ("b.txt", 100.0)] {
            let url = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age),
                                  .creationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        try fm.createDirectory(at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-400)], ofItemAtPath: dir.appendingPathComponent("Sub").path)
        try fm.createDirectory(at: dir.appendingPathComponent("Tool.app/Contents"), withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-500)], ofItemAtPath: dir.appendingPathComponent("Tool.app").path)
        try Data().write(to: dir.appendingPathComponent(".hidden"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func names(_ sort: StackOptions.Sort) -> [String] {
        StackOptions.contents(of: dir, sort: sort).map(\.lastPathComponent)
    }

    func testSortOrders() {
        XCTAssertEqual(names(.name), ["a.txt", "b.txt", "c.pdf", "Sub", "Tool.app"])
        XCTAssertEqual(names(.dateModified), ["b.txt", "c.pdf", "a.txt", "Sub", "Tool.app"])
        // Kind groups by type description and keeps names in order inside a kind.
        let kind = names(.kind)
        XCTAssertEqual(kind.count, 5)
        XCTAssertLessThan(kind.firstIndex(of: "a.txt")!, kind.firstIndex(of: "b.txt")!)
        XCTAssertEqual(abs(kind.firstIndex(of: "a.txt")! - kind.firstIndex(of: "b.txt")!), 1)
        XCTAssertFalse(names(.dateAdded).contains(".hidden"))
    }

    func testFoldersButNotPackages() {
        XCTAssertTrue(StackOptions.isFolder(dir.appendingPathComponent("Sub")))
        XCTAssertFalse(StackOptions.isFolder(dir.appendingPathComponent("Tool.app")))
        XCTAssertFalse(StackOptions.isFolder(dir.appendingPathComponent("a.txt")))
    }

    func testDefaultsAndStorage() {
        XCTAssertEqual(StackOptions.defaults(for: "/Applications").sort, .name)
        XCTAssertEqual(StackOptions.defaults(for: NSHomeDirectory() + "/Downloads").sort, .dateAdded)
        XCTAssertEqual(StackOptions.defaults(for: dir.path), StackOptions(sort: .dateModified, display: nil, view: .automatic))
        StackOptions.save(StackOptions(sort: .kind, display: .stack, view: .list), for: dir.path)
        XCTAssertEqual(StackOptions.load(dir.path), StackOptions(sort: .kind, display: .stack, view: .list))
        var all = UserDefaults.standard.dictionary(forKey: "dockStackOptions") ?? [:]
        all[dir.path] = nil
        UserDefaults.standard.set(all, forKey: "dockStackOptions")
    }

    @MainActor
    func testSnapshots() throws {
        guard let out = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] else { return }
        let files = StackOptions.contents(of: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads"), sort: .dateAdded)

        let fan = DockStackView(frame: NSRect(x: 0, y: 0, width: 400, height: 8 * 54 + 8))
        fan.fan = true; fan.openTile = true
        fan.files = Array(files.prefix(7)); fan.moreCount = max(0, files.count - 7)
        fan.iconSize = 48; fan.cellH = 54; fan.labelRoom = 250; fan.fanX = 274
        try write(fan, to: out, "stack-fan.png", background: .darkGray)

        let grid = DockStackView(frame: .zero)
        grid.chrome = "snowleopard"
        grid.files = files; grid.iconSize = 56; grid.cols = 6; grid.gap = 8
        grid.headerH = 24; grid.footerH = 24; grid.pad = 12; grid.cellW = 98; grid.cellH = 76
        grid.contentRows = Int(ceil(Double(max(files.count, 1)) / 6)); grid.canGoBack = true
        grid.folderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        grid.frame = NSRect(x: 0, y: 0, width: 24 + 6 * 98 + 5 * 8, height: 24 + 12 + 3 * 76 + 2 * 8 + 24 + 12)
        try write(grid, to: out, "stack-grid.png", background: .gray)
    }

    @MainActor
    private func write(_ view: NSView, to dir: String, _ name: String, background: NSColor) throws {
        let host = NSView(frame: view.bounds)
        host.wantsLayer = true; host.layer?.backgroundColor = background.cgColor
        host.addSubview(view)
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }
}
