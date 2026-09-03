import XCTest
@testable import RetroMac

/// Swapping the Vevo music channels for XITE's.
///
/// The delicate part is not the swap, it is everyone who already has their own channel list:
/// editing the built-in arrays reaches only a fresh install, and a migration that rewrites a
/// list people have curated has to leave everything it was not asked to touch exactly alone.
final class TVBookmarkMigrationTests: XCTestCase {

    private let vevo90 = "https://amg00056-vevotv-vevo90saunz-samsungau-n6a0d.amagi.tv/playlist/amg00056-vevotv-vevo90saunz-samsungau/playlist.m3u8"
    private let vevo80 = "https://amg00056-vevotv-vevo80saunz-samsungau-rp5e3.amagi.tv/playlist/amg00056-vevotv-vevo80saunz-samsungau/playlist.m3u8"
    private let vevo2k = "https://d1s6jz7jeei17.cloudfront.net/playlist/amg00056-vevotv-vevo2kau-samsungau/playlist.m3u8"
    private let vevoRock = "https://d2lyea6if8kkz9.cloudfront.net/playlist/amg00056-vevotv-vevoretrorockau-samsungau/playlist.m3u8"

    func testTheSwapKeepsPositionsAndDropsTheTwoWithNoSuccessor() {
        let before = [
            TVBookmark(name: "Mine", url: "https://example.com/a.m3u8"),
            TVBookmark(name: "VEVO 90s", url: vevo90, presetID: "joel-gdv-ntsc"),
            TVBookmark(name: "VEVO 2K", url: vevo2k),
            TVBookmark(name: "Also Mine", url: "https://example.com/b.m3u8"),
            TVBookmark(name: "VEVO Retro Rock", url: vevoRock),
            TVBookmark(name: "VEVO 80s", url: vevo80),
        ]
        let (after, changed) = AppSettings.applyingXiteSwap(to: before)
        XCTAssertTrue(changed)
        XCTAssertEqual(after.map(\.name),
                       ["Mine", "XITE 90s Throwback", "Also Mine", "XITE 80s Flashback"])
        XCTAssertEqual(after[1].url, AppSettings.xite90sURL)
        XCTAssertEqual(after[3].url, AppSettings.xite80sURL)
        // The preset the user had chosen for that slot belongs to the slot, not to Vevo.
        XCTAssertEqual(after[1].presetID, "joel-gdv-ntsc")
    }

    /// Somebody who renamed the channel, or already pointed it at a different stream, has made a
    /// decision. Matching on the URL rather than the name is what respects it.
    func testARenamedChannelIsStillSwappedButARepointedOneIsNot() {
        let renamed = TVBookmark(name: "Neunziger", url: vevo90)
        let repointed = TVBookmark(name: "VEVO 90s", url: "https://example.com/mine.m3u8")
        let (after, changed) = AppSettings.applyingXiteSwap(to: [renamed, repointed])
        XCTAssertTrue(changed)
        XCTAssertEqual(after[0].url, AppSettings.xite90sURL)
        XCTAssertEqual(after[1].url, "https://example.com/mine.m3u8", "a repointed channel is theirs")
        XCTAssertEqual(after[1].name, "VEVO 90s")
    }

    func testAListWithoutVevoIsReturnedUntouched() {
        let mine = [
            TVBookmark(name: "One", url: "https://example.com/1.m3u8"),
            TVBookmark(name: "Two", url: "https://example.com/2.m3u8"),
        ]
        let (after, changed) = AppSettings.applyingXiteSwap(to: mine)
        XCTAssertFalse(changed)
        XCTAssertEqual(after.map(\.url), mine.map(\.url))
    }

    /// The flag makes it run once, but running it twice must still be harmless.
    func testTheSwapIsIdempotent() {
        let once = AppSettings.applyingXiteSwap(to: [TVBookmark(name: "VEVO 80s", url: vevo80)]).list
        let twice = AppSettings.applyingXiteSwap(to: once)
        XCTAssertFalse(twice.changed)
        XCTAssertEqual(twice.list.map(\.url), once.map(\.url))
    }

    /// The 2.9 additions have to be reachable and distinct, and a redirector URL must be stored
    /// as the redirector: the playlists behind the two jmp2.uk addresses carry a 24-hour token,
    /// so storing a resolved URL would hand everyone a channel that dies tomorrow.
    func testTheNewStreamsAreInTheBuiltInListAndStayRedirectors() {
        let urls = AppSettings.defaultTVBookmarks.map(\.url)
        for b in AppSettings.newTVBookmarksV29 {
            XCTAssertTrue(urls.contains(b.url), "\(b.name) is missing from the built-in list")
            XCTAssertFalse(b.url.contains("authToken"), "\(b.name) stores a resolved, expiring URL")
            XCTAssertTrue(b.url.hasPrefix("https://"), "\(b.name) is not https")
        }
        XCTAssertEqual(Set(urls).count, urls.count, "a stream is in the built-in list twice")
        XCTAssertEqual(AppSettings.newTVBookmarksV29.count, 6)
    }

    /// A fresh install must not need the migration at all.
    func testTheBuiltInListHasNoVevoLeft() {
        let urls = AppSettings.defaultTVBookmarks.map(\.url)
        for gone in [vevo90, vevo80, vevo2k, vevoRock] {
            XCTAssertFalse(urls.contains(gone), "a Vevo stream is still in the built-in list")
        }
        XCTAssertTrue(urls.contains(AppSettings.xite90sURL))
        XCTAssertTrue(urls.contains(AppSettings.xite80sURL))
        // Vevo itself is not the problem and comes back in 2.9 on working links; what must not
        // survive is the four dead amagi.tv/cloudfront addresses checked above.
        let vevo = AppSettings.defaultTVBookmarks.filter { $0.name.lowercased().contains("vevo") }
        XCTAssertEqual(vevo.count, 3, "expected the three restored Vevo channels")
        for b in vevo {
            XCTAssertTrue(b.url.hasPrefix("https://jmp2.uk/"), "\(b.name) is back on a dead link")
        }
    }
}
