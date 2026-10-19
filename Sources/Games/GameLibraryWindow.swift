import SwiftUI
import AppKit

/// The cover gallery: every game RetroMac can play, with a tick on the ones whose data is
/// already in place.
///
/// It is deliberately not a shop. Two titles are free to distribute and RetroMac fetches those;
/// for the other eight it installs the engine, names the file it wants, finds the copy Steam or
/// Steam already put on this Mac, and otherwise waits for the user to point at their own.
///
/// It is a window of its own rather than a wizard page, because the Setup Assistant is a
/// first-run thing and this is not: people add a game months later. The Games page links into it,
/// and so does the Games menu.
struct GameLibraryView: View {

    @StateObject private var model = GameLibraryModel()
    @StateObject private var apps = AppLibraryModel()
    @StateObject private var themes = ThemeLibraryModel()
    enum Tab: String, CaseIterable { case apps = "Apps", games = "Games", themes = "Themes" }
    /// Games first, as before: every way in but the menu comes from a games page.
    @State private var tab: Tab = .games
    /// Wide enough for the longest button row a card can show — "Install Yamagi Quake II" plus
    /// the menu button — so the row never has to overflow in the first place.
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    switch tab {
                    case .games:  ForEach(InternetArchive.catalogue) { card($0) }
                    case .apps:   ForEach(AppCatalog.catalogue) { appCard($0) }
                    case .themes: ForEach(themes.entries) { themeCard($0) }
                    }
                }
                .padding(16)
                if tab == .themes, let note = themes.note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(32)
                }
            }
            Divider()
            switch tab {
            case .games:  footer
            case .apps:   appsFooter
            case .themes: themesFooter
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { model.refresh(); apps.refresh(); themes.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RetroHub").font(.title2.bold())
                Spacer()
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Text(tab == .games
                 ? "RetroMac installs the engine each game needs, downloads the free and shareware episodes, and finds the game data you already have. Full commercial games come from your own copy."
                 : tab == .apps
                 ? "Real Mac apps in a classic look. RetroMac downloads them from their makers, checks the signature and puts them in Applications. Theme title bars stay off them, since they draw their own."
                 : "Themes that are not built into RetroMac. One press downloads and installs one; it then sits in Settings ▸ Themes like the others.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func card(_ t: InternetArchive.Title) -> some View {
        let installed = model.installed.contains(t.id)
        let busy = model.activeID == t.id
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                cover(t)
                if installed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .padding(6)
                }
            }
            .allowsHitTesting(false)
            Text(t.name).font(.headline).lineLimit(1)
            // The size is what the download costs, so it is only shown where there is one.
            Text(t.freelyDistributable ? "\(t.year) · \(InternetArchive.sizeText(t.bytes))" : t.year)
                .font(.caption).foregroundStyle(.secondary)
            if !installed && !t.freelyDistributable {
                Text(InternetArchive.neededFilesText(t))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sw = t.shareware {
                    Text("Shareware: \(sw.episode) (\(sw.sizeNote))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !installed, let f = model.found[t.id] {
                Text("Found in \(Self.storeName(for: f)).")
                    .font(.caption2).foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !t.engine.isInstalled, t.engine != .bundled {
                Text("Includes \(t.engine.name) (\(t.engine.sizeNote))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let c = t.caveat {
                Text(c).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let e = model.errors[t.id] {
                Text(e).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if busy {
                // Real bytes where there are real bytes to count. The built-in downloaders bring
                // their own progress window and cannot be stopped from here, so those get a
                // spinner and no Cancel rather than a bar stuck at nought under a dead button.
                if model.indeterminate {
                    ProgressView().progressViewStyle(.linear)
                } else {
                    ProgressView(value: model.fraction).progressViewStyle(.linear)
                }
                Text(model.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if !model.indeterminate {
                    Button("Cancel") { model.cancel() }
                        .buttonStyle(.link).font(.caption)
                }
            } else {
                HStack(spacing: 6) {
                    // One primary button per state. A card is 170pt wide, so "Download Again"
                    // next to "Play" next to the menu simply truncated; the rare action moved
                    // into the menu instead of the label being shortened into nonsense.
                    // The label is allowed to shrink; the menu button is not. At a narrow window
                    // a long label ("Install Yamagi Quake II") pushed the menu button past the
                    // edge of its own card, where the next column's cell took the clicks — which
                    // is why it worked as soon as the window was made bigger.
                    if installed && t.engine.isInstalled {
                        Button("Play") { model.play(t) }
                            .lineLimit(1)
                    } else if let action = primaryAction(t, installed: installed) {
                        Button(action.title) { action.run() }
                            .disabled(model.activeID != nil)
                            .lineLimit(1)
                            .layoutPriority(0)
                    }
                    // The menu button sits at the card's trailing edge, which is exactly where a
                    // neighbouring cover used to overflow — see `cover`.
                    Spacer(minLength: 0)
                    // A plain button with its own NSMenu rather than SwiftUI's `Menu`: a
                    // borderless menu is exactly as big as its glyph and takes clicks nowhere
                    // else, which is why half the presses landed on the card instead. This one
                    // has a real 28x22 target.
                    Button {
                        showMoreMenu(for: t, installed: installed)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                            .frame(width: 28, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                    .help("More actions for \(t.name)")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// The card's "more" menu, built as an NSMenu so the button that opens it can be any size.
    private func showMoreMenu(for t: InternetArchive.Title, installed: Bool) {
        let menu = NSMenu()
        func add(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(MenuActions.run(_:)), keyEquivalent: "")
            let holder = MenuActions(action)
            item.target = holder
            item.representedObject = holder      // keeps the target alive while the menu is up
            item.isEnabled = enabled
            menu.addItem(item)
        }

        if installed && t.engine.isInstalled && t.freelyDistributable {
            add("Download Again", enabled: model.activeID == nil) { model.download(t) }
        }
        add("Use My Own Files…") { model.chooseOwnFiles(t) }
        if model.found[t.id] != nil {
            add("Use the Copy Found on This Mac") { model.useFoundCopy(t) }
        }
        // Offered while the game is not installed. The shareware Duke GRP and Quake pak carry
        // the same filenames as the retail ones, and the point of this entry is to try the game,
        // not to put an episode where a full game already is.
        if !installed, let sw = t.shareware {
            add("Download Shareware — \(sw.episode)", enabled: model.activeID == nil) {
                model.downloadShareware(t)
            }
        }
        add("Add Desktop Shortcut") { model.addShortcut(t) }
        if let u = InternetArchive.detailsURL(t) {
            add(t.builtIn == .freedoom ? "Show the project page" : "Show on archive.org") {
                NSWorkspace.shared.open(u)
            }
        }
        if installed {
            menu.addItem(.separator())
            add("Delete Game Data…") { model.deleteData(t) }
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// One button, one press: whatever is still missing, in the order it is missing.
    ///
    /// The engine comes first because data next to an engine that is not there only moves the
    /// dead end one step later. After that the two halves of the catalogue part ways: the free
    /// titles download, the rest take the copy that was found or ask for one.
    private func primaryAction(_ t: InternetArchive.Title, installed: Bool) -> (title: String, run: () -> Void)? {
        if !t.engine.isInstalled && t.engine != .bundled {
            let label = installed || !t.freelyDistributable ? "Install \(t.engine.name)" : "Get Game"
            return (label, { model.download(t) })
        }
        if t.freelyDistributable {
            return (installed ? "Download Again" : "Download", { model.download(t) })
        }
        // Your own copy first, then the free episode, then the file picker. Anything the user
        // already owns beats anything that has to come down the wire.
        if model.found[t.id] != nil { return ("Use Found Copy", { model.useFoundCopy(t) }) }
        guard !installed else { return nil }
        if t.shareware != nil { return ("Get Shareware", { model.downloadShareware(t) }) }
        return ("Choose Files…", { model.chooseOwnFiles(t) })
    }

    /// Which store a found copy came out of, for the line on the card. Read from the path
    /// because that is the only thing that actually knows.
    private static func storeName(for url: URL) -> String {
        let p = url.path
        if p.contains("/Steam/steamapps/") { return "your Steam library" }
        return "\(url.deletingLastPathComponent().lastPathComponent)"
    }

    private func cover(_ t: InternetArchive.Title) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.15))
            if let img = model.covers[t.id] {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: "gamecontroller").font(.system(size: 26)).foregroundStyle(.secondary)
            }
        }
        .frame(height: 110)
        .clipped()
        // `.clipped()` clips what you SEE, not what you can hit. A portrait box shot scaled to
        // fill a 110pt-high box is far taller than that box, and the part hanging below it — over
        // the title, the size and the buttons — still swallowed clicks. Nobody needs to click a
        // cover, so it stops taking them at all.
        .allowsHitTesting(false)
        .onAppear { model.loadCover(t) }
    }

    private func appCard(_ a: AppCatalog.App) -> some View {
        let installed = apps.installed.contains(a.id)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.15))
                    if let img = apps.shots[a.id] {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "macwindow").font(.system(size: 26)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 5))
                if installed {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .green).padding(6)
                }
            }
            .allowsHitTesting(false)   // as with the covers: a filled image overhangs its frame
            .accessibilityHidden(true)
            .onAppear { apps.loadShot(a) }
            Text(a.name).font(.headline).lineLimit(1)
            Text(a.author).font(.caption).foregroundStyle(.secondary)
            Text(a.blurb).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = AppCatalog.archNote(a) ?? a.caveat {
                Text(note).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let e = apps.errors[a.id] {
                Text(e).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if apps.activeID == a.id {
                    ProgressView().controlSize(.small)
                } else if installed {
                    Button("Open") { apps.open(a) }
                } else if case .appStore(let url) = a.source {
                    Button("App Store") { NSWorkspace.shared.open(url) }
                } else if AppCatalog.canInstall(a) {
                    Button("Install") { apps.install(a) }.disabled(apps.activeID != nil)
                }
                Spacer(minLength: 0)
                Button("Website") { NSWorkspace.shared.open(a.page) }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(a.name)\(installed ? ", installed" : "")")
    }

    private func themeCard(_ e: ThemeCatalog.Entry) -> some View {
        let installed = themes.installed.contains(e.id)
        let newer = ThemeCatalog.needsNewerApp(e)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.15))
                    if let img = themes.previews[e.id] {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "paintpalette").font(.system(size: 26)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 5))
                if installed {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .green).padding(6)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { themes.loadPreview(e) }
            Text(e.name).font(.headline).lineLimit(1)
            Text([e.era, e.author].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            Text(e.summary).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let newer {
                Text("Needs RetroMac \(newer) or later.").font(.caption2).foregroundStyle(.secondary)
            }
            if let err = themes.errors[e.id] {
                Text(err).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if themes.activeID == e.id {
                    ProgressView().controlSize(.small)
                } else if installed {
                    Button("Use") { AppSettings.shared.dockTheme = e.id }
                } else {
                    Button("Install") { themes.install(e) }.disabled(themes.activeID != nil || newer != nil)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(e.name)\(installed ? ", installed" : "")")
    }

    private var themesFooter: some View {
        Text("Each theme is checked against the catalogue's checksum before it is installed, and it can only change what a theme may change. Delete one in Settings ▸ Themes.")
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    private var appsFooter: some View {
        Text("Each app belongs to its maker and is fetched from them: GitHub releases, the maker's own site, or the Mac App Store. RetroMac installs only what is signed by its developer, notarised by Apple and carries the expected bundle identifier, unless you allow an exception.")
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RetroMac downloads what its publisher released to be copied: Freedoom, which is free software, and the shareware and demo episodes of Doom, Heretic, Duke Nukem 3D, Quake, Quake II and Shadow Warrior. It does not download the full commercial games. For those, the copy you play has to be your own — bought, on a disc, or already in your Steam library, where RetroMac will look for it.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // No link here on purpose: every card already carries its own source in the "more"
            // menu, as the project page for Freedoom and the item page for the rest. A single
            // footer link could only ever point at one of ten titles.
            Text("The engines are open source and come from their own projects.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

// MARK: - Model

/// Keeps the gallery's state: what is installed, what is downloading, and the cover art.
final class GameLibraryModel: ObservableObject {

    @Published var installed: Set<String> = []
    @Published var covers: [String: NSImage] = [:]
    @Published var errors: [String: String] = [:]
    @Published var activeID: String?
    @Published var fraction: Double = 0
    @Published var status: String = ""
    /// Copies of a title another store already put on this Mac, keyed by title id.
    @Published var found: [String: URL] = [:]
    /// True while a download runs that reports through its own progress window rather than
    /// through this card. Those cannot be cancelled from here, so the card stops pretending:
    /// a spinner instead of a bar frozen at nought, and no Cancel that does nothing.
    @Published var indeterminate = false

    func refresh() {
        installed = Set(InternetArchive.catalogue.filter { InternetArchive.isInstalled($0) }.map(\.id))
        scanForLocalCopies()
    }

    /// Look for Steam copies of everything not already in place. Off the main thread:
    /// this is a few hundred directory listings on a large Steam library, and the gallery has to
    /// draw immediately.
    private func scanForLocalCopies() {
        let wanted = InternetArchive.catalogue.filter { !installed.contains($0.id) }
        guard !wanted.isEmpty else { found = [:]; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let hits = InternetArchive.foundLocally(wanted)
            DispatchQueue.main.async { self.found = hits }
        }
    }

    /// Engine first, then the data, then the tick — the whole thing on one press.
    func download(_ t: InternetArchive.Title) {
        guard activeID == nil else { return }
        errors[t.id] = nil
        activeID = t.id
        fraction = 0
        indeterminate = false
        status = t.engine.isInstalled ? "Starting…" : "Installing \(t.engine.name)…"

        // "Install <engine>" is offered when only the engine is missing, so honour that: fetching
        // 184 MB of data that is already on disk would be a rude reading of one press. When the
        // engine is there, the press came from "Download Again" and means the data.
        //
        // For everything RetroMac does not distribute this press is ONLY ever the engine. The
        // card offers "Choose Files…" for the data, and `InternetArchive.downloadURL` refuses to
        // build a URL anyway, so routing here would end in a bewildering transport error.
        let needsData = t.freelyDistributable && (!installed.contains(t.id) || t.engine.isInstalled)

        // If the downloader is somehow still holding a previous title, say so instead of
        // arming a card that can never finish.
        if GameDownloader.shared.isBusy {
            activeID = nil
            errors[t.id] = "Another download is still running."
            return
        }

        let delegate = NSApp.delegate as? AppDelegate
        delegate?.ensureEngine(t.engine) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.activeID = nil
                self.status = ""
                self.errors[t.id] = "\(t.engine.name) is needed to play \(t.name), and was not installed."
                return
            }
            guard needsData else {
                self.activeID = nil
                self.status = ""
                self.refresh()
                return
            }
            self.fetchData(t)
        }
        if delegate == nil { fetchData(t) }   // no delegate in previews/tests
    }

    // MARK: - Own files, shortcuts, deletion

    /// Point the card at files the user already has. Both readings of "own installation files"
    /// are accepted: a folder (its path becomes the setting, exactly as the Setup Assistant does)
    /// or the files themselves (copied into the folder the engine reads).
    func chooseOwnFiles(_ t: InternetArchive.Title) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose your own \(t.name) files, or the folder they are in"
        panel.prompt = "Use"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        errors[t.id] = nil

        // Warcraft is its own case: the picked folder is either extracted data or a DOS
        // installation that has to go through the extractor first.
        if case .warcraftInstall = t.destination {
            guard let dir = panel.urls.first, dir.hasDirectoryPath else {
                errors[t.id] = "Choose the \(t.name) folder, not a single file."
                return
            }
            adoptWarcraft(t, dir)
            return
        }

        let dirs = panel.urls.filter { $0.hasDirectoryPath }
        let files = panel.urls.filter { !$0.hasDirectoryPath }
        if let dir = dirs.first, files.isEmpty {
            errors[t.id] = InternetArchive.useFolder(dir, for: t)
        } else if !files.isEmpty {
            adoptFiles(t, files)
        }
        refresh()
    }

    /// Take a copy another store already has: the file is copied into the folder the engine
    /// reads rather than the setting being repointed, because `doomWadFolder` is shared by Doom,
    /// Doom II, Heretic and Freedoom — moving it to Steam's Doom folder would un-find the rest.
    func useFoundCopy(_ t: InternetArchive.Title) {
        guard let url = found[t.id] else { return }
        errors[t.id] = nil
        if case .warcraftInstall = t.destination {
            adoptWarcraft(t, url)
        } else {
            adoptFiles(t, [url])
            refresh()
        }
    }

    /// Extracted data is adopted where it lies; an original DOS installation goes through the
    /// extractor first, exactly as the Setup Assistant does it.
    private func adoptWarcraft(_ t: InternetArchive.Title, _ dir: URL) {
        guard case .warcraftInstall(let wc) = t.destination else { return }
        if WarcraftGame.hasExtractedData(at: dir, wc) {
            setWarcraftFolder(wc, dir.path)
            refresh()
        } else if WarcraftGame.looksLikeInstallation(at: dir, wc) {
            activeID = t.id
            status = "Extracting game data…"
            WarcraftGame.extract(wc, from: dir) { [weak self] result in
                guard let self else { return }
                self.activeID = nil
                self.status = ""
                switch result {
                case .success(let dest): self.setWarcraftFolder(wc, dest.path)
                case .failure(let e):    self.errors[t.id] = "Extraction failed: \(e.message)"
                }
                self.refresh()
            }
        } else {
            errors[t.id] = "No \(t.name) data found in that folder."
        }
    }

    /// Copy the user's own files into the folder the engine reads. Never a move: those files
    /// belong to whatever put them there, and a Steam library that loses its WAD fails a
    /// verification the next time Steam looks.
    private func adoptFiles(_ t: InternetArchive.Title, _ files: [URL]) {
        guard let dest = InternetArchive.destinationFolder(t) else {
            errors[t.id] = "No folder is set for \(t.name)."
            return
        }
        do {
            for f in files {
                let to = dest.appendingPathComponent(f.lastPathComponent)
                if FileManager.default.fileExists(atPath: to.path) {
                    try FileManager.default.removeItem(at: to)
                }
                try FileManager.default.copyItem(at: f, to: to)
            }
        } catch {
            errors[t.id] = error.localizedDescription
        }
    }

    private func setWarcraftFolder(_ wc: WarcraftGame.Title, _ path: String) {
        if wc == .warcraft2 { AppSettings.shared.warcraft2DataFolder = path }
        else                { AppSettings.shared.warcraft1DataFolder = path }
    }

    /// Put the game on the themed desktop, the same entry the Setup Assistant writes.
    func addShortcut(_ t: InternetArchive.Title) {
        // `settingsKey`, not `name`: that is the key DesktopIconsController reads
        // (DesktopIconsController.swift:21). Writing under the display name saved the shortcut
        // somewhere nobody looks, so it was created and never appeared.
        guard let key = ThemeManager.shared.activeTheme?.config.settingsKey, !key.isEmpty else {
            errors[t.id] = "Activate a theme first — desktop shortcuts belong to a theme."
            return
        }
        var custom = DesktopStore.load(theme: key)
        guard !custom.added.contains(where: { $0.type == t.id }) else {
            errors[t.id] = "\(t.name) is already on the desktop."
            return
        }
        // No grid position: the desktop places it in the first free cell, which is the only
        // place that knows what the theme's own icons already occupy.
        custom.added.append(DockThemeConfig.DesktopIconEntry(name: t.name, icon: "", type: t.id))
        custom.removed.removeAll { $0 == t.name }
        DesktopStore.save(custom, theme: key)
        DesktopIconsController.shared.update()
        errors[t.id] = nil
    }

    /// Remove what this title installed. Never a silent delete: the sheet names every path, and
    /// data that lives outside RetroMac's own folders is only forgotten, not erased — it may well
    /// be the user's own copy of the game sitting where they put it.
    func deleteData(_ t: InternetArchive.Title) {
        let files = InternetArchive.installedFiles(t)
        guard !files.isEmpty else { return }
        let foreignFolder = InternetArchive.deleteOnlyForgets(t)

        let alert = NSAlert()
        alert.messageText = foreignFolder ? "Forget \(t.name)?" : "Delete \(t.name) game data?"
        alert.informativeText = foreignFolder
            ? "This data is outside RetroMac's own folders, so it looks like your own copy:\n\n\(files.map(\.path).joined(separator: "\n"))\n\nRetroMac will forget the path and leave the files alone."
            : "This deletes:\n\n\(files.map(\.path).joined(separator: "\n"))"
        alert.addButton(withTitle: foreignFolder ? "Forget" : "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        InternetArchive.deleteInstalled(t)
        errors[t.id] = nil
        refresh()
    }

    func play(_ t: InternetArchive.Title) {
        (NSApp.delegate as? AppDelegate)?.launchGame(id: t.id)
    }

    private func fetchData(_ t: InternetArchive.Title) {
        // Freedoom and Shadow Warrior come from their own projects, with their own downloader
        // and its own progress window — no member list to walk.
        if let kind = t.builtIn {
            runBuiltIn(kind, for: t, label: "Downloading \(t.name)…")
            return
        }
        status = "Starting…"
        GameDownloader.shared.fetch(t, progress: { [weak self] p in
            guard let self else { return }
            self.fraction = p.fraction
            // Per member, so a six-file title does not look stuck at 17%.
            let done = ByteCountFormatter.string(fromByteCount: p.received, countStyle: .file)
            let all = ByteCountFormatter.string(fromByteCount: p.expected, countStyle: .file)
            self.status = p.memberCount > 1
                ? "\(done) of \(all) — file \(p.memberIndex + 1) of \(p.memberCount)"
                : "\(done) of \(all)"
        }, status: { [weak self] s in
            self?.status = s
        }, completion: { [weak self] result in
            guard let self else { return }
            self.activeID = nil
            self.status = ""
            if case .failure(let e) = result, case .cancelled = e {
                // A cancel is a choice, not an error worth shouting about.
            } else if case .failure(let e) = result {
                self.errors[t.id] = e.errorDescription ?? "Download failed."
            }
            self.refresh()
        })
    }

    /// Fetch the publisher's shareware or demo episode.
    ///
    /// Same route the launchers have always taken: these downloaders are what happens today when
    /// a game is started with no data at all. The only difference here is that the press said
    /// "get me the data", so the game is not started afterwards.
    func downloadShareware(_ t: InternetArchive.Title) {
        guard let sw = t.shareware, activeID == nil else { return }
        errors[t.id] = nil
        activeID = t.id
        fraction = 0
        indeterminate = true
        status = t.engine.isInstalled ? "Downloading \(sw.episode)…" : "Installing \(t.engine.name)…"

        guard let delegate = NSApp.delegate as? AppDelegate else { finishJob(); return }
        delegate.ensureEngine(t.engine) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.finishJob()
                self.errors[t.id] = "\(t.engine.name) is needed to play \(t.name), and was not installed."
                return
            }
            self.runBuiltIn(sw.source, for: t, label: "Downloading \(sw.episode)…")
        }
    }

    /// Everything that comes from its own downloader rather than from the Archive catalogue.
    private func runBuiltIn(_ kind: InternetArchive.BuiltIn, for t: InternetArchive.Title, label: String) {
        activeID = t.id
        indeterminate = true
        status = label
        guard let delegate = NSApp.delegate as? AppDelegate else { finishJob(); return }
        delegate.fetchBuiltInGame(kind) { [weak self] ok in
            guard let self else { return }
            self.finishJob()
            if !ok { self.errors[t.id] = "The \(t.name) download did not finish." }
            self.refresh()
        }
    }

    private func finishJob() {
        activeID = nil
        status = ""
        indeterminate = false
    }

    func cancel() { GameDownloader.shared.cancel() }

    // MARK: - Covers

    private static var cacheDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/RetroMac/Covers")
    }

    /// Cover art comes from the item itself and never changes, so it is cached on disk: the
    /// gallery then opens instantly, and works with no network at all after the first visit.
    func loadCover(_ t: InternetArchive.Title) {
        guard covers[t.id] == nil else { return }
        let dir = Self.cacheDir
        let file = dir.appendingPathComponent("\(t.id)-\((t.cover as NSString).lastPathComponent)")
        if let img = NSImage(contentsOf: file) { covers[t.id] = img; return }
        guard let url = InternetArchive.coverURL(t) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file)
            DispatchQueue.main.async { self?.covers[t.id] = img }
        }.resume()
    }
}

/// The Apps tab's state: what is installed, which install runs, and the screenshots.
final class AppLibraryModel: ObservableObject {
    @Published var installed: Set<String> = []
    @Published var shots: [String: NSImage] = [:]
    @Published var errors: [String: String] = [:]
    @Published var activeID: String?

    func refresh() {
        installed = Set(AppCatalog.catalogue.filter(AppCatalog.isInstalled).map(\.id))
        AppCatalog.excludeInstalledFromTitleBars()
    }

    func install(_ a: AppCatalog.App) {
        guard activeID == nil else { return }
        errors[a.id] = nil
        activeID = a.id
        AppCatalog.install(a) { [weak self] error in
            self?.activeID = nil
            self?.errors[a.id] = error
            self?.refresh()
        }
    }

    func open(_ a: AppCatalog.App) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.bundleID) else { refresh(); return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    /// Cached next to the game covers, under the app's id, for the same reasons.
    func loadShot(_ a: AppCatalog.App) {
        guard shots[a.id] == nil else { return }
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/RetroMac/Covers")
        let file = dir.appendingPathComponent("app-\(a.id).\(a.screenshot.pathExtension.isEmpty ? "img" : a.screenshot.pathExtension)")
        if let img = NSImage(contentsOf: file) { shots[a.id] = img; return }
        URLSession.shared.dataTask(with: a.screenshot) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file)
            DispatchQueue.main.async { self?.shots[a.id] = img }
        }.resume()
    }
}

