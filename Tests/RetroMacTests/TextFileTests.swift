import XCTest
@testable import RetroMac

/// Notepad's text files (after retro98): what came in goes back out the same way.
final class TextFileTests: XCTestCase {
    func testLineEndingsAndBOMSurviveARoundTrip() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("one\r\ntwo\r\nthree".utf8)
        var f = try TextFile.decode(data)
        XCTAssertEqual(f.text, "one\ntwo\nthree")
        XCTAssertEqual(f.lineEnding, .crlf)
        XCTAssertTrue(f.hasBOM)
        XCTAssertEqual(f.encoded(), data)
        f.text += "\nfour"
        XCTAssertEqual(f.encoded(), Data([0xEF, 0xBB, 0xBF]) + Data("one\r\ntwo\r\nthree\r\nfour".utf8))
    }

    func testOldWindowsFilesStayWindows1252() throws {
        let data = Data([0x47, 0x72, 0xFC, 0xDF, 0x65])   // "Grüße" in Windows-1252
        let f = try TextFile.decode(data)
        XCTAssertEqual(f.text, "Grüße")
        XCTAssertEqual(f.encoding, .windowsCP1252)
        XCTAssertEqual(f.encoded(), data)
    }

    func testBinaryIsRefused() {
        XCTAssertThrowsError(try TextFile.decode(Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x14]))) { XCTAssertEqual($0 as? TextFileError, .notText) }
    }

    func testWriteReplacesWithAFinishedCopy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rm-text-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("note.txt")
        try TextFile(text: "first").write(to: url)
        var f = try TextFile.read(from: url)
        f.text = "second"
        try f.write(to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second")
    }
}
