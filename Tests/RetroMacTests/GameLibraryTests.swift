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
                // The catalogue still has to KNOW where the data lives and what it is called,
                // even for the titles RetroMac will not fetch: that is what the card tells the
                // user to go and find.
                XCTAssertFalse(t.item.isEmpty, "\(t.id) has no Archive item")
                XCTAssertFalse(t.members.isEmpty, "\(t.id) names no files")
            }
        }
    }

    // MARK: - What RetroMac may fetch

    /// The one that matters. Eight of the ten titles are commercial games sitting in Archive
    /// items that state no licence at all, and RetroMac must not hand them out however the UI is
    /// later rearranged. `downloadURL` is the single gate, so this is the test that guards it.
    func testOnlyFreelyDistributableTitlesCanProduceADownloadURL() {
        for t in InternetArchive.catalogue {
            let urls = (t.members.isEmpty ? [""] : t.members)
                .compactMap { InternetArchive.downloadURL(t, member: $0) }
            if t.freelyDistributable {
                XCTAssertEqual(t.builtIn != nil, true, "\(t.id) should come from its own project")
            } else {
                XCTAssertTrue(urls.isEmpty, "\(t.id) must not be downloadable: \(urls)")
            }
        }
        XCTAssertEqual(InternetArchive.freelyDistributableIDs, ["freedoom", "shadowwarrior"])
    }

    func testTheFreeTitlesAreTheOnlyOnesThatOfferASize() {
        let paid = InternetArchive.catalogue.filter { !$0.freelyDistributable }
        XCTAssertEqual(paid.count, 8)
        for t in paid {
            XCTAssertFalse(InternetArchive.neededFilesText(t).isEmpty, "\(t.id) says nothing about what it needs")
        }
    }

    /// The `+` in "Doom + Doom II Collection WAD files.7z" is read as a space by the Archive and
    /// answers 404, so it has to arrive percent-encoded. No shipped title can build a URL any
    /// more, so the escaping is exercised through a stand-in that can.
    func testArchiveNamesWithAPlusAreEscaped() throws {
        let t = InternetArchive.Title(
            id: "freedoom", name: "Stand-in", year: "1993",
            item: "an+item", archive: "A + B.7z", members: ["a+b.wad"], bytes: 1,
            cover: "", coverItem: nil, destination: .flat(folder: .doomWadFolder),
            engine: .gzdoom, builtIn: nil, caveat: nil)
        let url = try XCTUnwrap(InternetArchive.downloadURL(t, member: "a+b.wad"))
        XCTAssertTrue(url.absoluteString.contains("%2B"), url.absoluteString)
        XCTAssertFalse(url.absoluteString.contains("+"), url.absoluteString)
    }

    // MARK: - Shareware

    /// Shareware is the one thing RetroMac fetches for a commercial game, so the entries have to
    /// stay pinned to that meaning: never on a title that is already free (there is nothing to
    /// be a sample of), and never pointing at the two full free downloads by mistake.
    func testSharewareOnlySitsOnTheCommercialTitles() {
        let full: Set<InternetArchive.BuiltIn> = [.freedoom, .shadowWarrior]
        var withShareware: [String] = []
        for t in InternetArchive.catalogue {
            guard let sw = t.shareware else { continue }
            withShareware.append(t.id)
            XCTAssertFalse(t.freelyDistributable, "\(t.id) is already free in full")
            XCTAssertFalse(full.contains(sw.source), "\(t.id) points at a full download")
            XCTAssertFalse(sw.episode.isEmpty, "\(t.id) does not say what you get")
            XCTAssertFalse(sw.sizeNote.isEmpty, "\(t.id) does not say how big it is")
        }
        // Doom II never had a shareware release, and Warcraft's demos are not redistributable,
        // so this list is the whole of it. Every entry was verified by downloading it and
        // checking the extracted file's size and magic bytes.
        XCTAssertEqual(Set(withShareware), ["doom", "heretic", "duke3d", "quake", "quake2"])
    }

    /// Each shareware source has to be reachable through `fetchBuiltInGame`, which switches
    /// exhaustively — so a new case that nobody wired up would not compile. This pins the other
    /// direction: no two titles quietly sharing one download.
    func testEverySharewareSourceIsUsedOnce() {
        let sources = InternetArchive.catalogue.compactMap { $0.shareware?.source }
        XCTAssertEqual(sources.count, Set(sources.map(\.rawValue)).count)
    }

    // MARK: - Finding the copy you already own

    /// The walk and the matcher together, against a Steam library laid out the way Steam lays
    /// one out. Doom and Doom II sit in sibling folders under different spellings, which is the
    /// case that would go wrong if the search stopped at the first `.wad` it met.
    func testFindsSteamCopiesWithoutMixingUpTheGames() throws {
        let fm = FileManager.default
        let common = tempDir.appendingPathComponent("Steam/steamapps/common")
        func put(_ path: String) throws {
            let url = common.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }
        try put("Ultimate Doom/base/DOOM.WAD")
        try put("Doom 2/base/DOOM2.WAD")
        try put("Quake/id1/PAK0.PAK")
        try put("Some Other Game/readme.txt")

        let wanted = try ["doom", "doom2", "quake", "duke3d"].map { try title($0) }
        let hits = InternetArchive.foundLocally(wanted, in: [common])

        XCTAssertEqual(hits["doom"]?.lastPathComponent, "DOOM.WAD")
        XCTAssertEqual(hits["doom2"]?.lastPathComponent, "DOOM2.WAD")
        XCTAssertEqual(hits["quake"]?.lastPathComponent, "PAK0.PAK")
        XCTAssertNil(hits["duke3d"], "nothing here is Duke")
    }

    /// Three levels and no further, so a deep tree cannot turn the gallery into a disk crawl.
    func testTheSearchStopsAtThreeLevels() throws {
        let fm = FileManager.default
        let root = tempDir.appendingPathComponent("root")
        let deep = root.appendingPathComponent("a/b/c/d")
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        fm.createFile(atPath: deep.appendingPathComponent("doom.wad").path, contents: Data("x".utf8))
        XCTAssertTrue(InternetArchive.foundLocally([try title("doom")], in: [root]).isEmpty)
    }

    // MARK: - Steam's libraries

    /// The current `libraryfolders.vdf`, where each library is a numbered block with a `path`.
    /// The `apps` block inside it is the trap: it is full of numbered keys whose values are app
    /// ids, and a parser that takes "a number followed by something" swallows those too.
    func testTheCurrentVDFFormatYieldsOnlyTheLibraryPaths() {
        let vdf = """
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"/Users/maik/Library/Application Support/Steam"
        \t\t"label"\t\t""
        \t\t"totalsize"\t\t"0"
        \t\t"apps"
        \t\t{
        \t\t\t"2280"\t\t"14892400"
        \t\t}
        \t}
        \t"1"
        \t{
        \t\t"path"\t\t"/Volumes/Games SSD/SteamLibrary"
        \t\t"label"\t\t""
        \t}
        }
        """
        XCTAssertEqual(InternetArchive.steamLibraryPaths(fromVDF: vdf),
                       ["/Users/maik/Library/Application Support/Steam",
                        "/Volumes/Games SSD/SteamLibrary"])
    }

    /// The pre-2021 format put the path straight against the number, with counters beside it.
    func testTheOldVDFFormatStillParses() {
        let vdf = """
        "LibraryFolders"
        {
        \t"TimeNextStatsReport"\t\t"1788283649"
        \t"ContentStatsID"\t\t"-4373139012345"
        \t"1"\t\t"/Volumes/Games SSD/SteamLibrary"
        }
        """
        XCTAssertEqual(InternetArchive.steamLibraryPaths(fromVDF: vdf),
                       ["/Volumes/Games SSD/SteamLibrary"])
    }

    func testAMissingOrJunkVDFYieldsNothingRatherThanNonsense() {
        XCTAssertTrue(InternetArchive.steamLibraryPaths(fromVDF: "").isEmpty)
        XCTAssertTrue(InternetArchive.steamLibraryPaths(fromVDF: "not a vdf at all").isEmpty)
        XCTAssertTrue(InternetArchive.steamLibraryPaths(fromVDF: "\"path\" \"relative/thing\"").isEmpty)
    }

    /// Whatever the file says, the default library is always searched, and never twice.
    func testTheDefaultLibraryIsAlwaysIncludedExactlyOnce() {
        let libs = InternetArchive.steamLibraries()
        let expected = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Steam/steamapps/common").path
        XCTAssertEqual(libs.first, expected)
        XCTAssertEqual(libs.filter { $0 == expected }.count, 1)
        XCTAssertEqual(Set(libs).count, libs.count, "a library is listed twice")
    }

    // MARK: - Which folders are ours to delete

    /// A prefix test says yes to "RetroMac Backup", and for Warcraft the thing being tested is
    /// the data DIRECTORY, so "Forget" would have recursively erased the user's own folder.
    func testOurSupportFolderIsMatchedByComponentNotByPrefix() {
        let support = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        let ours = support.appendingPathComponent("RetroMac")

        XCTAssertTrue(InternetArchive.isInsideOurSupportFolder(ours.appendingPathComponent("Games/wc2")))
        XCTAssertTrue(InternetArchive.isInsideOurSupportFolder(ours.appendingPathComponent("x")))

        for sibling in ["RetroMac Backup", "RetroMac-old", "RetroMacGames", "RetroMac2"] {
            let url = support.appendingPathComponent(sibling).appendingPathComponent("Warcraft II")
            XCTAssertFalse(InternetArchive.isInsideOurSupportFolder(url), sibling)
        }
        // The folder itself is not "inside" it, so nothing can ever delete it wholesale.
        XCTAssertFalse(InternetArchive.isInsideOurSupportFolder(ours))
        XCTAssertFalse(InternetArchive.isInsideOurSupportFolder(URL(fileURLWithPath: "/tmp/x")))
    }
}
