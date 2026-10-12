import XCTest
@testable import RetroMac

/// "What this theme changes on your Mac" and "Restore my settings".
final class SystemChangesTests: XCTestCase {
    private func macOS9() throws -> ThemeBundle {
        try ThemeBundle(url: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Themes/MacOS9-Authentic.retromactheme"), isBuiltIn: true)
    }

    func testTheListReadsYoursAgainstTheThemes() throws {
        let theme = try macOS9()
        var on = ThemeSystemChanges.Switches()
        on.appearance = true; on.finderTweaks = true
        let mine: [String: Any] = ["com.apple.finder\tFXPreferredViewStyle": "clmv", "-g\tAppleInterfaceStyle": "Dark",
                                   "-g\tAppleAccentColor": NSNumber(value: 4)]
        let list = ThemeSystemChanges.list(for: theme.config, isBuiltIn: true, switches: on, hasCursors: false,
                                           terminalProfile: nil, current: { mine[$0 + "\t" + $1] })
        func row(_ what: String) -> ThemeSystemChanges.Change? { list.first { $0.what == what } }
        XCTAssertEqual(row("Mac Dock"), .init(what: "Mac Dock", before: "Shown", after: "Hidden"))
        XCTAssertEqual(row("Finder view"), .init(what: "Finder view", before: "Columns", after: "List"))
        XCTAssertEqual(row("Appearance"), .init(what: "Appearance", before: "Dark", after: "Light"))
        XCTAssertEqual(row("Accent colour"), .init(what: "Accent colour", before: "Blue", after: "Graphite"))
        XCTAssertEqual(row("Finder status bar")?.before, "macOS default")
        XCTAssertEqual(row("Finder status bar")?.after, "On")
        XCTAssertNil(row("Pointer"), "Match cursor is off")
    }

    func testSwitchesOffMeanFewerChanges() throws {
        let list = ThemeSystemChanges.list(for: try macOS9().config, isBuiltIn: true, switches: .init(),
                                           hasCursors: true, terminalProfile: "RetroMac Mac", current: { _, _ in nil })
        XCTAssertEqual(list.map(\.what), ["Mac Dock", "Wallpaper"])
    }

    /// "Keep my wallpaper": the theme's page does not promise to change the picture.
    func testKeepingMyWallpaperLeavesItOffTheList() throws {
        var sw = ThemeSystemChanges.Switches(); sw.ownWallpaper = true
        let list = ThemeSystemChanges.list(for: try macOS9().config, isBuiltIn: true, switches: sw,
                                           hasCursors: true, terminalProfile: nil, current: { _, _ in nil })
        XCTAssertEqual(list.map(\.what), ["Mac Dock"])
    }

    func testAnImportedThemeChangesNoFinderSettings() throws {
        var on = ThemeSystemChanges.Switches(); on.finderTweaks = true
        let list = ThemeSystemChanges.list(for: try macOS9().config, isBuiltIn: false, switches: on,
                                           hasCursors: false, terminalProfile: nil, current: { _, _ in nil })
        XCTAssertNil(list.first { $0.what == "Finder view" })
    }

    func testRememberedValuesGoBackWithTheirType() {
        XCTAssertEqual(OriginalSettings.writeArguments("com.apple.finder", "ShowPathbar", kCFBooleanTrue),
                       ["write", "com.apple.finder", "ShowPathbar", "-bool", "true"])
        XCTAssertEqual(OriginalSettings.writeArguments("-g", "NSTableViewDefaultSizeMode", NSNumber(value: 2)),
                       ["write", "-g", "NSTableViewDefaultSizeMode", "-int", "2"])
        XCTAssertEqual(OriginalSettings.writeArguments("-g", "NSConvolutionOverride1", NSNumber(value: 4.5)),
                       ["write", "-g", "NSConvolutionOverride1", "-float", "4.5"])
        XCTAssertEqual(OriginalSettings.writeArguments("com.apple.dock", "mineffect", "genie"),
                       ["write", "com.apple.dock", "mineffect", "-string", "genie"])
        XCTAssertEqual(OriginalSettings.writeArguments("com.apple.dock", "orientation", nil),
                       ["delete", "com.apple.dock", "orientation"], "unset before: deleted again")
        XCTAssertNil(OriginalSettings.writeArguments("com.apple.dock", "persistent-apps", [1, 2]))
    }
}
