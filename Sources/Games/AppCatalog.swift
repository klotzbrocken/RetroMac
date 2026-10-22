import AppKit

/// The Apps tab of RetroHub: retro-looking Mac apps that are real apps, not
/// themes. Same idea as the games — RetroMac fetches what may be fetched and installs it through
/// `TrustedDownloadInstaller` (signature, notarization and bundle ID checked), and what only an
/// app store may hand out gets a link to that store instead.
///
/// The screenshots come from each project's own page and are cached like the game covers, so
/// nothing of anyone else's is bundled.
enum AppCatalog {

    enum Source {
        /// The latest GitHub release; `asset` picks the file from the lower-cased asset names.
        case github(repo: String, asset: (String) -> Bool)
        /// A fixed download, `.dmg` or `.zip` by its extension.
        case direct(URL)
        /// Only the store hands it out.
        case appStore(URL)
        /// A bare program, not an app, with data the user brings: Johnny Castaway's, see there.
        case castaway
    }

    struct App: Identifiable {
        let id: String
        let name: String
        let author: String
        let blurb: String
        let bundleID: String
        /// The `.app` name inside the archive, matched case-insensitively.
        let appName: String
        let source: Source
        let page: URL
        let screenshot: URL
        let caveat: String?
        /// Nil = any Mac; otherwise the only architecture its binary has.
        var onlyArch: String? = nil
    }

