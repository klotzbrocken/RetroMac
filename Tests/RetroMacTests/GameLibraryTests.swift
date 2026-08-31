import XCTest
@testable import RetroMac

/// What the Game Library thinks belongs to which title. This decides two things that must not go
/// wrong: which cards show a green tick, and which files "Delete Game Data" removes. Every game
/// here shares a folder with at least one other one — Doom with Doom II, Heretic and Freedoom;
/// Duke Nukem with Shadow Warrior — so a matcher that is one character too loose either lies
/// about what is installed or deletes the wrong game.
final class GameLibraryTests: XCTestCase {

    private var tempDir: URL!
    private var savedWadFolder = ""
    private var savedGrpFolder = ""

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RetroMacGameLibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // These are real user settings, so they are put back in tearDown.
        savedWadFolder = AppSettings.shared.doomWadFolder
        savedGrpFolder = AppSettings.shared.razeGrpFolder
    }

    override func tearDownWithError() throws {
        AppSettings.shared.doomWadFolder = savedWadFolder
        AppSettings.shared.razeGrpFolder = savedGrpFolder
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String) {
        FileManager.default.createFile(atPath: tempDir.appendingPathComponent(name).path,
                                       contents: Data("x".utf8))
    }

    private func title(_ id: String) throws -> InternetArchive.Title {
        try XCTUnwrap(InternetArchive.title(id: id), "no catalogue entry for \(id)")
    }

    private func names(_ id: String) throws -> [String] {
        InternetArchive.installedFiles(try title(id)).map { $0.lastPathComponent }
    }

    // MARK: - One folder, four games

    func testWadFolderKeepsItsFourGamesApart() throws {
        AppSettings.shared.doomWadFolder = tempDir.path
        write("doom.wad")
        write("doom2.wad")
        write("HERETIC.WAD")
        write("freedoom1.wad")

        XCTAssertEqual(try names("doom"), ["doom.wad"])
        XCTAssertEqual(try names("doom2"), ["doom2.wad"])
        XCTAssertEqual(try names("heretic"), ["HERETIC.WAD"])
        XCTAssertEqual(try names("freedoom"), ["freedoom1.wad"])
    }

    /// The launcher accepts HERETIC1.WAD as well, so the card has to recognise it too — otherwise
    /// a playable game shows as missing and a second copy gets downloaded on top of it.
    func testHereticIsRecognisedUnderItsOtherName() throws {
        AppSettings.shared.doomWadFolder = tempDir.path
        write("HERETIC1.WAD")
        XCTAssertEqual(try names("heretic"), ["HERETIC1.WAD"])
        XCTAssertTrue(try names("doom").isEmpty)
    }

    func testDoomDoesNotClaimDoomIIOrFreedoom() throws {
        AppSettings.shared.doomWadFolder = tempDir.path
        write("doom2.wad")
        write("freedoom1.wad")
        XCTAssertTrue(try names("doom").isEmpty, "Doom must not tick because Doom II is installed")
    }

    func testDukeAndShadowWarriorShareAFolderWithoutSharingAGrp() throws {
        AppSettings.shared.razeGrpFolder = tempDir.path
        write("DUKE3D.GRP")
        write("SW.GRP")
        XCTAssertEqual(try names("duke3d"), ["DUKE3D.GRP"])
        XCTAssertEqual(try names("shadowwarrior"), ["SW.GRP"])
    }

    // MARK: - Deletion

    func testDeleteRemovesOnlyThatTitlesFiles() throws {
        AppSettings.shared.doomWadFolder = tempDir.path
        write("doom.wad")
        write("doom2.wad")
        write("HERETIC.WAD")

        let removed = InternetArchive.deleteInstalled(try title("doom2"))
        XCTAssertEqual(removed.map { $0.lastPathComponent }, ["doom2.wad"])

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: tempDir.appendingPathComponent("doom2.wad").path))
        XCTAssertTrue(fm.fileExists(atPath: tempDir.appendingPathComponent("doom.wad").path))
        XCTAssertTrue(fm.fileExists(atPath: tempDir.appendingPathComponent("HERETIC.WAD").path))
    }

    func testDeletingSomethingThatIsNotThereDoesNothing() throws {
        AppSettings.shared.doomWadFolder = tempDir.path
        XCTAssertTrue(InternetArchive.deleteInstalled(try title("doom")).isEmpty)
    }

    /// Warcraft data outside RetroMac's own folders is the user's own copy of the game. Deleting
    /// it would erase files RetroMac never put there, so that case only clears the stored path.
    func testWarcraftDataOutsideOurFolderIsOnlyForgotten() throws {
        let saved = AppSettings.shared.warcraft1DataFolder
        defer { AppSettings.shared.warcraft1DataFolder = saved }

        let fm = FileManager.default
        let scripts = tempDir.appendingPathComponent("scripts")
        try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
        fm.createFile(atPath: scripts.appendingPathComponent("wc1-config.lua").path, contents: Data("x".utf8))
        try fm.createDirectory(at: tempDir.appendingPathComponent("graphics"), withIntermediateDirectories: true)
        AppSettings.shared.warcraft1DataFolder = tempDir.path

        let t = try title("warcraft1")
        XCTAssertTrue(InternetArchive.isInstalled(t))
        XCTAssertTrue(InternetArchive.deleteOnlyForgets(t))

        XCTAssertTrue(InternetArchive.deleteInstalled(t).isEmpty, "nothing may be erased")
        XCTAssertTrue(fm.fileExists(atPath: scripts.appendingPathComponent("wc1-config.lua").path))
        XCTAssertEqual(AppSettings.shared.warcraft1DataFolder, "")
    }

    // MARK: - Pointing a title at your own files

    /// Quake wants the folder ABOVE id1. People pick either one, so both have to land on the
    /// base path — otherwise the engine is handed `.../id1/id1` and finds nothing.
    func testChoosingEitherQuakeFolderSetsTheBasePath() throws {
        let saved = AppSettings.shared.quakeBasePath
        defer { AppSettings.shared.quakeBasePath = saved }
        let fm = FileManager.default
        let id1 = tempDir.appendingPathComponent("id1")
        try fm.createDirectory(at: id1, withIntermediateDirectories: true)
        fm.createFile(atPath: id1.appendingPathComponent("pak0.pak").path, contents: Data("x".utf8))
        let t = try title("quake")

        XCTAssertNil(InternetArchive.useFolder(tempDir, for: t))
        XCTAssertEqual(AppSettings.shared.quakeBasePath, tempDir.path)

        AppSettings.shared.quakeBasePath = ""
        XCTAssertNil(InternetArchive.useFolder(id1, for: t))
        XCTAssertEqual(AppSettings.shared.quakeBasePath, tempDir.path)
    }

    func testChoosingAFolderWithNothingInItSaysSo() throws {
        let saved = AppSettings.shared.doomWadFolder
        defer { AppSettings.shared.doomWadFolder = saved }
        let message = InternetArchive.useFolder(tempDir, for: try title("doom"))
        XCTAssertNotNil(message)
    }

    // MARK: - Catalogue

    func testEveryTitleHasAReachableSourceAndDistinctID() {
        var seen = Set<String>()
        for t in InternetArchive.catalogue {
            XCTAssertTrue(seen.insert(t.id).inserted, "duplicate id \(t.id)")
            XCTAssertGreaterThan(t.bytes, 0, "\(t.id) has no size to show")
            if t.builtIn == nil {
                XCTAssertFalse(t.item.isEmpty, "\(t.id) has no Archive item")
                XCTAssertFalse(t.members.isEmpty, "\(t.id) has nothing to download")
                for m in t.members {
                    XCTAssertNotNil(InternetArchive.downloadURL(t, member: m), "\(t.id): \(m)")
                }
            }
        }
    }

    /// The Doom archive's name contains a `+`, which `.urlPathAllowed` leaves alone and the
    /// Archive then reads as a space — a 404. It has to arrive percent-encoded.
    func testArchiveNamesWithAPlusAreEscaped() throws {
        let doom = try title("doom")
        let url = try XCTUnwrap(InternetArchive.downloadURL(doom, member: "doom.wad"))
        XCTAssertTrue(url.absoluteString.contains("%2B"), url.absoluteString)
        XCTAssertFalse(url.absoluteString.contains("+"), url.absoluteString)
    }
}
