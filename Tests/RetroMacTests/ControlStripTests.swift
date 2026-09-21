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

    /// System 7.1 (authentic): the same strip, menus and desktop as Mac OS 9 (authentic), in 1 bit.
    func testSystem7ManifestMirrorsMacOS9InOneBit() throws {
        let t = try XCTUnwrap(theme("MacOS7-Authentic.retromactheme"), "the theme bundle loads")
        XCTAssertEqual(t.config.name, "System 7.1 (authentic)")
        XCTAssertTrue(t.config.isControlStripModules)
        XCTAssertTrue(t.config.hidesDock)
        XCTAssertTrue(t.config.hasApplicationMenu)
        XCTAssertTrue(t.config.hasAppleMenu)
        XCTAssertTrue(t.config.hasMonochromeMenus)
        XCTAssertEqual(t.config.menuBarAppleStyleDefault, 6, "the solid black apple")
        XCTAssertEqual(t.config.chrome?.style, "macos6", "the 1-bit title bars and frames")
        XCTAssertEqual(t.config.desktopIcons?.map { $0.name }, ["Macintosh HD", "Applications", "Trash"])
        XCTAssertEqual(t.config.desktopIconSize, 32)
        XCTAssertEqual(t.config.desktopLabel?.background, "#FFFFFF")
        XCTAssertNotNil(t.iconResource("controlstrip-left.png"))
        XCTAssertNotNil(t.iconResource("strip-volume.png"))
        XCTAssertNotNil(t.iconResource("computer.png"))
        let os9 = try XCTUnwrap(authenticTheme())
        XCTAssertEqual(t.config.desktopIconSize, os9.config.desktopIconSize, "size and behaviour come from Mac OS 9 (authentic)")
        XCTAssertEqual(t.config.dock.dockStyle, os9.config.dock.dockStyle)
        XCTAssertFalse(os9.config.hasMonochromeMenus)
        XCTAssertFalse(try XCTUnwrap(theme("MacOS6-Classic.retromactheme")).config.isControlStripModules, "System 6 stays as it was")
    }

    /// The 1-bit pass leaves only black, white and clear behind, at the pixel count asked for.
    func testOneBitIsBlackWhiteAndClear() {
        let src = NSImage(size: NSSize(width: 64, height: 64))
        src.lockFocus()
        NSColor(deviceRed: 0.1, green: 0.1, blue: 0.2, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 64, height: 32).fill()
        NSColor(deviceWhite: 0.95, alpha: 1).setFill(); NSRect(x: 0, y: 32, width: 64, height: 32).fill()
        src.unlockFocus()
        let bit = MonoArt.oneBit(src, points: 16, scale: 2)
        let rep = try! XCTUnwrap(bit.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, 32)
        var blacks = 0, whites = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            let c = rep.colorAt(x: x, y: y)!
            if c.alphaComponent < 0.5 { continue }
            XCTAssertTrue((c.redComponent == 0 || c.redComponent == 1) && c.redComponent == c.greenComponent && c.greenComponent == c.blueComponent, "only black and white")
            if c.redComponent == 0 { blacks += 1 } else { whites += 1 }
        } }
        XCTAssertGreaterThan(blacks, 0); XCTAssertGreaterThan(whites, 0, "the light half goes white, the dark half black")
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
        let mods: [ControlStripModule] = [ColourDepthModule(), NetworkModule(), SharingModule()]   // 20 pt each, plus the triangle's 8
        let all = view.modulesWidth(mods)
        XCTAssertEqual(all, (20 + 8) * 3 + 2 * 2)
        let full = view.preferredWidth(collapsed: false, visible: 0, modules: mods)
        XCTAssertEqual(full, view.tabWidth + 12 + 2 + all + 2 + 12 + view.sizeBoxWidth)
        XCTAssertEqual(view.preferredWidth(collapsed: false, visible: 30, modules: mods), full - (all - 30), "the size box shows a part")
        XCTAssertEqual(view.preferredWidth(collapsed: true, visible: 0, modules: mods), view.tabWidth)
    }

    /// The strip is 36 pt (1.5×) unless the setting says Small (1×) or Large (2×); half steps
    /// only, nothing below 1× or above 2×.
    func testScaleFollowsTheSetting() {
        XCTAssertEqual(ControlStripView.scale(for: 1), 1)
        XCTAssertEqual(ControlStripView.scale(for: 1.5), 1.5)
        XCTAssertEqual(ControlStripView.scale(for: 2), 2)
        XCTAssertEqual(ControlStripView.scale(for: 0.3), 1, "never smaller than 1×")
        XCTAssertEqual(ControlStripView.scale(for: 3), 2, "never larger than 2×")
        XCTAssertEqual(ControlStripView.scale(for: 1.3), 1.5, "half steps")
        let saved = AppSettings.shared.controlStripScale
        defer { AppSettings.shared.controlStripScale = saved }
        AppSettings.shared.controlStripScale = 1.5
        XCTAssertEqual(ControlStripView.height, 36)
        XCTAssertEqual(ControlStripView.windowWidth(100), 150)
        AppSettings.shared.controlStripScale = 2
        XCTAssertEqual(ControlStripView.height, 48)
    }

    func testVerticalPositionStaysOnScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let vf = screen.visibleFrame
        XCTAssertEqual(ControlStripController.clampedY(offset: -500, screen: screen), vf.minY)
        XCTAssertEqual(ControlStripController.clampedY(offset: 99999, screen: screen), vf.maxY - ControlStripView.height)
    }

    func testAvailabilityRules() {
        // Mirroring stays on the strip; its menu says when there is no second display.
        XCTAssertTrue(MirroringModule().isAvailable)
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
                    StripArt.speaker(level: 3), StripArt.battery(fraction: 0.5, charging: true),
                    KeychainModule.art, MediaBayModule.art, PrinterModule.art, SoundSourceModule.art] {
            XCTAssertEqual(art.count, 16)
            for row in art { XCTAssertEqual(row.count, 16) }
        }
    }
}
