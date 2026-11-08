import XCTest
@testable import RetroMac

/// About This Mac (10.0) and About This Computer (9.0): sized as the originals, the processor
/// without Intel's trademark clutter. With RETROMAC_SNAPSHOT_DIR set both are drawn to
/// about-macosx.png and about-macos9.png.
final class ClassicAboutTests: XCTestCase {
    @MainActor
    func testWindowsAreTheOriginalsSize() throws {
        XCTAssertEqual(ClassicAbout.makeView(.macOSX).frame.size, NSSize(width: 267, height: 314))
        XCTAssertEqual(ClassicAbout.makeView(.macOS9).frame.size, NSSize(width: 479, height: 281))
        XCTAssertFalse(ClassicAbout.processor.contains("(R)"))
        XCTAssertFalse(ClassicAbout.processor.isEmpty)
        XCTAssertEqual(ClassicAbout.memoryList().first?.name, "macOS")

        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"] else { return }
        for (kind, name) in [(ClassicAbout.macOSX, "about-macosx.png"), (.macOS9, "about-macos9.png")] {
            let view = ClassicAbout.makeView(kind)
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }
}
