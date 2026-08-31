import Foundation

/// The Internet Archive titles RetroMac can fetch game data from, and the plumbing to reach them.
///
/// The archive items are whole game installs or collections, most of them between half a gigabyte
/// and 1.4 GB, but every engine RetroMac drives needs only a handful of files out of them. The
/// Archive can extract a single member on request — `…/download/<item>/<archive>/<path>` works for
/// zip, 7z and rar alike — so a title costs its data files rather than its disc image. Across the
/// six titles that is 436 MB instead of 6.9 GB.
///
/// The sizes below were read from each archive's own file index, not estimated. They cannot drift:
/// these are fixed, immutable Archive items.
enum InternetArchive {

    /// One downloadable title. `archive` is nil when the member is a plain file in the item.
    struct Title: Identifiable, Equatable {
        /// Matches the desktop shortcut type and the Setup Assistant's row id.
        let id: String
        let name: String
        let year: String
        let item: String
        let archive: String?
        /// Paths inside the archive, exactly as its index spells them (case included).
        let members: [String]
        /// Total bytes of `members`, measured from the archive index.
        let bytes: Int64
        /// A file in the ITEM (not inside the archive) used as cover art.
        let cover: String
        /// The item the cover lives in, when it is not the item being downloaded. The Heretic WAD
        /// sits in a bare item with no artwork at all, so its cover comes from the MS-DOS item.
        let coverItem: String?
        /// Where the members end up, and what has to happen to them afterwards.
        let destination: Destination
        /// What has to be installed for the data to be playable.
        let engine: Engine
        /// Set when the data does not come from the Archive but from the game's own project.
        let builtIn: BuiltIn?
        /// Shown under the title where the download alone does not give the full experience.
        let caveat: String?

        static func == (a: Title, b: Title) -> Bool { a.id == b.id }
    }

    enum Destination: Equatable {
        /// Straight into the folder, flattened (the engine looks for a file, not a tree).
        case flat(folder: FolderKey)
        /// Into a named subfolder of the base path, e.g. `id1/` or `baseq2/`.
        case subfolder(folder: FolderKey, name: String)
        /// Staged in a temp install directory, then handed to `WarcraftGame.extract`.
        case warcraftInstall(WarcraftGame.Title)
    }

    /// Two titles do not come from the Archive at all: Freedoom is free software from its own
    /// project, Shadow Warrior is the publisher's shareware. RetroMac already fetched both from
    /// their own sources, and the Library is the place for that now, so those routes are named
    /// here rather than left behind in a menu.
    enum BuiltIn: String { case freedoom, shadowWarrior }

    /// The engine a title needs. Game data alone plays nothing, so the gallery treats the engine
    /// as part of the download rather than as a wall the user hits afterwards.
    enum Engine: String {
        case gzdoom, raze, vkQuake, yquake2, bundled

        var name: String {
            switch self {
            case .gzdoom:  return "GZDoom"
            case .raze:    return "Raze"
            case .vkQuake: return "vkQuake"
            case .yquake2: return "Yamagi Quake II"
            case .bundled: return "the bundled Stratagus engine"
            }
        }

        /// Roughly what the engine download costs, for the card's note.
        var sizeNote: String {
            switch self {
            case .gzdoom:  return "~40 MB"
            case .raze:    return "~30 MB"
            case .vkQuake: return "~11 MB"
            case .yquake2: return "~7 MB"
            case .bundled: return ""
            }
        }

        /// Where the engine lives once installed. `yquake2.app` is the name the notarized
        /// MacSourcePorts build actually carries; the other two spellings are older ones the
        /// launcher has always accepted.
        var appPaths: [String] {
            switch self {
            case .gzdoom:  return ["/Applications/GZDoom.app"]
            case .raze:    return ["/Applications/Raze.app"]
            case .vkQuake: return ["/Applications/vkQuake.app"]
            case .yquake2: return ["/Applications/yquake2.app",
                                   "/Applications/quake2.app",
                                   "/Applications/Yamagi Quake II.app"]
            case .bundled: return []
            }
        }

        var isInstalled: Bool {
            if case .bundled = self { return WarcraftGame.isEngineAvailable(.warcraft2) }
            return appPaths.contains { FileManager.default.fileExists(atPath: $0) }
        }
    }

