import XCTest
@testable import RetroMac

/// Unit tests for `ThemeBundle.confinedResource` — theme resource paths must never escape the
/// bundle directory via `../` or a symlink (RetroMac is unsandboxed and imports untrusted themes).
final class ThemeBundlePathTests: XCTestCase {

    private var bundleDir: URL!
    private var outsideDir: URL!

    override func setUpWithError() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rmthemetest-\(UUID().uuidString)")
        bundleDir = tmp.appendingPathComponent("theme.retromactheme")
        outsideDir = tmp.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        // An in-bundle icon and a secret file outside the bundle.
        try Data([0x1]).write(to: bundleDir.appendingPathComponent("icon.png"))
        try Data([0x2]).write(to: outsideDir.appendingPathComponent("secret.png"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundleDir.deletingLastPathComponent())
    }

    func testInBundleFileAccepted() {
        let u = ThemeBundle.confinedResource("icon.png", under: bundleDir)
        XCTAssertNotNil(u)
        XCTAssertEqual(u?.lastPathComponent, "icon.png")
    }

    func testParentTraversalRejected() {
        XCTAssertNil(ThemeBundle.confinedResource("../outside/secret.png", under: bundleDir))
        XCTAssertNil(ThemeBundle.confinedResource("../../etc/hosts", under: bundleDir))
    }

    func testSymlinkEscapeRejected() throws {
        // A symlink inside the bundle pointing at a file outside it must be refused.
        let link = bundleDir.appendingPathComponent("escape.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideDir.appendingPathComponent("secret.png"))
        XCTAssertNil(ThemeBundle.confinedResource("escape.png", under: bundleDir))
    }

    func testMissingAndEmptyReturnNil() {
        XCTAssertNil(ThemeBundle.confinedResource("does-not-exist.png", under: bundleDir))
        XCTAssertNil(ThemeBundle.confinedResource(nil, under: bundleDir))
        XCTAssertNil(ThemeBundle.confinedResource("", under: bundleDir))
    }
}
