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

/// macOS's wallpaper store, read for each Space's own picture before a theme sets one.
final class WallpaperStoreTests: XCTestCase {
    private func choice(_ path: String) throws -> [String: Any] {
        let config = try PropertyListSerialization.data(fromPropertyList: ["type": "imageFile", "url": ["relative": "file://" + path]],
                                                        format: .binary, options: 0)
        return ["Provider": "com.apple.wallpaper.choice.image", "Configuration": config, "Files": []]
    }

    func testEachSpaceKeepsItsOwnPicture() throws {
        func desktop(_ c: [String: Any]) -> [String: Any] { ["Desktop": ["Content": ["Choices": [c]]]] }
        let store: [String: Any] = ["Spaces": [
            "": ["Displays": ["DISP-A": desktop(try choice("/Users/me/Pictures/first.jpg"))]],
            "SPACE-2": ["Displays": ["DISP-A": desktop(try choice("/Applications/RetroMac.app/Contents/Resources/Themes/X/wp.jpg")),
                                     "DISP-B": desktop(try choice("/System/Library/Desktop%20Pictures/Sonoma.heic"))]],
            "SPACE-3": ["Displays": ["DISP-A": desktop(["Provider": "com.apple.wallpaper.choice.dynamic", "Configuration": Data()])]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
        let originals = WallpaperStore.originals(from: data) { $0.path.contains("/Themes/") }
        XCTAssertEqual(originals["DISP-A|"]?.path, "/Users/me/Pictures/first.jpg", "the first Space has the empty uuid")
        XCTAssertEqual(originals["DISP-B|SPACE-2"]?.path, "/System/Library/Desktop Pictures/Sonoma.heic")
        XCTAssertNil(originals["DISP-A|SPACE-2"], "one of ours is no original")
        XCTAssertNil(originals["DISP-A|SPACE-3"], "a dynamic wallpaper has no file to set back")
    }
}