    /// The AppSettings property each title writes when it lands.
    enum FolderKey: String {
        case doomWadFolder, razeGrpFolder, quakeBasePath, quake2BasePath, warcraft2DataFolder
    }

    // MARK: - Catalogue

    /// Deliberately six titles, not the eight that were suggested:
    ///
    /// **Warcraft I is missing** because nothing could use it. `WarcraftGame.canExtract` refuses
    /// anything but Warcraft II, and the build ships `wargus/wartool` only — there is no
    /// `war1tool`. Downloading it would produce data no code path can open.
    ///
    /// **Heretic II is missing** because RetroMac has no engine for it. `launchHeretic` runs
    /// GZDoom against a Heretic WAD; Heretic II is a Quake II-engine game with no launcher, no
    /// settings key and no icon here.
    ///
    /// Heretic also does NOT use the suggested `heretic-v-1.3`: that item's .rar holds a CD image
    /// (`image.ccd`/`.cue`/`.img`) rather than game files. `HERETIC_201905` is the bare WAD.
    static let catalogue: [Title] = [
        Title(id: "doom", name: "Doom", year: "1993",
              item: "doom-doom-ii-collection-wad-files",
              archive: "Doom + Doom II Collection WAD files.7z",
              members: ["doom.wad"],
              bytes: 12_996_515,
              cover: "Doom-DoomII_Bundle_Boxart_900x506-01.jpg", coverItem: nil,
              destination: .flat(folder: .doomWadFolder), engine: .gzdoom, builtIn: nil,
              caveat: nil),

        // Two entries out of one archive: they are separate games with separate IWADs, and a
        // single "Doom" card could only ever install one of them.
        Title(id: "doom2", name: "Doom II", year: "1994",
              item: "doom-doom-ii-collection-wad-files",
              archive: "Doom + Doom II Collection WAD files.7z",
              members: ["doom2.wad"],
              bytes: 14_951_361,
              cover: "Doom-DoomII_Bundle_Boxart_900x506-01.jpg", coverItem: nil,
              destination: .flat(folder: .doomWadFolder), engine: .gzdoom, builtIn: nil,
              caveat: nil),

        Title(id: "heretic", name: "Heretic", year: "1994",
              item: "HERETIC_201905",
              archive: nil,
              members: ["HERETIC.WAD"],
              bytes: 14_189_976,
              cover: "00cover.jpg", coverItem: "msdos_Heretic_1994",
              destination: .flat(folder: .doomWadFolder), engine: .gzdoom, builtIn: nil,
              caveat: nil),

        Title(id: "duke3d", name: "Duke Nukem 3D", year: "1996",
              item: "duke-3-d",
              archive: "DUKE3D.zip",
              members: ["DUKE3D.GRP"],
              bytes: 26_524_524,
              cover: "DUKE3D.png", coverItem: nil,
              destination: .flat(folder: .razeGrpFolder), engine: .raze, builtIn: nil,
              caveat: nil),

        Title(id: "quake", name: "Quake", year: "1996",
              item: "quake-complete",
              archive: "Quake.zip",
              members: ["id1/pak0.pak"],
              bytes: 179_618_935,
              cover: "Quake1cover.jpg", coverItem: nil,
              destination: .subfolder(folder: .quakeBasePath, name: "id1"), engine: .vkQuake, builtIn: nil,
              caveat: nil),

        Title(id: "quake2", name: "Quake II", year: "1997",
              item: "quake-2-complete",
              archive: "Quake 2.zip",
              members: ["Quake 2/baseq2/pak0.pak"],
              bytes: 183_997_730,
              cover: "Quake2box.jpg", coverItem: nil,
              destination: .subfolder(folder: .quake2BasePath, name: "baseq2"), engine: .yquake2, builtIn: nil,
              caveat: nil),

        Title(id: "warcraft2", name: "Warcraft II", year: "1995",
              item: "msdos_Warcraft_II_-_Tides_of_Darkness_1995",
              archive: "Warcraft_II_-_Tides_of_Darkness_1995.zip",
              members: ["WarcrafD/DATA/INSMAIN.INS",
                        "WarcrafD/DATA/INSSTR.INS",
                        "WarcrafD/DATA/MAINDAT.WAR",
                        "WarcrafD/DATA/REZDAT.WAR",
                        "WarcrafD/DATA/SFXDAT.SUD",
                        "WarcrafD/DATA/STRDAT.WAR"],
              bytes: 18_599_614,
              cover: "00cover.jpg", coverItem: nil,
              destination: .warcraftInstall(.warcraft2), engine: .bundled, builtIn: nil,
              // The CD audio and cutscenes live in two disc images in the same item, together
              // 1.27 GB. Fetching the DATA folder gets a playable game without them.
              caveat: "Without the CD music and cutscenes (they are 1.3 GB of disc images)."),

        // Warcraft I is here now because the build produces war1tool: without an extractor the
        // download would have been 73 MB of files nothing could open.
        Title(id: "warcraft1", name: "Warcraft: Orcs & Humans", year: "1994",
              item: "WarcraftOrcsAndHumans",
              archive: "Warcraft - Orcs and Humans.zip",
              members: warcraft1Members,
              bytes: 72_639_924,
              cover: "Cover.jpg", coverItem: "warcraft-orcs-humans",
              destination: .warcraftInstall(.warcraft1), engine: .bundled, builtIn: nil,
              caveat: nil),

        // Free and legal, and therefore the two entries this window can recommend without a
        // caveat: Freedoom is under a BSD-style licence, Shadow Warrior's shareware episode was
        // published for free distribution.
        Title(id: "freedoom", name: "Freedoom", year: "2001",
              item: "", archive: nil, members: [],
              bytes: 24_143_781,
              // No box art exists for a free game, so the card carries a screenshot from the
              // project's own release.
              cover: "th_phase1-gzdoom-e3m1-trilobites-worms-0.13.0.png", coverItem: "freedoom-0.13.0",
              destination: .flat(folder: .doomWadFolder), engine: .gzdoom, builtIn: .freedoom,
              caveat: nil),

        Title(id: "shadowwarrior", name: "Shadow Warrior", year: "1997",
              item: "swp426shadowwarriorshareware", archive: nil, members: [],
              bytes: 14_259_146,
              cover: "124337-shadow-warrior-dos-front-cover.jpg", coverItem: nil,
              destination: .flat(folder: .razeGrpFolder), engine: .raze, builtIn: .shadowWarrior,
              caveat: "The shareware episode, as published for free distribution."),
    ]

