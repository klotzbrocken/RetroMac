import XCTest
import AppKit
@testable import RetroMac

/// The pieces of the title-bar overlay that can be checked without a window: title bounds,
/// zoom bookkeeping, the plain/unified title bar threshold, and the lights geometry.
final class TitleBarOverlayTests: XCTestCase {

    func testPlatinumPlaqueNeverExceedsItsRoom() {
        let font = ChromeStyleFactory.macClassic().titleFont
        let long = "Bildschirmfoto 2026-09-15 um 13.39.42 — Kopie der Kopie der Kopie.png"
        XCTAssertGreaterThan(ClassicMacChrome.plaqueWidth(long, font: font, maxWidth: nil), 200)
        XCTAssertLessThanOrEqual(ClassicMacChrome.plaqueWidth(long, font: font, maxWidth: 120), 120)
        XCTAssertEqual(ClassicMacChrome.plaqueWidth("Hi", font: font, maxWidth: 120),
                       ClassicMacChrome.plaqueWidth("Hi", font: font, maxWidth: nil), "a short title is not touched")
    }

    func testZoomRestoreToleratesAnAppThatRefusedPartOfTheSize() {
        // The app was asked for 1920x1050 and gave 1200x1050 (a max width); that is now "zoomed".
        let reached = CGRect(x: 0, y: 30, width: 1200, height: 1050)
        XCTAssertTrue(TitleBarOverlayController.roughlySame(reached, reached.offsetBy(dx: 1, dy: -1)))
        XCTAssertFalse(TitleBarOverlayController.roughlySame(reached, CGRect(x: 0, y: 30, width: 1920, height: 1050)),
                       "the requested size is no measure of the zoomed state")
    }

    func testLightsPanelWrapsTheThreeLightsWithAir() {
        let offsets: [ChromeButtonKind: CGRect] = [
            .close: CGRect(x: 8, y: 8, width: 16, height: 16),
            .minimize: CGRect(x: 31, y: 8, width: 16, height: 16),
            .zoom: CGRect(x: 54, y: 8, width: 16, height: 16),
        ]
        let (frame, lights) = TitleBarOverlayController.lightsFrame(for: CGRect(x: 100, y: 100, width: 600, height: 400), offsets: offsets)
        XCTAssertEqual(lights.count, 3)
        for r in lights.values {
            XCTAssertEqual(r.width, TitleBarOverlayController.lightDiameter)
            XCTAssertTrue(NSRect(origin: .zero, size: frame.size).contains(r), "every orb lies inside the panel")
        }
        // The orb is centred on the real light (16 pt centre), so it covers it on every side.
        XCTAssertEqual(lights[.close]!.midX + frame.minX - 100, 16, accuracy: 0.01)
        // A unified toolbar puts the lights lower; that is what the bar styles key on.
        XCTAssertLessThan(offsets[.close]!.midY, TitleBarOverlayController.plainTitleBarLightCentre)
        XCTAssertGreaterThan(CGRect(x: 8, y: 16, width: 16, height: 16).midY, TitleBarOverlayController.plainTitleBarLightCentre)
    }

    func testTrafficLightStyleNeedsNoStripAndBarStylesDo() {
        XCTAssertEqual(TitleBarOverlayController.stripHeight(.snowLights), 0)
        XCTAssertEqual(TitleBarOverlayController.stripHeight(.platinumCloseOnly), 0)
        XCTAssertGreaterThanOrEqual(TitleBarOverlayController.stripHeight(.platinum), 28, "must cover the native 28 pt bar")
        XCTAssertGreaterThanOrEqual(TitleBarOverlayController.stripHeight(.luna), 28)
    }
}
