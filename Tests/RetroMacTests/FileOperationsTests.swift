import XCTest
@testable import RetroMac

/// The file windows' operations (after retro98's FilesCore): nothing is ever written over, and
/// every change can be taken back. All in a temporary folder, with a Trash of its own.
final class FileOperationsTests: XCTestCase {
    private var root: URL!
    private var trash: URL!
    private var ops = FileOperations()
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rm-fileops-\(UUID().uuidString)")
        trash = root.appendingPathComponent("Trash")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        let t = trash!
        ops.moveToTrash = { url in
            let target = t.appendingPathComponent(FileNames.available(url.lastPathComponent, isFolder: false,
                                                                      existing: FileOperations.names(in: t)))
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func file(_ path: String, _ text: String = "x") throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private func folder(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testCopyNamesFollowTheFinder() {
        let u = URL(fileURLWithPath: "/x/photo.jpg")
        XCTAssertEqual(FileNames.copyName(for: u, isFolder: false, existing: []), "photo copy.jpg")
        XCTAssertEqual(FileNames.copyName(for: u, isFolder: false, existing: ["photo copy.jpg", "PHOTO COPY 2.JPG"]), "photo copy 3.jpg")
        XCTAssertEqual(FileNames.copyName(for: URL(fileURLWithPath: "/x/v1.2"), isFolder: true, existing: []), "v1.2 copy")
        XCTAssertEqual(FileNames.available("New Folder", isFolder: true, existing: ["new folder"]), "New Folder 2")
    }

    func testCopyIntoTheSameFolderMakesACopyAndUndoTrashesIt() throws {
        let a = try file("A/note.txt", "hello")
        let out = ops.transfer(.copy, [a], to: a.deletingLastPathComponent(), control: OperationControl(), resolve: { _ in .cancel }, progress: { _ in })
        XCTAssertNil(out.failure)
        let copy = root.appendingPathComponent("A/note copy.txt")
        XCTAssertEqual(text(copy), "hello")
        let undone = ops.revert(out.changes, control: OperationControl())
        XCTAssertNil(undone.failure)
        XCTAssertFalse(fm.fileExists(atPath: copy.path))
        XCTAssertEqual(text(a), "hello", "the original stays")
    }

    func testReplaceSendsTheOldItemToTheTrashAndUndoBringsItBack() throws {
        let src = try file("A/note.txt", "new")
        let old = try file("B/note.txt", "old")
        var asked = 0
        let out = ops.transfer(.copy, [src], to: old.deletingLastPathComponent(), control: OperationControl(),
                               resolve: { _ in asked += 1; return .replace }, progress: { _ in })
        XCTAssertNil(out.failure); XCTAssertEqual(asked, 1)
        XCTAssertEqual(text(old), "new")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: trash.path).count, 1, "the replaced item went to the Trash")
        _ = ops.revert(out.changes, control: OperationControl())
        XCTAssertEqual(text(old), "old", "undo puts the replaced item back")
    }

    func testSkipAndCancelLeaveTheExistingItem() throws {
        let src = try file("A/note.txt", "new")
        let old = try file("B/note.txt", "old")
        for choice in [ConflictChoice.skip, .cancel] {
            let out = ops.transfer(.copy, [src], to: old.deletingLastPathComponent(), control: OperationControl(), resolve: { _ in choice }, progress: { _ in })
            XCTAssertTrue(out.changes.isEmpty)
            XCTAssertEqual(text(old), "old")
        }
    }

    func testMoveIntoItselfIsRefused() throws {
        let f = try folder("F")
        let inner = try folder("F/Inner")
        let out = ops.transfer(.move, [f], to: inner, control: OperationControl(), resolve: { _ in .cancel }, progress: { _ in })
        XCTAssertEqual(out.failure, .intoItself(f))
        XCTAssertTrue(fm.fileExists(atPath: inner.path))
    }

    /// A folder dropped on a Dock stack of its own subfolder: a plain copyItem copied it into
    /// its own copy, level after level, until the path grew too long.
    func testCopyIntoItselfIsRefused() throws {
        let f = try folder("Documents")
        let inbox = try folder("Documents/Inbox")
        let out = ops.transfer(.copy, [f], to: inbox, control: OperationControl(), resolve: { _ in .cancel }, progress: { _ in })
        XCTAssertEqual(out.failure, .intoItself(f))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: inbox.path), [])
    }

    /// The game and ROM imports skip a file that is already where it would go, else removing
    /// the "old" one first erases the only copy. Another letter case is the same file here.
    func testTheSameFileIsRecognisedWhateverCaseSpellsIt() throws {
        let wad = try file("Games/doom.wad")
        XCTAssertTrue(FileOperations.sameFolder(wad, root.appendingPathComponent("Games/DOOM.WAD")))
        XCTAssertFalse(FileOperations.sameFolder(wad, try file("Games/doom2.wad")))
    }

    func testMoveRenameAndNewFolderAreUndoneInOrder() throws {
        let a = try file("A/doc.txt", "d")
        let b = try folder("B")
        let moved = ops.transfer(.move, [a], to: b, control: OperationControl(), resolve: { _ in .cancel }, progress: { _ in })
        let at = b.appendingPathComponent("doc.txt")
        XCTAssertEqual(moved.results, [at])
        let renamed = ops.rename(at, to: "Doc.txt")
        XCTAssertNil(renamed.failure, "a change of case alone works")
        let made = ops.newFolder(in: b, base: "New Folder")
        XCTAssertEqual(made.results.first?.lastPathComponent, "New Folder")
        for step in [made, renamed, moved] { XCTAssertNil(ops.revert(step.changes, control: OperationControl()).failure) }
        XCTAssertEqual(text(a), "d", "everything is back where it started")
        XCTAssertFalse(fm.fileExists(atPath: b.appendingPathComponent("New Folder").path))
    }

    func testTrashIsUndoable() throws {
        let a = try file("A/gone.txt", "g")
        let out = ops.trash([a], control: OperationControl(), progress: { _ in })
        XCTAssertFalse(fm.fileExists(atPath: a.path))
        _ = ops.revert(out.changes, control: OperationControl())
        XCTAssertEqual(text(a), "g")
    }

    func testRenameRules() {
        XCTAssertEqual(RenameRules.check(original: "a.txt", typed: " a.txt ", isFolder: false), .unchanged)
        XCTAssertEqual(RenameRules.check(original: "a.txt", typed: "b.txt", isFolder: false), .accept("b.txt"))
        XCTAssertEqual(RenameRules.check(original: "a.txt", typed: "b.md", isFolder: false), .confirmExtensionChange(from: ".txt", to: ".md"))
        if case .invalid = RenameRules.check(original: "a", typed: "x/y", isFolder: true) {} else { XCTFail("a slash is refused") }
    }
}