/// The Themes tab's state: the catalogue, what is installed, which install runs, previews.
final class ThemeLibraryModel: ObservableObject {
    @Published var entries: [ThemeCatalog.Entry] = []
    @Published var installed: Set<String> = []
    @Published var previews: [String: NSImage] = [:]
    @Published var errors: [String: String] = [:]
    @Published var activeID: String?
    /// What stands in the empty tab: loading, no themes yet, or that the list could not be read.
    @Published var note: String? = "Loading the theme list\u{2026}"

    func load() {
        ThemeCatalog.load { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let list):
                self.entries = list
                self.note = list.isEmpty ? "No themes to download yet. New ones will appear here." : nil
            case .failure:
                self.note = "The theme list could not be loaded. Check the connection and open RetroHub again."
            }
            self.refresh()
        }
    }

    func refresh() { installed = Set(entries.filter(ThemeCatalog.isInstalled).map(\.id)) }

    func install(_ e: ThemeCatalog.Entry) {
        guard activeID == nil else { return }
        errors[e.id] = nil
        activeID = e.id
        ThemeCatalog.install(e) { [weak self] error in
            self?.activeID = nil
            self?.errors[e.id] = error
            self?.refresh()
        }
    }

    func loadPreview(_ e: ThemeCatalog.Entry) {
        guard previews[e.id] == nil, let url = e.preview, url.scheme == "https" else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.previews[e.id] = img }
        }.resume()
    }
}

// MARK: - Controller

final class GameLibraryWindowController: NSObject, NSWindowDelegate {

    static let shared = GameLibraryWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "RetroHub"
        win.contentView = NSHostingView(rootView: GameLibraryView())
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        // Above the Setup Assistant, which is `.floating` and would otherwise cover it.
        win.level = .modalPanel
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}

/// Carries a closure into an NSMenuItem. AppKit menu items need a target and a selector; this is
/// the smallest honest way to give them one from SwiftUI.
private final class MenuActions: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run(_ sender: NSMenuItem) { action() }
}
