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

    /// System 7.1 (authentic): the Mac OS 9 (authentic) desktop in the four greys, with the
    /// PowerBook's own seven strip modules and its own window style.
    func testSystem7ManifestMirrorsMacOS9InFourGreys() throws {
        let t = try XCTUnwrap(theme("MacOS7-Authentic.retromactheme"), "the theme bundle loads")
        XCTAssertEqual(t.config.name, "System 7.1 (authentic)")
        XCTAssertTrue(t.config.isControlStripModules)
        XCTAssertTrue(t.config.hidesDock)
        XCTAssertTrue(t.config.hasApplicationMenu)
        XCTAssertTrue(t.config.hasAppleMenu)
        XCTAssertTrue(t.config.hasFourGreys, "every theme surface is limited to the four greys")
        XCTAssertTrue(t.config.applicationMenuIsIconOnly, "System 7.1 showed the icon alone")
        XCTAssertTrue(t.config.hasBalloonHelp)
        XCTAssertEqual(t.config.menuBarAppleStyleDefault, 6, "the solid black apple")
        XCTAssertEqual(t.config.chrome?.style, "system7", "its own window style")
        XCTAssertEqual(t.config.desktopIcons?.map { $0.name }, ["Macintosh HD", "Volumes", "Applications", "Trash"])
        XCTAssertEqual(t.config.desktopIcons?.last?.gridY, -1, "the Trash sits on the bottom row, whatever the screen")
        XCTAssertEqual(t.config.desktopIconSize, 32)
        XCTAssertEqual(t.config.desktopLabel?.background, "#FFFFFF")
        XCTAssertNotNil(t.iconResource("controlstrip-left.png"))
        XCTAssertNotNil(t.iconResource("computer.png"))

        let os9 = try XCTUnwrap(authenticTheme())
        // The strip wears Mac OS 9 (authentic)'s pictures, shown in grey.
        for name in ["strip-volume.png", "strip-arrow-left.png", "strip-arrow-right.png"] {
            let mine = try XCTUnwrap(t.iconResource(name).flatMap { try? Data(contentsOf: $0) }, name)
            let theirs = try XCTUnwrap(os9.iconResource(name).flatMap { try? Data(contentsOf: $0) }, name)
            XCTAssertEqual(mine, theirs, "\(name) is Mac OS 9 (authentic)'s own")
        }
        XCTAssertEqual(t.config.desktopIconSize, os9.config.desktopIconSize, "size and behaviour come from Mac OS 9 (authentic)")
        XCTAssertEqual(t.config.dock.dockStyle, os9.config.dock.dockStyle)
        XCTAssertFalse(os9.config.hasFourGreys)
        XCTAssertNil(os9.config.stripModuleIDs, "Mac OS 9 (authentic) keeps every module")
        XCTAssertFalse(try XCTUnwrap(theme("MacOS6-Classic.retromactheme")).config.isControlStripModules, "System 6 stays as it was")
    }

    /// The seven modules a PowerBook's strip had, in its order, and none of the Mac OS 9 ones.
    func testSystem7StripHasThePowerBookModules() throws {
        let t = try XCTUnwrap(theme("MacOS7-Authentic.retromactheme"))
        let ids = try XCTUnwrap(t.config.stripModuleIDs)
        XCTAssertEqual(ids, ["appletalk", "battery", "sharing", "hdspindown", "power", "sleep", "volume"])
        let built = ids.compactMap { ControlStripController.makeModule($0)?.id }
        XCTAssertEqual(built, ["network", "battery", "sharing", "hdspindown", "power", "sleep", "volume"])
        for gone in ["keychain", "mediabay", "colours", "resolution", "printer", "soundsource", "mirroring"] {
            XCTAssertFalse(built.contains(gone), "\(gone) was not on a System 7 strip")
        }
        XCTAssertNil(ControlStripController.makeModule("nonesuch"), "an unknown id is skipped, not guessed at")
    }

    /// Nothing leaves the four greys, at the pixel count asked for, and a picture with four
    /// tones lands on all four rather than collapsing to black and white.
    func testFourGreysAreTheOnlyColoursLeft() throws {
        let src = NSImage(size: NSSize(width: 64, height: 64))
        src.lockFocus()
        let bands: [NSColor] = [NSColor(deviceWhite: 0.02, alpha: 1),
                                NSColor(deviceWhite: 0.33, alpha: 1),
                                NSColor(deviceWhite: 0.68, alpha: 1),
                                NSColor(deviceWhite: 0.98, alpha: 1)]
        for (i, c) in bands.enumerated() {
            c.setFill()
            NSRect(x: 0, y: CGFloat(i) * 16, width: 64, height: 16).fill()
        }
        src.unlockFocus()

        let out = FourGrays.quantize(src, points: 16, scale: 2)
        let rep = try XCTUnwrap(out.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, 32)
        let allowed: Set<Int> = [0, 0x55, 0xAA, 0xFF]
        var seen = Set<Int>()
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let c = try XCTUnwrap(rep.colorAt(x: x, y: y))
                if c.alphaComponent < 0.5 { continue }
                let v = Int((c.redComponent * 255).rounded())
                XCTAssertTrue(allowed.contains(v), "\(v) is not one of the four greys")
                let isGrey = abs(c.redComponent - c.greenComponent) < 0.001 && abs(c.greenComponent - c.blueComponent) < 0.001
                XCTAssertTrue(isGrey, "grey, never a colour")
                seen.insert(v)
            }
        }
        XCTAssertEqual(seen, allowed, "all four are used, none is dithered away")
        XCTAssertEqual(FourGrays.snap(0.0), FourGrays.black)
        XCTAssertEqual(FourGrays.snap(0.36), FourGrays.dark)
        XCTAssertEqual(FourGrays.snap(0.62), FourGrays.light)
        XCTAssertEqual(FourGrays.snap(1.0), FourGrays.white)
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
