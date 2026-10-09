import XCTest
import AVFoundation
@testable import RetroMac

/// Boot screens fill the display when their shape is close to it, and keep bars when it is not.
final class SplashFillTests: XCTestCase {
    private let macBook = NSSize(width: 1470, height: 956)   // 16:10-ish built-in display

    func testA16by9ClipFillsA16by10Display() throws {
        let r = try XCTUnwrap(SplashController.aspectFillRect(content: NSSize(width: 1920, height: 1080), in: macBook))
        XCTAssertEqual(r.height, macBook.height, accuracy: 0.5)       // full height
        XCTAssertEqual(r.midX, macBook.width / 2, accuracy: 0.5)      // cut evenly at both sides
        XCTAssertLessThan((r.width - macBook.width) / 2 / r.width, 0.08)
    }

    func testA4by3ClipKeepsItsBars() {
        XCTAssertNil(SplashController.aspectFillRect(content: NSSize(width: 640, height: 480), in: macBook))
        XCTAssertNil(SplashController.aspectFillRect(content: NSSize(width: 640, height: 480), in: NSSize(width: 1920, height: 1080)))
    }

    /// The widened Windows 95 and Me boot screens and the uncropped Mac OS 9 clip are in the bundles.
    func testTheWidenedBootScreensAreWide() throws {
        let themes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Themes")
        let me = try XCTUnwrap(NSImage(contentsOf: themes.appendingPathComponent("WindowsMe.retromactheme/boot.gif")))
        XCTAssertGreaterThan(me.size.width / me.size.height, 1.7)
        for clip in ["Windows95.retromactheme/boot.mp4", "MacOS9-Classic.retromactheme/boot.mp4"] {
            let track = try XCTUnwrap(AVURLAsset(url: themes.appendingPathComponent(clip)).tracks(withMediaType: .video).first)
            XCTAssertNotNil(SplashController.aspectFillRect(content: track.naturalSize, in: macBook), clip)
        }
    }
}
