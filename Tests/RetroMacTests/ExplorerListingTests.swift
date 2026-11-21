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
        let list = try XCTUnwrap(page.range(of: #"const PNG=new Set\(\[([^\]]*)\]"#, options: .regularExpression).map { String(page[$0]) })
        let roles = list.split(separator: "'").enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
        XCTAssertGreaterThan(roles.count, 20)
        for role in roles + ["exe"] {
            for size in [16, 32] {
                XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("icons/\(role)-\(size).png").path), "\(role)-\(size)")
            }
        }
    }
}
