import XCTest
@testable import RetroMac

/// Installing an imported theme used to `removeItem` the existing bundle and only then copy,
/// so a copy that failed for any reason destroyed a working theme. The install is now
/// copy-then-swap; these tests pin that down.
final class ThemeInstallTests: XCTestCase {

    private var root: URL!
    private var themesDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rm-install-\(UUID().uuidString)")
        themesDir = root.appendingPathComponent("Themes")
        try fm.createDirectory(at: themesDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    /// A minimal stand-in for a theme bundle: a directory with one marker file inside.
    @discardableResult
    private func makeBundle(_ name: String, marker: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("theme.json"), atomically: true, encoding: .utf8)
        return url
    }

    private func marker(of bundle: URL) -> String? {
        try? String(contentsOf: bundle.appendingPathComponent("theme.json"), encoding: .utf8)
    }

    private var stagingLeftovers: [URL] {
        let items = (try? fm.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.lastPathComponent.hasPrefix(".staging-") }
    }

    func testInstallingIntoAnEmptyDirectoryCreatesTheBundle() throws {
        let src = try makeBundle("Cool.retromactheme", marker: "v1", in: root)
        try ThemeManager.install(bundleAt: src, into: themesDir, replacing: nil)

        let dest = themesDir.appendingPathComponent("Cool.retromactheme")
        XCTAssertTrue(fm.fileExists(atPath: dest.path))
        XCTAssertEqual(marker(of: dest), "v1")
        XCTAssertTrue(stagingLeftovers.isEmpty, "staging directory was not cleaned up")
    }

    func testReinstallingReplacesTheContent() throws {
        let installed = try makeBundle("Cool.retromactheme", marker: "v1", in: themesDir)
        let src = try makeBundle("Cool.retromactheme", marker: "v2", in: root)

        try ThemeManager.install(bundleAt: src, into: themesDir, replacing: installed)

        XCTAssertEqual(marker(of: installed), "v2")
        XCTAssertTrue(stagingLeftovers.isEmpty)
    }

    /// The regression this refactor exists for.
    func testAFailedCopyLeavesTheInstalledThemeIntact() throws {
        let installed = try makeBundle("Cool.retromactheme", marker: "v1", in: themesDir)
        let missing = root.appendingPathComponent("DoesNotExist.retromactheme")

        XCTAssertThrowsError(try ThemeManager.install(bundleAt: missing, into: themesDir, replacing: installed))

        XCTAssertTrue(fm.fileExists(atPath: installed.path), "the working theme was destroyed by a failed import")
        XCTAssertEqual(marker(of: installed), "v1")
        XCTAssertTrue(stagingLeftovers.isEmpty, "a failed install left a staging directory behind")
    }

    /// `replacing:` is resolved from the theme id, so a renamed bundle updates the theme it *is*
    /// instead of landing beside it under a second file name.
    func testARenamedBundleReplacesTheThemeItWasResolvedTo() throws {
        let installed = try makeBundle("OldName.retromactheme", marker: "v1", in: themesDir)
        let src = try makeBundle("NewName.retromactheme", marker: "v2", in: root)

        try ThemeManager.install(bundleAt: src, into: themesDir, replacing: installed)

        XCTAssertEqual(marker(of: installed), "v2")
        XCTAssertFalse(fm.fileExists(atPath: themesDir.appendingPathComponent("NewName.retromactheme").path),
                       "the rename created a duplicate instead of replacing the installed theme")
    }

    /// Without a match, an unrelated theme that happens to share a file name is still overwritten
    /// by name — but only because the caller passed `replacing: nil` and the name collides. The
    /// point of this test is that the swap is still atomic and clean in that path.
    func testNameCollisionWithoutAMatchStillSwapsCleanly() throws {
        let installed = try makeBundle("Cool.retromactheme", marker: "v1", in: themesDir)
        let src = try makeBundle("Cool.retromactheme", marker: "v2", in: root)

        try ThemeManager.install(bundleAt: src, into: themesDir, replacing: nil)

        XCTAssertEqual(marker(of: installed), "v2")
        XCTAssertTrue(stagingLeftovers.isEmpty)
    }
}

