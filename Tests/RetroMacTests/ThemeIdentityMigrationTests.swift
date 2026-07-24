import XCTest
@testable import RetroMac

/// The one-time rewrite of theme-keyed defaults from display name to stable id. It runs before
/// `AppSettings` reads anything, exactly once, and must never lose a user's settings.
final class ThemeIdentityMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "rm-migration-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The repo's shipped themes — `Bundle.main` points at the test runner, not the app.
    private var themeDirs: [URL] {
        [URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes")]
    }

    private func migrate() {
        ThemeIdentityMigration.runIfNeeded(defaults: defaults, directories: themeDirs)
    }

    /// The real built-in themes provide the name→id map, so the fixtures use their names.
    private let win98Name = "Windows 98"
    private let win98ID   = "com.retromac.microsoft.windows98"
    private let xpName    = "Windows XP"
    private let xpID      = "com.retromac.microsoft.windowsxp"

    func testDictionaryKeysAreRewrittenToIDs() {
        defaults.set([win98Name: "crt-royale", xpName: ""], forKey: "themePresetOverrides")
        defaults.set([win98Name: true], forKey: "themeDockAutoHide")

        migrate()

        let presets = defaults.dictionary(forKey: "themePresetOverrides") as? [String: String]
        XCTAssertEqual(presets?[win98ID], "crt-royale")
        XCTAssertEqual(presets?[xpID], "")
        XCTAssertNil(presets?[win98Name], "the old name-keyed entry must be gone")

        let autohide = defaults.dictionary(forKey: "themeDockAutoHide") as? [String: Bool]
        XCTAssertEqual(autohide?[win98ID], true)
    }

    func testPrefixedKeysAreRenamed() {
        defaults.set(0.75, forKey: "iconScale_dock_\(win98Name)")
        defaults.set(Data([0xAB]), forKey: "desktopCustom.\(win98Name)")

        migrate()

        XCTAssertEqual(defaults.object(forKey: "iconScale_dock_\(win98ID)") as? Double, 0.75)
        XCTAssertNil(defaults.object(forKey: "iconScale_dock_\(win98Name)"))
        XCTAssertEqual(defaults.data(forKey: "desktopCustom.\(win98ID)"), Data([0xAB]))
        XCTAssertNil(defaults.object(forKey: "desktopCustom.\(win98Name)"))
    }

    func testStoredSelectionBecomesAnID() {
        defaults.set(win98Name, forKey: "dockTheme")
        migrate()
        XCTAssertEqual(defaults.string(forKey: "dockTheme"), win98ID)
        XCTAssertEqual(defaults.string(forKey: "dockThemeLegacyName"), win98Name)
    }

    func testLegacySelectorIsMappedThroughItsAlias() {
        // "Mac OS 9.2" no longer names any theme; it aliases to "Mac OS 9.2 Classic".
        defaults.set("Mac OS 9.2", forKey: "dockTheme")
        migrate()
        XCTAssertEqual(defaults.string(forKey: "dockTheme"), "com.retromac.apple.macos9")
    }

    func testUnknownKeysSurviveUntouched() {
        // A theme that isn't installed right now must NOT lose its settings.
        defaults.set(["Some Deleted Theme": "zfast-crt"], forKey: "themePresetOverrides")
        defaults.set("Some Deleted Theme", forKey: "dockTheme")

        migrate()

        let presets = defaults.dictionary(forKey: "themePresetOverrides") as? [String: String]
        XCTAssertEqual(presets?["Some Deleted Theme"], "zfast-crt")
        XCTAssertEqual(defaults.string(forKey: "dockTheme"), "Some Deleted Theme")
    }

    func testExistingIDEntryWinsOverTheNameEntry() {
        defaults.set([win98Name: "old", win98ID: "new"], forKey: "themePresetOverrides")
        migrate()
        let presets = defaults.dictionary(forKey: "themePresetOverrides") as? [String: String]
        XCTAssertEqual(presets?[win98ID], "new")
        XCTAssertNil(presets?[win98Name])
    }

    func testMigrationIsIdempotent() {
        defaults.set([win98Name: "crt-royale"], forKey: "themePresetOverrides")
        defaults.set(0.5, forKey: "iconScale_dock_\(win98Name)")
        defaults.set(win98Name, forKey: "dockTheme")

        migrate()
        let afterFirst = snapshot()

        // Running again (flag set) must be a no-op…
        migrate()
        XCTAssertEqual(snapshot(), afterFirst)

        // …and even a forced re-run must converge, because ids no longer match any name.
        defaults.removeObject(forKey: "themeSettingsKeyedByID_v1")
        migrate()
        XCTAssertEqual(snapshot(), afterFirst)
    }

    func testFlagIsSetSoItRunsOnlyOnce() {
        migrate()
        XCTAssertTrue(defaults.bool(forKey: "themeSettingsKeyedByID_v1"))
    }

    /// Everything the migration can touch, as one comparable value.
    private func snapshot() -> String {
        var parts: [String] = []
        for key in ["themePresetOverrides", "themeDockAutoHide", "dockTheme", "dockThemeLegacyName"] {
            parts.append("\(key)=\(String(describing: defaults.object(forKey: key)))")
        }
        parts.append("iconScale_dock_\(win98ID)=\(String(describing: defaults.object(forKey: "iconScale_dock_\(win98ID)")))")
        parts.append("iconScale_dock_\(win98Name)=\(String(describing: defaults.object(forKey: "iconScale_dock_\(win98Name)")))")
        return parts.sorted().joined(separator: "|")
    }
}
