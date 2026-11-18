import XCTest
@testable import RetroMac

/// Tiger's Finder and Spotlight: the file model, the groups, and the window drawn offscreen
/// (with RETROMAC_SNAPSHOT_DIR set, to tiger-finder-icons/list/columns.png).
final class TigerFinderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rmfinder-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Pictures"), withIntermediateDirectories: true)
        try Data(count: 2048).write(to: dir.appendingPathComponent("Read Me.txt"))
        try Data(count: 10).write(to: dir.appendingPathComponent("item 10.txt"))
        try Data(count: 20).write(to: dir.appendingPathComponent("item 2.txt"))
        try Data().write(to: dir.appendingPathComponent(".hidden"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testChildrenSkipHiddenAndSortLikeFinder() {
        let names = FinderItem.children(of: dir).map(\.name)
        XCTAssertEqual(names, ["Documents", "item 2.txt", "item 10.txt", "Pictures", "Read Me.txt"])
        let bySize = FinderItem.sorted(FinderItem.children(of: dir).filter { !$0.isFolder }, by: "size", ascending: false)
        XCTAssertEqual(bySize.first?.name, "Read Me.txt")
        XCTAssertTrue(FinderItem.children(of: dir.appendingPathComponent("missing")).isEmpty)
    }

    func testUnusedNameCountsUp() throws {
        XCTAssertEqual(FinderItem.unusedURL(in: dir, base: "Documents", ext: "").lastPathComponent, "Documents 2")
        XCTAssertEqual(FinderItem.unusedURL(in: dir, base: "Read Me copy", ext: "txt").lastPathComponent, "Read Me copy.txt")
    }

    func testSpotlightGroupsInTigersOrder() {
        XCTAssertEqual(SpotlightSearch.category(["com.apple.application-bundle", "com.apple.application"]), "Applications")
        XCTAssertEqual(SpotlightSearch.category(["public.folder"]), "Folders")
        XCTAssertEqual(SpotlightSearch.category(["com.adobe.pdf", "public.content"]), "PDF Documents")
        XCTAssertEqual(SpotlightSearch.category(["public.jpeg", "public.image"]), "Images")
        XCTAssertEqual(SpotlightSearch.category(["public.plain-text", "public.text"]), "Documents")
        XCTAssertEqual(SpotlightSearch.order.first, "Applications")
    }

    @MainActor
    func testWindowDrawsInAllThreeViews() throws {
        let f = TigerFinder()
        f.wire()
        f.go(to: dir, record: false)
        let chrome = WebAppChromeView(frame: NSRect(x: 0, y: 0, width: 760, height: 470), title: "rmfinder", showNav: false)
        chrome.embed(f.view)
        for (m, name) in [(TigerFinder.Mode.icons, "icons"), (.list, "list"), (.columns, "columns")] {
            f.setMode(m)
            chrome.layoutSubtreeIfNeeded()
            f.view.icons.collectionViewLayout?.invalidateLayout()
            f.view.icons.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(chrome.bitmapImageRepForCachingDisplay(in: chrome.bounds))
            chrome.cacheDisplay(in: chrome.bounds, to: rep)
            if let out = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] {
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out).appendingPathComponent("tiger-finder-\(name).png"))
            }
        }
        XCTAssertEqual(f.view.status.stringValue.hasPrefix("5 items"), true, f.view.status.stringValue)
        XCTAssertEqual(f.view.list.numberOfRows, 5)
    }
}

/// Tiger's About This Mac, drawn offscreen (tiger-about.png with RETROMAC_SNAPSHOT_DIR).
final class TigerAboutTests: XCTestCase {
    @MainActor
    func testAboutWindowLaysOutTigersRows() throws {
        let w = TigerAboutWindow.shared.makeWindow()
        let v = try XCTUnwrap(w.contentView)
        let texts = v.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(texts.contains("Mac OS X"))
        XCTAssertTrue(texts.contains("Processor") && texts.contains("Memory"))
        XCTAssertFalse(texts.contains("Startup Disk"), "10.4 had no startup disk row")
        XCTAssertTrue(texts.contains { $0.contains("1983\u{2013}2005 Apple Computer") })
        if let out = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"],
           let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out).appendingPathComponent("tiger-about.png"))
        }
    }
}
