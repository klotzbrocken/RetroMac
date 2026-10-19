import XCTest
@testable import RetroMac

/// The theme list RetroHub downloads: read as documented, plain-http downloads dropped, and a
/// theme that needs a newer RetroMac said so instead of installed.
final class ThemeCatalogTests: XCTestCase {
    func testEntryDecodes() throws {
        let json = """
        {"themes":[{"id":"com.example.t","name":"T","author":"A","summary":"S","era":"1993",
        "preview":"https://e.com/p.png","download":"https://e.com/t.zip","sha256":"ab","minAppVersion":"99.0"}]}
        """
        struct F: Decodable { let themes: [ThemeCatalog.Entry] }
        let e = try XCTUnwrap(JSONDecoder().decode(F.self, from: Data(json.utf8)).themes.first)
        XCTAssertEqual(e.id, "com.example.t")
        XCTAssertEqual(ThemeCatalog.needsNewerApp(e), "99.0")
    }

    func testShippedCatalogIsValid() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../catalog/themes.json").standardized
        struct F: Decodable { let themes: [ThemeCatalog.Entry] }
        let list = try JSONDecoder().decode(F.self, from: Data(contentsOf: url)).themes
        for e in list {
            XCTAssertEqual(e.download.scheme, "https", e.id)
            XCTAssertEqual(e.sha256.count, 64, e.id)
        }
    }
}
