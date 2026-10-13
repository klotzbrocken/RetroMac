import XCTest
import ScreenSaver
@testable import RetroMac

/// The Windows 3D savers ship as native .saver modules (vendor/retro-screensavers, built by
/// Scripts/build-savers.sh); each loads, names a ScreenSaverView and draws.
final class NativeSaverTests: XCTestCase {
    @MainActor
    func testEveryNativeSaverLoadsAndAnimates() throws {
        let savers = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Savers")
        for (id, name) in ScreensaverController.nativeBundles {
            let bundle = try XCTUnwrap(Bundle(url: savers.appendingPathComponent("\(name).saver")), id)
            XCTAssertTrue(bundle.load(), id)
            let type = try XCTUnwrap(bundle.principalClass as? ScreenSaverView.Type, id)
            let view = try XCTUnwrap(type.init(frame: NSRect(x: 0, y: 0, width: 320, height: 200), isPreview: true), id)
            view.startAnimation()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            view.stopAnimation()
            XCTAssertTrue(ScreensaverController.available.contains { $0.id == id }, "\(id) in the picker")
        }
    }
}
