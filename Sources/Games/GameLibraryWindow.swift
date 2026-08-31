import SwiftUI
import AppKit

/// The cover gallery: every title RetroMac can fetch from the Internet Archive, with a tick on
/// the ones whose data is already in place.
///
/// It is a window of its own rather than a wizard page, because the Setup Assistant is a
/// first-run thing and this is not: people add a game months later. The Games page links into it,
/// and so does the Games menu.
struct GameLibraryView: View {

    @StateObject private var model = GameLibraryModel()
    private let columns = [GridItem(.adaptive(minimum: 176), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(InternetArchive.catalogue) { card($0) }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Game Library").font(.title2.bold())
            Text("One press gets everything a game needs: the engine from its own project, and the game data from the Internet Archive.")
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
            Text(t.name).font(.headline).lineLimit(1)
            Text("\(t.year) · \(InternetArchive.sizeText(t.bytes))")
                .font(.caption).foregroundStyle(.secondary)
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
                // Real bytes, not a spinner: these are up to 184 MB.
                ProgressView(value: model.fraction)
                    .progressViewStyle(.linear)
                Text(model.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Button("Cancel") { model.cancel() }
                    .buttonStyle(.link).font(.caption)
            } else {
                HStack(spacing: 8) {
                    // One primary button per state. A card is 170pt wide, so "Download Again"
                    // next to "Play" next to the menu simply truncated; the rare action moved
                    // into the menu instead of the label being shortened into nonsense.
                    if installed && t.engine.isInstalled {
                        Button("Play") { model.play(t) }
                    } else {
                        Button(buttonTitle(t, installed: installed)) { model.download(t) }
                            .disabled(model.activeID != nil)
                    }
                    Menu {
                        if installed && t.engine.isInstalled {
                            Button("Download Again") { model.download(t) }
                                .disabled(model.activeID != nil)
                        }
                        Button("Use My Own Files…") { model.chooseOwnFiles(t) }
                        Button("Add Desktop Shortcut") { model.addShortcut(t) }
                        if let u = InternetArchive.detailsURL(t) {
                            Link(t.builtIn == .freedoom ? "Show the project page" : "Show on archive.org",
                                 destination: u)
                        }
                        if installed {
                            Divider()
                            Button("Delete Game Data…", role: .destructive) { model.deleteData(t) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    /// One button, one press: whatever is still missing. Downloading data next to an engine that
    /// is not there just moves the dead end one step later.
    private func buttonTitle(_ t: InternetArchive.Title, installed: Bool) -> String {
        if !t.engine.isInstalled && t.engine != .bundled { return installed ? "Install \(t.engine.name)" : "Get Game" }
        return installed ? "Download Again" : "Download"
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
        .onAppear { model.loadCover(t) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Freedoom and Shadow Warrior's shareware episode are free to distribute. Everything else is hosted by the Internet Archive, not by RetroMac, and none of those items states a licence: downloading them is your own decision and your own responsibility, and in most countries you need to own the game.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("archive.org", destination: URL(string: "https://archive.org")!)
                    .font(.caption2)
                Spacer()
                Text("Total if you take everything: \(InternetArchive.sizeText(InternetArchive.catalogue.reduce(0) { $0 + $1.bytes }))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
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

    func refresh() {
        installed = Set(InternetArchive.catalogue.filter { InternetArchive.isInstalled($0) }.map(\.id))
    }

    /// Engine first, then the data, then the tick — the whole thing on one press.
    func download(_ t: InternetArchive.Title) {
        guard activeID == nil else { return }
        errors[t.id] = nil
        activeID = t.id
        fraction = 0
        status = t.engine.isInstalled ? "Starting…" : "Installing \(t.engine.name)…"

        // "Install <engine>" is offered when only the engine is missing, so honour that: fetching
        // 184 MB of data that is already on disk would be a rude reading of one press. When the
        // engine is there, the press came from "Download Again" and means the data.
        let needsData = !installed.contains(t.id) || t.engine.isInstalled

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
        if case .warcraftInstall(let wc) = t.destination {
            guard let dir = panel.urls.first, dir.hasDirectoryPath else {
                errors[t.id] = "Choose the \(t.name) folder, not a single file."
                return
            }
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
            return
        }

        let dirs = panel.urls.filter { $0.hasDirectoryPath }
        let files = panel.urls.filter { !$0.hasDirectoryPath }

        if let dir = dirs.first, files.isEmpty {
            errors[t.id] = InternetArchive.useFolder(dir, for: t)
        } else if !files.isEmpty {
            guard let dest = InternetArchive.destinationFolder(t) else {
                errors[t.id] = "No folder is set for \(t.name)."
                return
            }
            do {
                for f in files {
                    try FileManager.default.copyItem(at: f, to: dest.appendingPathComponent(f.lastPathComponent))
                }
            } catch {
                errors[t.id] = error.localizedDescription
            }
        }
        refresh()
    }

    private func setWarcraftFolder(_ wc: WarcraftGame.Title, _ path: String) {
        if wc == .warcraft2 { AppSettings.shared.warcraft2DataFolder = path }
        else                { AppSettings.shared.warcraft1DataFolder = path }
    }

    /// Put the game on the themed desktop, the same entry the Setup Assistant writes.
    func addShortcut(_ t: InternetArchive.Title) {
        guard let themeName = ThemeManager.shared.activeTheme?.config.name, !themeName.isEmpty else {
            errors[t.id] = "Activate a theme first — desktop shortcuts belong to a theme."
            return
        }
        var custom = DesktopStore.load(theme: themeName)
        guard !custom.added.contains(where: { $0.type == t.id }) else {
            errors[t.id] = "\(t.name) is already on the desktop."
            return
        }
        let nextRow = (custom.added.compactMap { $0.gridY }.max() ?? 6) + 1
        custom.added.append(DockThemeConfig.DesktopIconEntry(
            name: t.name, icon: "", type: t.id, gridX: 0, gridY: nextRow))
        DesktopStore.save(custom, theme: themeName)
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
            status = "Downloading \(t.name)…"
            (NSApp.delegate as? AppDelegate)?.fetchBuiltInGame(kind) { [weak self] ok in
                guard let self else { return }
                self.activeID = nil
                self.status = ""
                if !ok { self.errors[t.id] = "The \(t.name) download did not finish." }
                self.refresh()
            }
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
        win.title = "Game Library"
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
