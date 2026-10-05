import XCTest
@testable import RetroMac

/// Historic icon packages (Lastenheft 3.0, section 9): what is accepted, what is turned away, what
/// an import keeps, and which picture a size gets.
final class IconPackTests: XCTestCase {
    typealias E = IconPackManifest.Entry
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("iconpack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png("ok-32.png", 32, alpha: true)
        try png("ok-32@2x.png", 64, alpha: true)
        try png("flat-32.png", 32, alpha: false)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func png(_ name: String, _ px: Int, alpha: Bool) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: alpha ? 4 : 3, hasAlpha: alpha, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
    }

    private func entry(_ app: String, _ bundle: String, files: [(String, Int, Int)] = [("ok-32.png", 32, 1), ("ok-32@2x.png", 32, 2)],
                       kind: IconPackManifest.Kind = .eraAdaptation, ref: String = "Stiladaption",
                       status: IconPackManifest.UsageStatus = .released) -> E {
        E(appID: app, bundleIDs: [bundle], kind: kind, referenceVersion: ref, usageStatus: status, source: "Test",
          variants: files.map { .init(file: $0.0, size: $0.1, scale: $0.2) }, checksum: nil)
    }

    private func check(_ entries: [E]) -> (valid: [E], invalid: [IconImportReport.Problem]) {
        IconPackStore.validate(IconPackManifest(format: 1, themeID: "t", source: nil, icons: entries), in: dir)
    }

    func testAGoodIconComesInWithItsChecksum() {
        let r = check([entry("claude", "com.anthropic.claudefordesktop")])
        XCTAssertEqual(r.valid.count, 1)
        XCTAssertEqual(r.valid.first?.checksum?.count, 64)
        XCTAssertTrue(r.invalid.isEmpty)
    }

    /// ICO-A2: a broken entry is reported with its reason; the others still come in.
    func testFaultsAreNamed() {
        let r = check([
            entry("ok", "com.example.ok"),
            entry("missing", "com.example.a", files: [("nope.png", 32, 1)]),
            entry("size", "com.example.b", files: [("ok-32.png", 16, 1)]),
            entry("flat", "com.example.c", files: [("flat-32.png", 32, 1)]),
            entry("escape", "com.example.d", files: [("../ok-32.png", 32, 1)]),
            entry("name", "Microsoft Word"),
            entry("twice", "com.example.ok"),
            entry("claim", "com.example.e", kind: .eraAdaptation, ref: "Solaris 8"),
        ])
        XCTAssertEqual(r.valid.map(\.appID), ["ok"])
        let why = Dictionary(uniqueKeysWithValues: r.invalid.map { ($0.appID, $0.reason) })
        XCTAssertTrue(why["missing"]!.contains("missing"))
        XCTAssertTrue(why["size"]!.contains("declared"))
        XCTAssertTrue(why["flat"]!.contains("alpha"))
        XCTAssertTrue(why["escape"]!.contains("leaves"))
        XCTAssertTrue(why["name"]!.contains("bundle IDs"), "ICO-08: names are no bundle IDs")
        XCTAssertTrue(why["twice"]!.contains("another app"))
        XCTAssertTrue(why["claim"]!.contains("Stiladaption"), "ICO-02: an adaptation is not an original")
    }

    func testAnOriginalMayNameItsVersion() {
        XCTAssertEqual(check([entry("calc", "com.apple.calculator", kind: .historicalOriginal, ref: "Mac OS 9.2")]).valid.count, 1)
    }

    /// ICO-10: a faulty new icon leaves the working old one in place; a good one replaces it.
    func testAnImportKeepsWhatWorked() {
        let old = [entry("claude", "com.anthropic.claudefordesktop"), entry("word", "com.microsoft.Word")]
        let new = entry("word", "com.microsoft.Word", ref: "Stiladaption 2")
        let (entries, report) = IconPackStore.merge(installed: old, valid: [new],
                                                    invalid: [.init(appID: "claude", reason: "missing")])
        XCTAssertEqual(entries.map(\.appID), ["claude", "word"])
        XCTAssertEqual(entries.first { $0.appID == "word" }?.referenceVersion, "Stiladaption 2")
        XCTAssertEqual(report.kept, ["claude"])
        XCTAssertEqual(report.accepted, ["word"])
    }