    private static let isAppleSilicon: Bool = {
        var v: Int32 = 0; var n = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &n, nil, 0) == 0 && v == 1
    }()

    private static func repoPage(_ repo: String) -> URL { URL(string: "https://github.com/\(repo)")! }
    private static func shot(_ repo: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/\(repo)/main/docs/screenshots/hero.png")!
    }
    private static func dmg(_ name: String) -> (String) -> Bool { { $0.hasPrefix(name) && $0.hasSuffix(".dmg") } }

    static let catalogue: [App] = [
        App(id: "reframe", name: "Reframe", author: "Maik Klotz",
            blurb: "Today's web in the browsers we grew up with: a real Chromium browser inside 25 rebuilt classics from Mosaic to Safari 1.0, with a Wayback Machine time slider.",
            bundleID: AppSettings.reframeBundleID, appName: "Reframe",
            source: .github(repo: "klotzbrocken/Reframe", asset: { n in
                n.hasSuffix(".dmg") && n.contains("arm64") == isAppleSilicon }),
            page: repoPage("klotzbrocken/Reframe"),
            screenshot: URL(string: "https://myretromac.app/__l5e/assets-v1/1e5002b2-4565-4e10-8768-f9ee5905ab2c/reframe-hero-v1.14.jpg")!,
            caveat: nil),
        App(id: "retrofind", name: "RetroFind", author: "Maik Klotz",
            blurb: "The Finder of OS X 10.8 on your real files: icon, list, column and Cover Flow views, sidebar, Spotlight search and Quick Look.",
            bundleID: "de.maik.RetroFind", appName: "RetroFind",
            source: .github(repo: "klotzbrocken/RetroFind", asset: dmg("retrofind")),
            page: repoPage("klotzbrocken/RetroFind"), screenshot: shot("klotzbrocken/RetroFind"), caveat: nil),
        App(id: "retrocontacts", name: "RetroContacts", author: "Maik Klotz",
            blurb: "The leather-bound Address Book of OS X 10.8, working with your Mac's own contacts: groups, search, vCards.",
            bundleID: "de.retrocontacts.app", appName: "RetroContacts",
            source: .github(repo: "klotzbrocken/RetroContacts", asset: dmg("retrocontacts")),
            page: repoPage("klotzbrocken/RetroContacts"), screenshot: shot("klotzbrocken/RetroContacts"), caveat: nil),
        App(id: "retroreminder", name: "RetroReminder", author: "Maik Klotz",
            blurb: "Reminders as OS X 10.8 had it — dark leather, lined paper, a mini calendar — with your Mac's own reminders behind it.",
            bundleID: "de.maik.RetroReminder", appName: "RetroReminder",
            source: .github(repo: "klotzbrocken/retroreminder", asset: dmg("retroreminder")),
            page: repoPage("klotzbrocken/retroreminder"), screenshot: shot("klotzbrocken/retroreminder"),
            caveat: nil, onlyArch: "arm64"),
        App(id: "retrocal", name: "RetroCal", author: "Maik Klotz",
            blurb: "A calendar in leather, torn paper and glass: day, week, month and year, synced with your system calendars.",
            bundleID: "com.retromac.retrocal", appName: "RetroCal",
            source: .github(repo: "klotzbrocken/RetroCal", asset: dmg("retrocal")),
            page: repoPage("klotzbrocken/RetroCal"), screenshot: shot("klotzbrocken/RetroCal"), caveat: nil),
        App(id: "retronotes", name: "RetroNotes", author: "Maik Klotz",
            blurb: "Notes from OS X 10.8 — yellow lined paper under a leather header — reading and writing your notes from the Notes app.",
            bundleID: "de.maik.RetroNotes", appName: "RetroNotes",
            source: .github(repo: "klotzbrocken/RetroNotes", asset: dmg("retronotes")),
            page: repoPage("klotzbrocken/RetroNotes"), screenshot: shot("klotzbrocken/RetroNotes"),
            caveat: nil, onlyArch: "arm64"),
        App(id: "mojavepaint", name: "Mojave Paint", author: "Skull Rock Software",
            blurb: "An image editor with modern GPU internals and the clean look of the best 1990s paint programs: layers, masks, blend modes.",
            bundleID: "com.skullrocksoftware.mojavepaint", appName: "Mojave Paint",
            source: .appStore(URL(string: "macappstore://apps.apple.com/app/id6759276677")!),
            page: URL(string: "https://mojavepaint.app/")!,
            screenshot: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/c6/af/3e/c6af3ea6-d8eb-fce5-21f2-5fb5fa02717b/adjustments.png/800x500bb.jpg")!,
            caveat: "From the Mac App Store. Free for 14 days, then a one-time purchase."),
        App(id: "classicfinder", name: "Classic Mac Finder", author: "Ben Szymanski",
            blurb: "A pixel-for-pixel re-creation of the Finder of the Performa and Quadra days, spatial windows included.",
            bundleID: "com.classicmacfinder.Classic-Finder", appName: "Classic Finder",
            source: .direct(URL(string: "https://bitbucket.org/bszyman/classic-finder-app/downloads/Classic-Finder-1.1.3.zip")!),
            page: repoPage("bszyman/classic-mac-finder"),
            screenshot: URL(string: "https://raw.githubusercontent.com/bszyman/classic-mac-finder/master/header.jpg")!,
            caveat: nil, onlyArch: "x86_64"),
        App(id: "quicktune", name: "QuickTune", author: "Mario Guzmán",
            blurb: "Apple Music with the look and feel of the QuickTime 7 player.",
            bundleID: "com.marioaguzman.QuickTune", appName: "QuickTune",
            source: .direct(URL(string: "https://marioaguzman.github.io/quicktune/updater/QuickTune.dmg")!),
            page: URL(string: "https://marioaguzman.github.io/quicktune/")!,
            screenshot: URL(string: "https://marioaguzman.github.io/quicktune/images/qt_web_preview_card.png")!,
            caveat: nil),
        App(id: "retrolux", name: "Retrolux", author: "konzertblock",
            blurb: "Photo library and editing in the style of the pro photo software of the Snow Leopard years: browser, adjustments, places, full screen.",
            bundleID: "io.github.konzertblock.retrolux", appName: "Retrolux",
            source: .github(repo: "konzertblock/retrolux", asset: dmg("retrolux")),
            page: repoPage("konzertblock/retrolux"),
            screenshot: URL(string: "https://raw.githubusercontent.com/konzertblock/retrolux/main/docs/screenshots/browser.png")!,
            caveat: "Not signed with a Developer ID; RetroMac asks before installing it.", onlyArch: "arm64"),
        App(id: "retroncommander", name: "Retron Commander", author: "konzertblock",
            blurb: "A two-panel file manager in the style of the Norton Commander: blue panels, function-key bar, keyboard first.",
            bundleID: "com.konzertblock.RetronCommander", appName: "Retron Commander",
            source: .github(repo: "konzertblock/retron-commander", asset: dmg("retron-commander")),
            page: repoPage("konzertblock/retron-commander"),
            screenshot: URL(string: "https://raw.githubusercontent.com/konzertblock/retron-commander/main/Screenshots/RetronCommander-norton-commander.png")!,
            caveat: "Not signed with a Developer ID; RetroMac asks before installing it."),
        App(id: "arose", name: "ARose", author: "CooLajz",
            blurb: "The ARose screen saver of the Amiga's BlitzBlank, revived with its original authors' blessing: rotating, mirrored dots in ECS and AGA palettes, or a glowing modern mode.",
            bundleID: "cz.coolajz.ARose.Preview", appName: "ARose",
            source: .github(repo: "CooLajz/ARose-ScreenSaver", asset: { $0.hasSuffix("macos-universal.dmg") }),
            page: repoPage("CooLajz/ARose-ScreenSaver"),
            screenshot: URL(string: "https://raw.githubusercontent.com/CooLajz/ARose-ScreenSaver/main/Resources/thumbnail@2x.png")!,
            caveat: "Turn it on in System Settings \u{25B8} Screen Saver."),
        App(id: "johnnycastaway", name: "Johnny Castaway", author: "Open Scrantic (glauberlima)",
            blurb: "The 1992 Sierra screen saver, his island and his story day by day, on a reimplementation of the original engine. On the Windows 3.x and 9x desktops once installed.",
            bundleID: "", appName: "open-scrantic",
            source: .castaway,
            page: repoPage(JohnnyCastaway.repo),
            screenshot: URL(string: "https://raw.githubusercontent.com/glauberlima/open-scrantic/main/docs/images/open-scrantic-logo.png")!,
            caveat: "Needs your own copy of the original files (SCRANTIC.SCR, RESOURCE.MAP, RESOURCE.001); RetroMac asks for them the first time."),
    ]

    static func isInstalled(_ a: App) -> Bool {
        if case .castaway = a.source { return JohnnyCastaway.isInstalled }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.bundleID) != nil
    }

    /// What stands between this Mac and the app, or nil. An Intel-only app runs under Rosetta,
    /// which macOS offers to install on first launch; an Apple silicon-only one cannot run at all.
    static func archNote(_ a: App) -> String? {
        switch a.onlyArch {
        case "arm64" where !isAppleSilicon: return "Needs a Mac with Apple silicon."
        case "x86_64" where isAppleSilicon: return "Built for Intel; runs under Rosetta."
        default: return nil
        }
    }

    static func canInstall(_ a: App) -> Bool {
        if case .appStore = a.source { return false }
        return !(a.onlyArch == "arm64" && !isAppleSilicon)
    }

    // MARK: - Title bars

    /// These apps draw their own era's window, so a theme's title bar on top of it is a second,
    /// wrong one. Each is excluded once, when it is first seen installed; a user who takes one off
    /// the list later is not overruled (the flag remembers it was done).
    static func excludeInstalledFromTitleBars(defaults: UserDefaults = .standard) {
        var list = AppSettings.shared.themeTitleBarsExcludedApps
        var changed = false
        for a in catalogue where !a.bundleID.isEmpty && isInstalled(a) {
            // Reframe's flag predates this list; the same one, so a removal made then still counts.
            let flag = a.bundleID == AppSettings.reframeBundleID ? "reframeTitleBarExcluded" : "titleBarExcluded.\(a.bundleID)"
            guard !defaults.bool(forKey: flag) else { continue }
            if !list.contains(a.bundleID) { list.append(a.bundleID); changed = true }
            defaults.set(true, forKey: flag)
        }
        if changed { AppSettings.shared.themeTitleBarsExcludedApps = list }
    }

    /// At launch, and whenever one of the catalogue's apps starts: one installed from the App Store
    /// or by hand is caught the first time it runs, before a title bar is put over it.
    static func startWatching() {
        excludeInstalledFromTitleBars()
        let ids = Set(catalogue.map(\.bundleID))
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let id = app?.bundleIdentifier, ids.contains(id) { excludeInstalledFromTitleBars() }
        }
    }

    // MARK: - Install

    /// Download, unpack, verify and install to /Applications, then take it off the title bars.
    /// `completion(nil)` on success, else what went wrong; runs on the main thread.
    static func install(_ a: App, completion: @escaping (String?) -> Void) {
        let win = InstallProgressWindow.make(title: "Installing \(a.name)…", detail: "Downloading \(a.name)…")
        func finish(_ error: String?) {
            DispatchQueue.main.async {
                win.close()
                if error == nil { excludeInstalledFromTitleBars() }
                completion(error)
            }
        }
        switch a.source {
        case .appStore: finish("\(a.name) comes from the App Store.")
        case .direct(let url): DispatchQueue.global(qos: .userInitiated).async { finish(fetch(a, url, win)) }
        case .castaway:
            TrustedDownloadInstaller.latestReleaseAsset(repo: JohnnyCastaway.repo, matches: { $0 == JohnnyCastaway.asset }) { result in
                guard case .success(let r) = result else { finish("No download of \(a.name) was found on GitHub."); return }
                let error = JohnnyCastaway.install(from: r.url)
                // The desktop and Program Manager take him in now, not at the next theme switch.
                if error == nil { DispatchQueue.main.async { DesktopIconsController.shared.update(); ProgramManagerController.shared.update() } }
                finish(error.map { "\(a.name) could not be installed (\($0))." })
            }
        case .github(let repo, let asset):
            TrustedDownloadInstaller.latestReleaseAsset(repo: repo, matches: asset) { result in
                switch result {
                case .success(let r): finish(fetch(a, r.url, win))
                case .failure: finish("No download of \(a.name) was found on GitHub.")
                }
            }
        }
    }

    /// The synchronous part, off the main thread.
    private static func fetch(_ a: App, _ url: URL, _ win: NSWindow) -> String? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("app_install_\(a.id)_\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let isZip = url.pathExtension.lowercased() == "zip"
        let archive = tmp.appendingPathComponent(isZip ? "app.zip" : "app.dmg")
        guard TrustedDownloadInstaller.download(url, to: archive, minBytes: 50_000) else {
            return "The download of \(a.name) did not finish."
        }
        DispatchQueue.main.async { InstallProgressWindow.update(win, detail: "Installing \(a.name)…") }
        let found: URL?
        if isZip {
            let out = tmp.appendingPathComponent("x")
            found = TrustedDownloadInstaller.unzip(archive, into: out)
                ? TrustedDownloadInstaller.findAppBundle(named: a.appName, in: out) : nil
        } else {
            found = TrustedDownloadInstaller.withMountedDMG(archive) { mount -> URL? in
                guard let app = TrustedDownloadInstaller.findAppBundle(named: a.appName, in: mount) else { return nil }
                let copy = tmp.appendingPathComponent(app.lastPathComponent)
                return (try? fm.copyItem(at: app, to: copy)) != nil ? copy : nil
            } ?? nil
        }
        guard let app = found else { return "\(a.name) was not in the download." }
        let target = URL(fileURLWithPath: "/Applications").appendingPathComponent(app.lastPathComponent)
        switch TrustedDownloadInstaller.installVerifiedApp(
            bundleAt: app, to: target, expectedBundleID: a.bundleID,
            confirmUnverified: { InstallProgressWindow.confirmUnverified(name: a.name) }) {
        case .installed: return nil
        case .cancelled: return "Not installed."
        case .failed(let why): return "\(a.name) could not be installed (\(why))."
        }
    }
}
