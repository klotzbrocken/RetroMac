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

    /// System 7.1 (authentic): the Mac OS 9 (authentic) desktop in 256 colours, with the
    /// PowerBook's own seven strip modules and its own window style.
    func testSystem7ManifestMirrorsMacOS9InFourGreys() throws {
        let t = try XCTUnwrap(theme("MacOS7-Authentic.retromactheme"), "the theme bundle loads")
        XCTAssertEqual(t.config.name, "System 7.1 (authentic)")
        XCTAssertTrue(t.config.isControlStripModules)
        XCTAssertTrue(t.config.hidesDock)
        XCTAssertTrue(t.config.hasApplicationMenu)
        XCTAssertTrue(t.config.hasAppleMenu)
        XCTAssertTrue(t.config.hasMac256Palette, "the theme draws in the Mac's 256 colours")
        XCTAssertTrue(t.config.applicationMenuIsIconOnly, "System 7.1 showed the icon alone")
        XCTAssertTrue(t.config.hasBalloonHelp)
        XCTAssertEqual(t.config.menuBarAppleStyleDefault, 1, "the rainbow apple of a colour Mac")
        XCTAssertEqual(t.config.chrome?.style, "system7", "its own window style")
        XCTAssertEqual(t.config.desktopIcons?.map { $0.name }, ["Macintosh HD", "Volumes", "Applications", "Trash"])
        XCTAssertEqual(t.config.desktopIcons?.last?.gridY, -1, "the Trash sits on the bottom row, whatever the screen")
        XCTAssertEqual(t.config.desktopIconSize, 32)
        XCTAssertEqual(t.config.desktopLabel?.background, "#FFFFFF")
        XCTAssertNotNil(t.iconResource("controlstrip-left.png"))
        XCTAssertNotNil(t.iconResource("computer.png"))

        let os9 = try XCTUnwrap(authenticTheme())
        // The strip is the PowerBook 150's, drawn by RetroMac: no borrowed Platinum pictures.
        for name in ["strip-volume.png", "strip-arrow-left.png", "strip-arrow-right.png"] {
            XCTAssertNil(t.iconResource(name), "\(name): the PowerBook strip draws its own")
        }
        XCTAssertEqual(t.config.desktopIconSize, os9.config.desktopIconSize, "size and behaviour come from Mac OS 9 (authentic)")
        XCTAssertEqual(t.config.dock.dockStyle, os9.config.dock.dockStyle)
        XCTAssertFalse(os9.config.hasMac256Palette)
        XCTAssertNil(os9.config.stripModuleIDs, "Mac OS 9 (authentic) keeps every module")
        XCTAssertFalse(try XCTUnwrap(theme("MacOS6-Classic.retromactheme")).config.isControlStripModules, "System 6 stays as it was")
    }

    /// The System 7.5 colour strip's pieces: 24 rows each, the modules' buttons 31 px with
    /// their line, every character one of the strip's colours (or a space beside the tab).
    func testSystem7StripArtIsTheOriginalsPieces() {
        let allowed = Set(System7Strip.ink.keys).union([" "])
        for id in ["appletalk", "sharing", "colours", "resolution", "volume"] {
            let m = ControlStripController.makeModule(id)!
            let art = System7Strip.cell(for: m)
            XCTAssertEqual(art?.count, System7Strip.height, id)
            XCTAssertTrue(art?.allSatisfy { $0.count == System7Strip.cellWidth && Set($0).isSubset(of: allowed) } ?? false, id)
        }
        for level in 0...3 { XCTAssertEqual(System7Strip.sound(level: level).count, System7Strip.height) }
        XCTAssertNotEqual(System7Strip.sound(level: 0), System7Strip.sound(level: 2), "the waves follow the volume")
        XCTAssertNotEqual(System7Strip.fileSharing, System7Strip.fileSharingOn, "off is crossed out, on is not")
        for piece in [System7Strip.closeBox, System7Strip.tab, System7Strip.blankCell,
                      System7Strip.arrow(pointsLeft: true, enabled: false), System7Strip.arrow(pointsLeft: false, enabled: true)] {
            XCTAssertEqual(piece.count, System7Strip.height)
            XCTAssertTrue(piece.allSatisfy { Set($0).isSubset(of: allowed) })
        }
        XCTAssertNil(System7Strip.cell(for: ControlStripController.makeModule("battery")!), "not on the colour strip")
    }

    /// The five modules of the System 7.5 colour strip, in its order, and nothing else.
    func testSystem7StripHasTheColourStripModules() throws {
        let t = try XCTUnwrap(theme("MacOS7-Authentic.retromactheme"))
        let ids = try XCTUnwrap(t.config.stripModuleIDs)
        XCTAssertEqual(ids, ["appletalk", "sharing", "colours", "resolution", "volume"])
        let built = ids.compactMap { ControlStripController.makeModule($0)?.id }
        XCTAssertEqual(built, ["network", "sharing", "colours", "resolution", "volume"])
        XCTAssertNil(ControlStripController.makeModule("nonesuch"), "an unknown id is skipped, not guessed at")
    }

    /// The Mac's standard 8-bit table: 256 different colours, the cube, the four ramps and
    /// black; an icon comes out at the pixel count asked for, every pixel one of them, and
    /// its mask all or nothing.
    func testMac256IsTheStandardTableAndIconsKeepToIt() throws {
        let table = Mac256.palette.map { Int($0.r) << 16 | Int($0.g) << 8 | Int($0.b) }
        XCTAssertEqual(table.count, 256)
        XCTAssertEqual(Set(table).count, 256, "no colour twice")
        XCTAssertEqual(table.first, 0xFFFFFF, "white first, as the table starts")
        XCTAssertEqual(table.last, 0x000000, "black last")
        for grey in [0xEEEEEE, 0xDDDDDD, 0xBBBBBB, 0xAAAAAA, 0x888888, 0x777777, 0x555555, 0x444444, 0x222222, 0x111111, 0xCCCCFF] {
            XCTAssertTrue(table.contains(grey), String(grey, radix: 16))
        }
        for c in Mac256.palette { XCTAssertTrue(Mac256.snap(c.r, c.g, c.b) == c, "a table colour stays itself") }

        // A 64 px picture: a colour ramp across, half transparent at the bottom.
        let src = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<64 { for x in 0..<64 {
            src.setColor(NSColor(deviceRed: CGFloat(x) / 63, green: CGFloat(y) / 63, blue: 0.4, alpha: y < 48 ? 1 : 0.2), atX: x, y: y)
        } }
        let img = NSImage(size: NSSize(width: 64, height: 64)); img.addRepresentation(src)
        let out = Mac256.icon(img, points: 16, scale: 2)
        let rep = try XCTUnwrap(out.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, 32)
        let allowed = Set(table)
        var opaque = 0, clear = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            let c = try XCTUnwrap(rep.colorAt(x: x, y: y))
            let a = Int((c.alphaComponent * 255).rounded())
            XCTAssertTrue(a == 0 || a == 255, "a 1-bit mask")
            if a == 0 { clear += 1; continue }
            opaque += 1
            let v = Int((c.redComponent * 255).rounded()) << 16 | Int((c.greenComponent * 255).rounded()) << 8 | Int((c.blueComponent * 255).rounded())
            XCTAssertTrue(allowed.contains(v), String(v, radix: 16))
        } }
        XCTAssertGreaterThan(opaque, 0); XCTAssertGreaterThan(clear, 0)
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