/// Dock folder items carry a synthetic id built from an absolute path, so a shipped theme cannot
/// name the user's Downloads directly. `iconURL(for:)` folds the home directory to "~" — a
/// silent-no-op risk worth pinning, since a miss just falls back to the system folder icon.
final class FolderIconMappingTests: XCTestCase {

    /// The repo's shipped themes — `Bundle.main` points at the test runner, not the app.
    private var themesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes")
    }

    private func snowLeopard() throws -> ThemeBundle {
        try ThemeBundle(url: themesDir.appendingPathComponent("MacOSX-SnowLeopard.retromactheme"),
                        isBuiltIn: true)
    }

    func testDownloadsFolderResolvesThroughTheTildeForm() throws {
        let theme = try snowLeopard()
        let id = "__folder__" + NSHomeDirectory() + "/Downloads"
        let url = try XCTUnwrap(theme.iconURL(for: id), "the Downloads folder mapping did not resolve")
        XCTAssertEqual(url.lastPathComponent, "downloads.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAnUnmappedFolderStillReturnsNil() throws {
        let theme = try snowLeopard()
        XCTAssertNil(theme.iconURL(for: "__folder__" + NSHomeDirectory() + "/Music"))
    }

    /// Only paths inside the home directory fold; anything else must not be rewritten.
    func testFolderOutsideHomeIsNotFolded() throws {
        let theme = try snowLeopard()
        XCTAssertNil(theme.iconURL(for: "__folder__/Volumes/Extern/Downloads"))
    }

    func testTheNewAppMappingsPointAtFilesThatExist() throws {
        let theme = try snowLeopard()
        for id in ["com.google.Chrome", "com.apple.iWork.Numbers", "com.apple.iWork.Pages",
                   "com.apple.iWork.Keynote", "com.anthropic.claudefordesktop",
                   "com.openai.chat", "com.openai.codex"] {
            let url = try XCTUnwrap(theme.iconURL(for: id), "\(id) is not mapped")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(id) -> missing file")
        }
    }
}

/// An icon whose artwork sits inside a wide transparent margin renders visibly smaller than its
/// neighbours even though the file is the right size. That is invisible in review and only shows
/// up in the dock, so it is pinned here: the first pass at the new Snow Leopard icons shipped
/// Claude at 77% and ChatGPT at 75% while Safari and Mail measure 98%.
final class IconContentExtentTests: XCTestCase {

    private var iconsDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes/MacOSX-SnowLeopard.retromactheme/icons")
    }

    /// Longer side of the opaque bounding box, as a fraction of the canvas.
    private func contentExtent(_ url: URL) throws -> CGFloat {
        let img = try XCTUnwrap(NSImage(contentsOf: url), "unreadable: \(url.lastPathComponent)")
        let cg = try XCTUnwrap(img.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 24 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return 0 }
        return max(CGFloat(maxX - minX + 1) / CGFloat(w), CGFloat(maxY - minY + 1) / CGFloat(h))
    }

    func testNewIconsFillTheCanvasLikeTheShippedOnes() throws {
        // Safari, Mail and Preview sit at 97-98%; Finder, the loosest, at 91%.
        let floor: CGFloat = 0.88
        for name in ["chrome", "numbers", "pages", "keynote", "downloads", "claude", "chatgpt"] {
            let extent = try contentExtent(iconsDir.appendingPathComponent("\(name).png"))
            XCTAssertGreaterThanOrEqual(
                extent, floor,
                "\(name).png only fills \(Int(extent * 100))% of its canvas — it will look shrunken in the dock")
        }
    }

    func testTheReferenceIconsStillSetThatBar() throws {
        for name in ["safari", "mail", "preview_app"] {
            let extent = try contentExtent(iconsDir.appendingPathComponent("\(name).png"))
            XCTAssertGreaterThanOrEqual(extent, 0.90, "\(name).png is no longer a valid yardstick")
        }
    }
}
