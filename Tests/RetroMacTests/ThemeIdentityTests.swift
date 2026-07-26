import XCTest
@testable import RetroMac

/// Manifest 2.0 identity: a theme's `id` — not its renameable display name — is what the stored
/// selection and every per-theme setting key off. These tests pin the rules that make that safe.
final class ThemeIdentityTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rmidtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Write a valid theme.json into a fresh bundle directory. Built by encoding a real config so
    /// the fixture can never drift out of sync with `DockThemeConfig`'s required fields.
    @discardableResult
    private func makeTheme(dir: String, name: String, id: String? = nil) throws -> URL {
        let url = root.appendingPathComponent("\(dir).retromactheme")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var cfg = DockThemeConfig(name: name,
                                  dock: .init(),
                                  icon: .init(),
                                  indicator: .init(),
                                  iconMappings: [:])
        cfg.id = id
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cfg).write(to: url.appendingPathComponent("theme.json"))
        return url
    }

    // MARK: - id validation

    func testValidIDsAccepted() {
        for id in ["com.retromac.microsoft.windows98", "legacy.my-theme.a1b2c3d4", "user.x.0", "a"] {
            XCTAssertTrue(ThemeBundle.isValidID(id), "should accept \(id)")
        }
    }

    func testInvalidIDsRejected() {
        // Uppercase, spaces, path separators, empty, and dot edges are all unusable as a
        // permanent, non-localised key.
        for id in ["", "Windows 98", "com.retromac.Windows", "a/b", ".leading", "trailing.",
                   "double..dot", "emoji🙂", String(repeating: "a", count: 129)] {
            XCTAssertFalse(ThemeBundle.isValidID(id), "should reject \(id)")
        }
    }

    func testMalformedDeclaredIDFallsBackToLegacyID() throws {
        // A broken id must not make the theme unloadable — it is treated as "no id".
        let url = try makeTheme(dir: "Broken", name: "Broken Theme", id: "NOT VALID")
        let bundle = try ThemeBundle(url: url, isBuiltIn: true)
        XCTAssertTrue(bundle.stableID.hasPrefix("legacy.broken-theme."))
        XCTAssertTrue(ThemeBundle.isValidID(bundle.stableID))
    }

    // MARK: - legacy id generation

    func testLegacyIDIsDeterministicAndSlugged() {
        let manifest = Data("{\"name\":\"Mac OS 9.2\"}".utf8)
        let a = ThemeBundle.legacyID(name: "Mac OS 9.2", manifest: manifest)
        let b = ThemeBundle.legacyID(name: "Mac OS 9.2", manifest: manifest)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("legacy.mac-os-9-2."))
        XCTAssertTrue(ThemeBundle.isValidID(a))
    }

    func testSameNameDifferentContentGetDifferentLegacyIDs() {
        // Two imported themes may share a display name — the fingerprint keeps them apart.
        let a = ThemeBundle.legacyID(name: "Retro", manifest: Data("{\"a\":1}".utf8))
        let b = ThemeBundle.legacyID(name: "Retro", manifest: Data("{\"a\":2}".utf8))
        XCTAssertNotEqual(a, b)
    }

    /// The whole point of writing the generated id into the manifest: editing the theme afterwards
    /// must NOT move its identity, or the user silently loses every per-theme setting.
    func testGeneratedIDIsPersistedAndSurvivesAnEdit() throws {
        let url = try makeTheme(dir: "Legacy", name: "My Legacy Theme")
        let first = try ThemeBundle(url: url, isBuiltIn: false)
        XCTAssertTrue(first.stableID.hasPrefix("legacy.my-legacy-theme."))

        // It landed in the manifest…
        let onDisk = try Data(contentsOf: url.appendingPathComponent("theme.json"))
        XCTAssertTrue(String(decoding: onDisk, as: UTF8.self).contains(first.stableID))

        // …and reloading yields the same id.
        XCTAssertEqual(try ThemeBundle(url: url, isBuiltIn: false).stableID, first.stableID)

        // Now edit the theme (rename it). The id must not follow the name.
        var cfg = first.config
        cfg.name = "Renamed Theme"
        try first.save(config: cfg)
        let afterEdit = try ThemeBundle(url: url, isBuiltIn: false)
        XCTAssertEqual(afterEdit.stableID, first.stableID)
        XCTAssertEqual(afterEdit.name, "Renamed Theme")
    }

    func testBuiltInIsNotWrittenTo() throws {
        let url = try makeTheme(dir: "BuiltIn", name: "Built In")
        let before = try Data(contentsOf: url.appendingPathComponent("theme.json"))
        _ = try ThemeBundle(url: url, isBuiltIn: true)
        let after = try Data(contentsOf: url.appendingPathComponent("theme.json"))
        XCTAssertEqual(before, after, "a built-in bundle must never be modified on load")
    }

    // MARK: - resolution

    func testTwoThemesWithTheSameNameDoNotCollide() throws {
        let a = try ThemeBundle(url: try makeTheme(dir: "A", name: "Retro", id: "com.example.a"),
                                isBuiltIn: true)
        let b = try ThemeBundle(url: try makeTheme(dir: "B", name: "Retro", id: "com.example.b"),
                                isBuiltIn: true)
        XCTAssertNotEqual(a.stableID, b.stableID)
        XCTAssertEqual(ThemeManager.resolve("com.example.a", in: [a, b])?.stableID, a.stableID)
        XCTAssertEqual(ThemeManager.resolve("com.example.b", in: [a, b])?.stableID, b.stableID)
    }

    func testIDWinsOverName() throws {
        // A theme whose display NAME equals another theme's id must not steal its selection.
        let victim = try ThemeBundle(url: try makeTheme(dir: "V", name: "Victim", id: "com.example.target"),
                                     isBuiltIn: true)
        let impostor = try ThemeBundle(url: try makeTheme(dir: "I", name: "com.example.target",
                                                          id: "com.example.impostor"), isBuiltIn: true)
        XCTAssertEqual(ThemeManager.resolve("com.example.target", in: [impostor, victim])?.stableID,
                       victim.stableID)
    }

    func testDisplayNameStillResolvesForPreManifestSelections() throws {
        let t = try ThemeBundle(url: try makeTheme(dir: "T", name: "Windows 98",
                                                   id: "com.retromac.microsoft.windows98"), isBuiltIn: true)
        XCTAssertEqual(ThemeManager.resolve("Windows 98", in: [t])?.stableID, t.stableID)
    }

    func testLegacySelectorAliasResolves() throws {
        let t = try ThemeBundle(url: try makeTheme(dir: "T", name: "Mac OS 9.2 Classic",
                                                   id: "com.retromac.apple.macos9"), isBuiltIn: true)
        XCTAssertEqual(ThemeManager.resolve("Mac OS 9.2", in: [t])?.stableID, t.stableID)
    }

    // MARK: - built-in manifests

    /// Every shipped theme must declare the SAME chrome the old display-name heuristic produced,
    /// otherwise Manifest 2.0 silently restyles windows, widgets and the TV frame.
    func testBuiltInThemesDeclareTheChromeTheHeuristicWouldPick() throws {
        let themesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes")
        let bundles = try FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "retromactheme" }
        XCTAssertFalse(bundles.isEmpty, "no built-in themes found at \(themesDir.path)")

        var seenIDs = Set<String>()
        for url in bundles {
            let bundle = try ThemeBundle(url: url, isBuiltIn: true)
            let cfg = bundle.config

            XCTAssertEqual(cfg.schemaVersion, 2, "\(cfg.name) should be a Manifest 2.0 theme")
            let id = try XCTUnwrap(cfg.id, "\(cfg.name) has no id")
            XCTAssertTrue(ThemeBundle.isValidID(id), "\(cfg.name) has an invalid id: \(id)")
            XCTAssertTrue(seenIDs.insert(id).inserted, "duplicate built-in id: \(id)")
            XCTAssertNotNil(cfg.family, "\(cfg.name) has no family")

            let declared = try XCTUnwrap(cfg.chrome?.style, "\(cfg.name) declares no chrome.style")
            XCTAssertEqual(declared, RetroFrameTheme.legacyKeyFromName(cfg.name),
                           "\(cfg.name): declared chrome must match the pre-2.0 heuristic")
        }
    }
}
