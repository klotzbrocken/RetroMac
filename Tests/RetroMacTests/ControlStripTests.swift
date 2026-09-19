import XCTest
import AppKit
@testable import RetroMac

/// The Mac OS 9 (authentic) theme and its Control Strip, in the parts that need no window.
final class ControlStripTests: XCTestCase {

    private static let themesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Themes")
    private func theme(_ folder: String) -> ThemeBundle? {
        try? ThemeBundle(url: Self.themesDir.appendingPathComponent(folder), isBuiltIn: true)
    }
    private func authenticTheme() -> ThemeBundle? {
        do { return try ThemeBundle(url: Self.themesDir.appendingPathComponent("MacOS9-Authentic.retromactheme"), isBuiltIn: true) }
        catch { XCTFail("\(error)"); return nil }
    }

    func testManifestDeclaresStripAndApplicationMenuAndNoDock() throws {
        let t = try XCTUnwrap(authenticTheme(), "the theme bundle loads")
        XCTAssertTrue(t.config.isControlStripModules)
        XCTAssertTrue(t.config.hidesDock, "no DockView for this theme")
        XCTAssertTrue(t.config.hasApplicationMenu)
        XCTAssertEqual(t.config.chrome?.style, "macos9", "Platinum bars and frames come with the chrome key")
        XCTAssertEqual(t.config.desktopIcons?.map { $0.name }, ["Macintosh HD", "Applications", "Trash"])
        XCTAssertNotNil(t.iconResource("controlstrip-left.png"))
        XCTAssertNotNil(t.iconResource("controlstrip-right.png"))
    }

    func testClassicThemeIsUntouched() throws {
        let t = try XCTUnwrap(theme("MacOS9-Classic.retromactheme"))
        XCTAssertTrue(t.config.isControlStrip)
        XCTAssertFalse(t.config.isControlStripModules)
        XCTAssertFalse(t.config.hidesDock)
        XCTAssertFalse(t.config.hasApplicationMenu)
    }

    /// Width comes from the modules on show, never from apps; collapsed is the tab alone.
    func testStripWidthFromModules() throws {
        let t = try XCTUnwrap(authenticTheme())
        let view = ControlStripView(theme: t, controller: ControlStripController.shared)
        let mods: [ControlStripModule] = [ColourDepthModule(), NetworkModule(), SharingModule()]   // 20 pt each
        let all = view.modulesWidth(mods)
        XCTAssertEqual(all, 20 * 3 + 2 * 2)
        let full = view.preferredWidth(collapsed: false, visible: 0, modules: mods)
        XCTAssertEqual(full, view.tabWidth + 12 + 2 + all + 2 + 12 + view.sizeBoxWidth)
        XCTAssertEqual(view.preferredWidth(collapsed: false, visible: 30, modules: mods), full - (all - 30), "the size box shows a part")
        XCTAssertEqual(view.preferredWidth(collapsed: true, visible: 0, modules: mods), view.tabWidth)
    }

    func testVerticalPositionStaysOnScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let vf = screen.visibleFrame
        XCTAssertEqual(ControlStripController.clampedY(offset: -500, screen: screen), vf.minY)
        XCTAssertEqual(ControlStripController.clampedY(offset: 99999, screen: screen), vf.maxY - ControlStripView.height)
    }

    func testAvailabilityRules() {
        // Mirroring needs a second display; on a one-display machine it hides.
        XCTAssertEqual(MirroringModule().isAvailable, MirroringModule.displayCount() >= 2)
        // The battery hides where there is none.
        let b = BatteryModule(); b.refresh()
        XCTAssertEqual(b.isAvailable, BatteryModule.read().0 != nil)
    }

    func testResolutionModesDedupedAndSortedLargestFirst() {
        let display = CGMainDisplayID()
        guard let all = CGDisplayCopyAllDisplayModes(display, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] else { return }
        let offered = ResolutionModule.offeredModes(all)
        let sizes = offered.map { "\($0.width)x\($0.height)" }
        XCTAssertEqual(sizes.count, Set(sizes).count, "one entry per size")
        XCTAssertEqual(offered.map { ($0.width, $0.height) }.map { $0.0 * 100000 + $0.1 }, offered.map { $0.width * 100000 + $0.height }.sorted(by: >))
    }

    func testApplicationMenuRows() {
        let rows = ApplicationMenuController.rows(apps: [("Finder", false), ("TextEdit", false), ("Mail", true)], front: "TextEdit")
        XCTAssertEqual(rows.map { $0.title }, ["Hide TextEdit", "Hide Others", "Show All", "", "Finder", "TextEdit", "Mail"])
        XCTAssertEqual(rows.map { $0.ticked }, [false, false, false, false, false, true, false])
        XCTAssertEqual(rows.map { $0.dimmed }, [false, false, false, false, false, false, true])
        XCTAssertTrue(rows[3].separator)
    }

    func testPixelArtIsSixteenSquare() {
        for art in [StripArt.network, StripArt.sharing, StripArt.colours, StripArt.monitor, StripArt.mirroring,
                    StripArt.speaker(level: 3), StripArt.battery(fraction: 0.5, charging: true)] {
            XCTAssertEqual(art.count, 16)
            for row in art { XCTAssertEqual(row.count, 16) }
        }
    }
}