    /// The whole DATA folder: war1tool reads data.war for the game itself and every other .WAR
    /// as a cutscene, so leaving any of them out costs content.
    private static let warcraft1Members: [String] = {
        var m = ["WARCRAFT/DATA/DATA.WAR", "WARCRAFT/DATA/TITLE.WAR",
                 "WARCRAFT/DATA/CAVE1.WAR", "WARCRAFT/DATA/CAVE2.WAR", "WARCRAFT/DATA/CAVE3.WAR",
                 "WARCRAFT/DATA/HFINALE.WAR", "WARCRAFT/DATA/OFINALE.WAR",
                 "WARCRAFT/DATA/HINTRO1.WAR", "WARCRAFT/DATA/HINTRO2.WAR",
                 "WARCRAFT/DATA/OINTRO1.WAR", "WARCRAFT/DATA/OINTRO2.WAR", "WARCRAFT/DATA/OINTRO3.WAR",
                 "WARCRAFT/DATA/LOSE1.WAR", "WARCRAFT/DATA/LOSE2.WAR",
                 "WARCRAFT/DATA/WIN1.WAR", "WARCRAFT/DATA/WIN2.WAR"]
        for i in 1...12 {
            m.append(String(format: "WARCRAFT/DATA/HMAP%02d.WAR", i))
            m.append(String(format: "WARCRAFT/DATA/OMAP%02d.WAR", i))
        }
        return m
    }()

    static func title(id: String) -> Title? { catalogue.first { $0.id == id } }

    // MARK: - URLs

