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
    }

    /// The bar sits above the window, so every bar style has the height of its era and the
    /// lights styles have none; every Windows and Mac chrome key resolves to a style.
    func testEveryWindowsAndMacChromeHasAStyle() {
        for key in ["macos6", "macos9", "win31", "win98", "winxp", "win7"] {
            let style = TitleBarOverlayController.style(for: key)
            XCTAssertEqual(style?.isBar, true, "\(key) should be a bar")
            XCTAssertGreaterThan(TitleBarOverlayController.stripHeight(style!), 0)
        }
        for key in ["macosx", "snowleopard"] {
            let style = TitleBarOverlayController.style(for: key)
            XCTAssertEqual(style?.isBar, false, "\(key) should be lights only")
            XCTAssertEqual(TitleBarOverlayController.stripHeight(style!), 0)
        }
        XCTAssertNil(TitleBarOverlayController.style(for: "beos"))
        XCTAssertEqual(TitleBarOverlayController.stripHeight(.platinum), 22, "Platinum's own height, nothing to cover any more")
    }

    /// The Platinum bar stands a point out on each side, on the hairline macOS draws round
    /// the window, so its frame line is flush with the window as seen; other bars, and the
    /// Platinum bar with the window border on, are exactly as wide as the window.
    func testPlatinumBarOverhangsTheHairline() {
        let bounds = CGRect(x: 100, y: 200, width: 400, height: 300)   // Quartz, top-left origin
        let plain = TitleBarOverlayController.barFrame(for: bounds, style: .platinum, overhang: 0)
        let out = TitleBarOverlayController.barFrame(for: bounds, style: .platinum, overhang: 1)
        XCTAssertEqual(out.minX, plain.minX - 1)
        XCTAssertEqual(out.width, plain.width + 2)
        XCTAssertEqual(out.height, 22)
        XCTAssertEqual(out.minY, plain.minY)
        XCTAssertEqual(TitleBarOverlayController.platinumOverhang(for: .luna), 0)
        XCTAssertEqual(TitleBarOverlayController.platinumOverhang(for: .win98), 0)
        let saved = AppSettings.shared.themeWindowBorders
        defer { AppSettings.shared.themeWindowBorders = saved }
        AppSettings.shared.themeWindowBorders = false
        XCTAssertEqual(TitleBarOverlayController.platinumOverhang(for: .platinum), 1)
        AppSettings.shared.themeWindowBorders = true
        XCTAssertEqual(TitleBarOverlayController.platinumOverhang(for: .platinum), 0, "the border covers the hairline")
    }
}

final class TitleBarCornerTests: XCTestCase {
    /// The Luna/Aero clip rounds the two top corners (flipped view: y = 0 is the top) and
    /// keeps the bottom square and the full width — the earlier angle-based arc lost the
    /// bar's right end.
    func testTopCornersClipKeepsWidthAndBottom() {
        let b = NSRect(x: 0, y: 0, width: 300, height: 30)
        let p = TitleBarOverlayView.topCorners(b, radius: 8)
        XCTAssertEqual(p.bounds, b)
        XCTAssertFalse(p.contains(NSPoint(x: 0.5, y: 0.5)))       // top-left corner cut
        XCTAssertFalse(p.contains(NSPoint(x: 299.5, y: 0.5)))     // top-right corner cut
        XCTAssertTrue(p.contains(NSPoint(x: 8, y: 0.5)))          // top edge past the corner
        XCTAssertTrue(p.contains(NSPoint(x: 0.5, y: 29.5)))       // bottom-left square
        XCTAssertTrue(p.contains(NSPoint(x: 299.5, y: 29.5)))     // bottom-right square
        XCTAssertTrue(p.contains(NSPoint(x: 299.5, y: 15)))       // right end present
    }
}

final class TitleBarCornerKeyTests: XCTestCase {
    /// The global corner key is asked for under bars only (0.5 = square); the lights leave the
    /// system's rounding alone, because the key masks every window an app opens after reading
    /// it, and Webex's received video did not survive that.
    func testCornerKeyOnlyForBars() {
        for style in TitleBarOverlayController.Style.allCases {
            XCTAssertEqual(TitleBarOverlayController.cornerRadius(for: style), style.isBar ? 0.5 : nil, "\(style)")
        }
    }
}

final class TitleBarCacheTests: XCTestCase {
    /// Only a title that was actually fetched is refreshed when its window comes forward; a
    /// failure entry keeps its backoff, and a window never asked about needs nothing.
    func testTitleRefreshOnlyForFetchedTitles() {
        XCTAssertTrue(TitleBarOverlayController.refreshesTitle("Untitled.rtf"))
        XCTAssertFalse(TitleBarOverlayController.refreshesTitle(nil))
    }

    func testBarCornerRadiusPerStyle() {
        XCTAssertEqual(TitleBarOverlayController.barCornerRadius(for: .luna), 8)
        XCTAssertEqual(TitleBarOverlayController.barCornerRadius(for: .aero), 6)
        XCTAssertEqual(TitleBarOverlayController.barCornerRadius(for: .win98), 0)
        XCTAssertEqual(TitleBarOverlayController.barCornerRadius(for: .platinum), 0)
    }

    /// The glass mask for Aero: rounded at the top, square at the bottom, stretchable in width.
    func testAeroGlassMaskShape() {
        let m = TitleBarOverlayView.topCornersMask(radius: 6, height: 30)
        XCTAssertEqual(m.capInsets.top, 6); XCTAssertEqual(m.capInsets.bottom, 0)
        let rep = NSBitmapImageRep(data: m.tiffRepresentation!)!
        let w = rep.pixelsWide, h = rep.pixelsHigh
        XCTAssertLessThan(rep.colorAt(x: 0, y: 0)!.alphaComponent, 0.5)          // top-left cut (bitmap y = 0 is the top)
        XCTAssertGreaterThan(rep.colorAt(x: 0, y: h - 1)!.alphaComponent, 0.5)   // bottom-left square
        XCTAssertGreaterThan(rep.colorAt(x: w / 2, y: 0)!.alphaComponent, 0.5)   // top edge between the corners
    }
}
