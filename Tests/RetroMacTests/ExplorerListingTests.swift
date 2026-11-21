import XCTest
@testable import RetroMac

/// The Explorer's drives and window icons, and the icons its page asks for.
final class ExplorerListingTests: XCTestCase {
    func testDriveKinds() {
        XCTAssertEqual(ExplorerListing.driveKind(typeName: "apfs", isLocal: true, isRemovable: false).icon, "drive")
        XCTAssertEqual(ExplorerListing.driveKind(typeName: "cd9660", isLocal: true, isRemovable: true).icon, "cd")
        XCTAssertEqual(ExplorerListing.driveKind(typeName: "udf", isLocal: true, isRemovable: true).icon, "cd")
        // An external disk is ejectable too, and was shown as a CD-ROM.
        XCTAssertEqual(ExplorerListing.driveKind(typeName: "exfat", isLocal: true, isRemovable: true).icon, "removable")
        XCTAssertEqual(ExplorerListing.driveKind(typeName: "smbfs", isLocal: false, isRemovable: false).icon, "netdrive")
    }

    func testSpecialFolderRoles() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(ExplorerListing.role(home.appendingPathComponent("Documents")), "mydocs")
        XCTAssertEqual(ExplorerListing.role(URL(fileURLWithPath: "/Applications")), "programs")
        XCTAssertEqual(ExplorerListing.role(home.appendingPathComponent("Music")), "folderopen")
    }

    /// Every icon the page names exists at both sizes.
    func testPageIconsExist() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Resources/Widgets/Explorer")
        let page = try String(contentsOf: dir.appendingPathComponent("Explorer.html"), encoding: .utf8)
        func roles(_ name: String) throws -> [String] {
            let list = try XCTUnwrap(page.range(of: "const \(name)=new Set\\(\\[([^\\]]*)\\]", options: .regularExpression).map { String(page[$0]) })
            return list.split(separator: "'").enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
        }
        let win98 = try roles("PNG"), xp = try roles("PNGXP"), toolbar = try roles("TBXP")
        XCTAssertGreaterThan(win98.count, 20)
        XCTAssertGreaterThan(xp.count, 12)
        for (folder, list) in [("icons", win98 + ["exe"]), ("icons/xp", xp + ["exe"])] {
            for role in list {
                for size in [16, 32] {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(folder)/\(role)-\(size).png").path), "\(folder)/\(role)-\(size)")
                }
            }
        }
        for name in toolbar.map({ "icons/xp/tb-\($0)-24.png" }) + ["icons/tb98.png", "icons/tb98-gray.png"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path), name)
        }
    }
}
