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
