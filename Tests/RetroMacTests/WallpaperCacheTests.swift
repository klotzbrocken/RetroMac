import XCTest
@testable import RetroMac

/// The rendered-wallpaper cache is tidied without ever deleting a picture that may be on screen.
final class WallpaperCacheTests: XCTestCase {

    private typealias F = ThemeManager.CachedWallpaper
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private let mb = 1024 * 1024
    private func days(_ d: Double) -> Date { now.addingTimeInterval(-d * 24 * 3600) }

    func testLongUnusedFilesGo() {
        let files = [F(path: "/a", bytes: mb, lastUsed: days(20)), F(path: "/b", bytes: mb, lastUsed: days(3))]
        XCTAssertEqual(ThemeManager.wallpaperCacheVictims(files, inUse: [], now: now), ["/a"])
    }

    func testOverTheLimitTheLongestUnusedGoFirst() {
        let files = (0..<10).map { F(path: "/\($0)", bytes: 10 * mb, lastUsed: days(Double(2 + $0))) }   // 100 MB
        let victims = ThemeManager.wallpaperCacheVictims(files, inUse: [], now: now)
        XCTAssertEqual(Set(victims), ["/9", "/8", "/7", "/6"], "down to 60 MB, oldest first")
    }

    func testAPictureOnScreenOrUsedTodayStays() {
        let files = [F(path: "/shown", bytes: 90 * mb, lastUsed: days(40)),
                     F(path: "/today", bytes: 90 * mb, lastUsed: days(0.5))]
        XCTAssertTrue(ThemeManager.wallpaperCacheVictims(files, inUse: ["/shown"], now: now).isEmpty)
    }
}