    /// Where a single member comes from. The Archive extracts it on the fly for archived members,
    /// which is why those responses carry no `Content-Length` — see `GameDownloader`.
    static func downloadURL(_ t: Title, member: String) -> URL? {
        var path = "https://archive.org/download/\(escape(t.item))/"
        if let archive = t.archive { path += "\(escape(archive))/" }
        path += member.split(separator: "/").map(escape).joined(separator: "/")
        return URL(string: path)
    }

    static func coverURL(_ t: Title) -> URL? {
        let item = t.coverItem ?? t.item
        guard !item.isEmpty, !t.cover.isEmpty else { return nil }
        return URL(string: "https://archive.org/download/\(escape(item))/\(escape(t.cover))")
    }

    /// Where the download comes from, for the "what am I actually getting" link on the card.
    static func detailsURL(_ t: Title) -> URL? {
        if t.builtIn == .freedoom { return URL(string: "https://freedoom.github.io") }
        guard !t.item.isEmpty else { return nil }
        return URL(string: "https://archive.org/details/\(escape(t.item))")
    }

    /// `+` has to go too, and that is not pedantry: the Doom archive is called
    /// "Doom + Doom II Collection WAD files.7z", and a literal `+` in the path is read as a
    /// space, which answers 404. `.urlPathAllowed` leaves `+` alone, so it is escaped by hand.
    private static func escape(_ s: any StringProtocol) -> String {
        String(s).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "#", with: "%23")
            .replacingOccurrences(of: "?", with: "%3F") ?? String(s)
    }

    // MARK: - Where a title lands

    /// The folder a title's files belong in, creating it if needed.
    static func destinationFolder(_ t: Title) -> URL? {
        let s = AppSettings.shared
        func base(_ key: FolderKey) -> String {
            switch key {
            case .doomWadFolder:       return s.doomWadFolder
            case .razeGrpFolder:       return s.razeGrpFolder
            case .quakeBasePath:       return s.quakeBasePath
            case .quake2BasePath:      return s.quake2BasePath
            case .warcraft2DataFolder: return s.warcraft2DataFolder
            }
        }
        let url: URL
        switch t.destination {
        case .flat(let key):
            let p = base(key)
            guard !p.isEmpty else { return nil }
            url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        case .subfolder(let key, let name):
            let p = base(key)
            guard !p.isEmpty else { return nil }
            url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
                .appendingPathComponent(name, isDirectory: true)
        case .warcraftInstall(let wc):
            // Staged, not final: `WarcraftGame.extract` turns this into the playable data.
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("RetroMac-\(wc.rawValue)-install", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - What is already here

    /// Whether this title's data is in place. Deliberately narrower than the Setup Assistant's
    /// folder checks: `doomHasData` says yes to ANY .wad, so installing Heretic would put a green
    /// tick on Doom's card, and Doom II would tick Doom.
    static func isInstalled(_ t: Title) -> Bool { !installedFiles(t).isEmpty }

    /// The files this title owns: what makes it count as installed, and exactly what
    /// "Delete Game Data" offers to remove. Warcraft answers with its extracted data folder,
    /// because that is the unit the engine reads.
    static func installedFiles(_ t: Title) -> [URL] {
        let s = AppSettings.shared
        switch t.destination {
        case .flat, .subfolder:
            guard let folder = existingDestination(t),
                  let items = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
            return items.filter { matches(t, $0.lowercased()) }
                        .sorted()
                        .map { folder.appendingPathComponent($0) }
        case .warcraftInstall(let wc):
            let p = wc == .warcraft2 ? s.warcraft2DataFolder : s.warcraft1DataFolder
            guard !p.isEmpty else { return [] }
            let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            return WarcraftGame.hasExtractedData(at: url, wc) ? [url] : []
        }
    }

    /// Which filenames belong to this title. Loose enough to recognise the user's own copy
    /// (HERETIC1.WAD as well as HERETIC.WAD), tight enough to keep the cards apart.
    private static func matches(_ t: Title, _ lower: String) -> Bool {
        switch t.id {
        case "doom":    return lower.hasSuffix(".wad") && lower.contains("doom")
                            && !lower.contains("doom2") && !lower.contains("freedoom")
        case "doom2":   return lower.hasSuffix(".wad") && lower.contains("doom2")
        // The same rule `launchHeretic` uses to find its WAD.
        case "heretic": return lower.hasSuffix(".wad") && lower.contains("heretic")
        // NOT just any .grp: Shadow Warrior's SW.GRP lives in the same folder.
        case "duke3d":  return lower.hasSuffix(".grp") && lower.contains("duke")
        case "shadowwarrior": return lower == "sw.grp"
        case "freedoom": return lower.hasSuffix(".wad") && lower.contains("freedoom")
        case "quake", "quake2": return lower == "pak0.pak"
        default:        return false
        }
    }

    /// The destination folder, but only if it is already there — unlike `destinationFolder`
    /// this never creates anything, so merely drawing the gallery leaves no folders behind.
    private static func existingDestination(_ t: Title) -> URL? {
        let s = AppSettings.shared
        func base(_ key: FolderKey) -> String {
            switch key {
            case .doomWadFolder:       return s.doomWadFolder
            case .razeGrpFolder:       return s.razeGrpFolder
            case .quakeBasePath:       return s.quakeBasePath
            case .quake2BasePath:      return s.quake2BasePath
            case .warcraft2DataFolder: return s.warcraft2DataFolder
            }
        }
        var url: URL
        switch t.destination {
        case .flat(let key):
            let p = base(key); guard !p.isEmpty else { return nil }
            url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        case .subfolder(let key, let name):
            let p = base(key); guard !p.isEmpty else { return nil }
            url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
                .appendingPathComponent(name, isDirectory: true)
        case .warcraftInstall:
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return url
    }

    /// Remove what a title installed, and report what went. Warcraft data that lives outside
    /// RetroMac's own folders is deliberately left alone — that is the user's own copy of the
    /// game sitting where they put it — and only the stored path is cleared.
    @discardableResult
    static func deleteInstalled(_ t: Title) -> [URL] {
        let files = installedFiles(t)
        guard !files.isEmpty else { return [] }
        if case .warcraftInstall(let wc) = t.destination {
            let ours = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/RetroMac").path
            var removed: [URL] = []
            if let f = files.first, f.path.hasPrefix(ours) {
                try? FileManager.default.removeItem(at: f)
                removed.append(f)
            }
            if wc == .warcraft2 { AppSettings.shared.warcraft2DataFolder = "" }
            else                { AppSettings.shared.warcraft1DataFolder = "" }
            return removed
        }
        for f in files { try? FileManager.default.removeItem(at: f) }
        return files
    }

    /// True when deleting this title would only forget a path rather than erase anything.
    static func deleteOnlyForgets(_ t: Title) -> Bool {
        guard case .warcraftInstall = t.destination, let f = installedFiles(t).first else { return false }
        let ours = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RetroMac").path
        return !f.path.hasPrefix(ours)
    }

    /// Point a title at a folder the user already has. Returns an error message when the folder
    /// holds nothing the engine could use, so the caller can show it on the card.
    static func useFolder(_ dir: URL, for t: Title) -> String? {
        let s = AppSettings.shared
        func set(_ key: FolderKey, _ path: String) {
            switch key {
            case .doomWadFolder:       s.doomWadFolder = path
            case .razeGrpFolder:       s.razeGrpFolder = path
            case .quakeBasePath:       s.quakeBasePath = path
            case .quake2BasePath:      s.quake2BasePath = path
            case .warcraft2DataFolder: s.warcraft2DataFolder = path
            }
        }
        switch t.destination {
        case .flat(let key):
            set(key, dir.path)
        case .subfolder(let key, let name):
            // Quake wants the BASE folder. People pick `id1` just as often, so accept both and
            // step up a level when the pak is sitting right there.
            let fm = FileManager.default
            let inside = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: inside.path) {
                set(key, dir.path)
            } else if dir.lastPathComponent.lowercased() == name.lowercased() {
                set(key, dir.deletingLastPathComponent().path)
            } else {
                set(key, dir.path)
            }
        case .warcraftInstall:
            return nil   // handled by the caller, which knows about extraction
        }
        return isInstalled(t) ? nil : "No \(t.name) data found in that folder."
    }

    /// Human-readable size, for the gallery card.
    static func sizeText(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