    func testNotForReleaseIsCheckedButNotTaken() {
        let (entries, _) = IconPackStore.merge(installed: [], valid: [entry("x", "com.example.x", status: .notForRelease)], invalid: [])
        XCTAssertTrue(entries.isEmpty)
    }

    /// ICO-06: an exact size wins; a 48 is not shrunk to 16 when a 16 is there.
    func testTheNearestSizeIsTaken() {
        let v: [IconPackManifest.Variant] = [.init(file: "16", size: 16, scale: 1), .init(file: "16@2x", size: 16, scale: 2),
                                             .init(file: "48", size: 48, scale: 1)]
        XCTAssertEqual(IconPackStore.pick(v, for: 16).map(\.file), ["16", "16@2x"])
        XCTAssertEqual(IconPackStore.pick(v, for: 32).map(\.file), ["48"])
        XCTAssertEqual(IconPackStore.pick(v, for: 64).map(\.file), ["48"])
    }

    /// The working catalogue (ICO-03) names every app once and gives no bundle ID to two apps.
    func testTheCatalogue() {
        let apps = IconCatalog.apps
        XCTAssertGreaterThanOrEqual(apps.count, 45)
        XCTAssertEqual(Set(apps.map(\.appID)).count, apps.count)
        let ids = apps.flatMap(\.bundleIDs)
        XCTAssertEqual(Set(ids).count, ids.count, "one bundle ID, one app (ICO-09)")
        XCTAssertNil(apps.first { $0.appID == "codex" }, "no Codex until a standalone app is found")
        for a in apps { XCTAssertTrue(Set(a.verified).isSubset(of: a.bundleIDs), a.appID) }
    }

    /// ICO-A1/A5 end to end: an imported package is read off the main thread and then drawn at
    /// its 1× and 2× sizes; a second import with a broken file keeps the working icon (ICO-A2).
    func testImportThenDraw() throws {
        let root = dir.appendingPathComponent("store")
        IconPackStore.rootForTests = root
        defer { IconPackStore.rootForTests = nil }
        let manifest = IconPackManifest(format: 1, themeID: "test.theme", source: "Test", icons: [entry("claude", "com.anthropic.claudefordesktop")])
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("icons.json"))
        let store = IconPackStore.shared
        XCTAssertThrowsError(try store.importPackage(at: dir, themes: ["other"]))
        let report = try store.importPackage(at: dir, themes: ["test.theme"])
        XCTAssertEqual(report.accepted, ["claude"])
        XCTAssertNil(store.image(themeID: "test.theme", bundleID: "com.anthropic.claudefordesktop", size: 32), "still being read")
        let ready = expectation(description: "decoded")
        DispatchQueue.global().async {
            while store.image(themeID: "test.theme", bundleID: "com.anthropic.claudefordesktop", size: 32) == nil { usleep(20_000) }
            ready.fulfill()
        }
        wait(for: [ready], timeout: 5)
        let img = store.image(themeID: "test.theme", bundleID: "com.anthropic.claudefordesktop", size: 32)
        XCTAssertEqual(img?.representations.map(\.pixelsWide).sorted(), [32, 64], "1× and 2×")
        XCTAssertNil(store.image(themeID: "test.theme", bundleID: "com.example.unknown", size: 32), "ICO-A3: no stand-in for an unknown app")

        let broken = IconPackManifest(format: 1, themeID: "test.theme", source: "Test",
                                      icons: [entry("claude", "com.anthropic.claudefordesktop", files: [("gone.png", 32, 1)])])
        try JSONEncoder().encode(broken).write(to: dir.appendingPathComponent("icons.json"))
        let second = try store.importPackage(at: dir, themes: ["test.theme"])
        XCTAssertEqual(second.kept, ["claude"])
        XCTAssertEqual(store.manifest(for: "test.theme")?.icons.first?.variants.count, 2, "the working icon stayed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("test.theme/ok-32@2x.png").path))
    }
}
