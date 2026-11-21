import XCTest
@testable import RetroMac

/// Start ▸ Run… (after retro98's RunTarget): Windows commands, URLs, web addresses, paths and
/// app names, in that order.
final class RunTargetTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rm-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Utilities/Café Löwe.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Calculator.app"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testResolveOrder() {
        let roots = [root!]
        XCTAssertNil(RunTarget.resolve("   ", appRoots: roots))
        XCTAssertEqual(RunTarget.resolve("notepad.exe", appRoots: roots), .command("notepad"))
        XCTAssertEqual(RunTarget.resolve("CMD", appRoots: roots), .command("terminal"))
        XCTAssertEqual(RunTarget.resolve("https://example.com", appRoots: roots), .url(URL(string: "https://example.com")!))
        XCTAssertEqual(RunTarget.resolve("www.example.com", appRoots: roots), .url(URL(string: "https://www.example.com")!))
        XCTAssertEqual(RunTarget.resolve("calculator", appRoots: roots)?.appPath, root.appendingPathComponent("Calculator.app").path)
        XCTAssertEqual(RunTarget.resolve("cafe lowe.app", appRoots: roots)?.isApp, true, "case and accents do not matter, subfolders are searched")
        XCTAssertEqual(RunTarget.resolve("/no/such/thing", appRoots: roots), .notFound("/no/such/thing"))
        XCTAssertEqual(RunTarget.resolve("nothing-like-it", appRoots: roots), .notFound("nothing-like-it"))
    }
}

private extension RunTarget {
    var isApp: Bool { if case .app = self { return true }; return false }
    var appPath: String? { if case .app(let u) = self { return u.path }; return nil }
}
