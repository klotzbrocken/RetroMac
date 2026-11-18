import XCTest
@testable import RetroMac

/// Mac OS X 10.4 Tiger: a built-in theme that shares Cheetah's icons and Snow Leopard's boot
/// film through symlinks, the frosted dock without pinstripes, brushed-metal title bars.
/// With RETROMAC_SNAPSHOT_DIR set the metal bar is drawn to tiger-titlebar.png.
final class TigerThemeTests: XCTestCase {
    private let themes = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Resources/Themes").standardizedFileURL
    private var tigerURL: URL { themes.appendingPathComponent("MacOSX-Tiger.retromactheme") }

    func testManifest() throws {
        let tiger = try ThemeBundle(url: tigerURL, isBuiltIn: true)
        let c = tiger.config
        XCTAssertEqual(c.id, "com.retromac.apple.tiger")
        XCTAssertEqual(c.chrome?.style, "macosx")
        XCTAssertEqual(c.chrome?.titleBar, "brushed")
        XCTAssertEqual(c.menuBarAppleStyleDefault, 1, "the rainbow Apple")
        XCTAssertEqual(c.dock.pinstripe, false)
        XCTAssertTrue(c.supportsAutoHide)
        XCTAssertNotNil(SwitcherCapability.matrix["com.retromac.apple.tiger"])
        XCTAssertEqual(DockBadges.style(forThemeID: c.id), .leopard)
    }

    /// Every wallpaper and every mapped icon resolves, the shared ones to the sibling's file.
    func testSharedFilesResolveForTheBuiltInTheme() throws {
        let tiger = try ThemeBundle(url: tigerURL, isBuiltIn: true)
        XCTAssertEqual(tiger.wallpaperOptions().count, 10)
        for w in tiger.config.wallpapers ?? [] {
            XCTAssertNotNil(tiger.rootResource(w.file), w.file)
        }
        for (id, file) in tiger.config.iconMappings {
            XCTAssertNotNil(tiger.iconURL(for: id), "\(id) → \(file)")
        }
        let finder = try XCTUnwrap(tiger.iconURL(for: "com.apple.finder"))
        XCTAssertTrue(finder.path.contains("MacOSX-Cheetah.retromactheme/icons/"), finder.path)
        XCTAssertNotNil(tiger.rootResource("boot.mp4"))
    }

    /// The same bundle, imported, stays fenced into its own folder: its links lead nowhere.
    func testImportedThemeCannotFollowLinksOut() throws {
        let imported = try ThemeBundle(url: tigerURL, isBuiltIn: false)
        XCTAssertNil(imported.iconURL(for: "com.apple.finder"))
        XCTAssertNil(imported.rootResource("wallpaper.jpg"))
        XCTAssertNotNil(imported.rootResource("wallpaper-lotus.jpg"), "its own files still resolve")
    }

    /// A duplicate leaves the Themes folder, so it carries real copies, not links.
    func testDuplicateMaterializesSharedFiles() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rmtiger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let tiger = try ThemeBundle(url: tigerURL, isBuiltIn: true)
        let copy = try ThemeBundle.create(name: "My Tiger", basedOn: tiger, at: tmp)
        let walk = FileManager.default.enumerator(at: copy.url, includingPropertiesForKeys: [.isSymbolicLinkKey])!
        for case let u as URL in walk {
            XCTAssertNotEqual((try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink, true, u.path)
        }
        XCTAssertNotNil(copy.iconURL(for: "com.apple.finder"))
        XCTAssertNotNil(copy.rootResource("wallpaper.jpg"))
        XCTAssertNotNil(copy.rootResource("boot.mp4"))
    }

    /// The metal is lighter in the middle than at the ends, and pales when inactive.
    func testBrushedBarIsLitInTheMiddle() throws {
        func render(active: Bool) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 23, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            AquaChrome.brushedBar(NSRect(x: 0, y: 0, width: 400, height: 23), active: active, flipped: false)
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        func grey(_ r: NSBitmapImageRep, _ x: Int) -> CGFloat { r.colorAt(x: x, y: 11)!.usingColorSpace(.sRGB)!.redComponent }
        let on = render(active: true), off = render(active: false)
        XCTAssertGreaterThan(grey(on, 200), grey(on, 20) + 0.05)
        XCTAssertGreaterThan(grey(off, 20), grey(on, 20))
        if let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] {
            try on.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("tiger-titlebar.png"))
        }
    }
}
