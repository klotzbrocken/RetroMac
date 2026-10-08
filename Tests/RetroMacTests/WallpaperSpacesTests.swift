import XCTest
@testable import RetroMac

/// The wallpaper backup is kept per screen and Space: macOS sets a desktop picture only on the
/// Space a screen shows, so every Space has an original of its own.
final class WallpaperSpacesTests: XCTestCase {
    private let mine = URL(fileURLWithPath: "/Users/me/Pictures/mine.jpg")
    private let other = URL(fileURLWithPath: "/Users/me/Pictures/other.jpg")

    func testTheKeyIsScreenAndSpace() {
        XCTAssertEqual(WallpaperSpaces.key(screen: "S1", space: "A"), "S1|A")
        XCTAssertEqual(WallpaperSpaces.key(screen: "S1", space: ""), "S1|")   // a first desktop without a uuid
        XCTAssertEqual(WallpaperSpaces.key(screen: "S1", space: nil), "S1")   // the window server said nothing
    }

    func testASpaceFindsItsOwnOriginalBeforeTheScreensOld() {
        let saved = ["S1|A": mine, "S1": other]
        XCTAssertEqual(WallpaperSpaces.original(for: "S1|A", in: saved), mine)
        XCTAssertEqual(WallpaperSpaces.original(for: "S1|B", in: saved), other)   // an older build's backup stands in
        XCTAssertNil(WallpaperSpaces.original(for: "S2|A", in: saved))
    }

    func testBackupsOfSpacesThatAreGoneAreDropped() {
        let saved = ["S1|A": mine, "S1|B": other, "S1": other, "S2|": mine]
        let kept = WallpaperSpaces.pruned(saved, liveSpaces: ["A", ""])
        XCTAssertEqual(Set(kept.keys), ["S1|A", "S1", "S2|"])
    }

    func testPendingCountsSpacesOnly() {
        XCTAssertEqual(WallpaperSpaces.pendingSpaces(in: ["S1|A": mine, "S1|B": other, "S1": other]), 2)
    }
}
