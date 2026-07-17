import SwiftUI

struct GamesSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var wadFiles: [String] = []
    @State private var gzdoomInstalled = false
    @State private var grpFiles: [String] = []
    @State private var razeInstalled = false
    @State private var vkQuakeInstalled = false
    @State private var yamagiQ2Installed = false
    /// Per-title message from the last folder pick / extraction (keyed by Title.rawValue).
    @State private var wcStatus: [String: String] = [:]
    /// Title.rawValue of the extraction currently running, if any.
    @State private var wcExtracting: String? = nil

    /// Every CRT preset, grouped as the registry orders them ("" = None).
    private var allPresets: [(String, String)] {
        var list: [(String, String)] = [("", "None")]
        for (_, presets) in PresetRegistry.categorizedPresets {
            for p in presets { list.append((p.id, p.displayName)) }
        }
        return list
    }

    var body: some View {
        Form {
            // One global CRT switch for all bundled PC games (replaces per-game toggles).
            Section("Game effects") {
                Toggle("Apply CRT effect to games", isOn: $settings.gamesCRTEnabled)
                    .toggleStyle(.switch)
                    .tint(.rmAccent)
                Text("Master switch. Doom, Duke Nukem 3D, Heretic, Shadow Warrior and Freedoom load a shader mod into the game engine itself. Warcraft and console ROMs can't do that, so RetroMac lays its own CRT over their window instead — which needs Screen Recording permission. Pick the preset per game below.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Retro Console ROMs (drop zone + library)
            Section("Retro Games") {
                ROMDropZone()
            }
            ROMLibrarySection()

            // Bundled arcade demo
            pacmanSection

            // Warcraft I + II on the bundled Stratagus engine (user supplies game data)
            warcraftSection(.warcraft2)
            warcraftSection(.warcraft1)

            // PC Games (existing — each is its own collapsible section)
            doomSection
            razeSection
            hereticSection
            shadowWarriorSection
            freedoomSection
            quakeSection
            quake2Section

            // Emulators at bottom
            EmulatorStatusSection()
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear {
            gzdoomInstalled = FileManager.default.fileExists(atPath: "/Applications/GZDoom.app")
            razeInstalled = FileManager.default.fileExists(atPath: "/Applications/Raze.app")
            vkQuakeInstalled = FileManager.default.fileExists(atPath: "/Applications/vkQuake.app")
            yamagiQ2Installed = FileManager.default.fileExists(atPath: "/Applications/quake2.app")
                || FileManager.default.fileExists(atPath: "/Applications/Yamagi Quake II.app")
            refreshWadFiles()
            refreshGrpFiles()
        }
    }

    // MARK: - Warcraft I + II (bundled Stratagus engine)

    /// Engine ships with RetroMac; the media comes from the user's own copy of the game.
    /// Mirrors the Doom WAD-folder section: pick a folder, see whether it was recognised.
    @ViewBuilder
    private func warcraftSection(_ title: WarcraftGame.Title) -> some View {
        let engineOK = WarcraftGame.isEngineAvailable(title)
        let dataOK = WarcraftGame.hasExtractedData(title)
        let folder = WarcraftGame.dataFolder(title)

        Section {
            DisclosureGroup(title.displayName) {
                HStack {
                    Image(systemName: engineOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(engineOK ? .green : .red)
                    Text("Stratagus engine")
                    Spacer()
                    Text(engineOK ? "Bundled" : "Not bundled").foregroundStyle(.secondary)
                }
                if !engineOK {
                    Text("The engine is built from the vendored submodules on first build. Requires cmake and pkg-config (brew install cmake pkg-config), then rebuild RetroMac.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Game data")
                        Spacer()
                        if wcExtracting == title.rawValue {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(folder.isEmpty ? "Choose Game…" : "Change…") { chooseWarcraftFolder(title) }
                            if !folder.isEmpty {
                                Button("Clear") {
                                    setWarcraftFolder(title, "")
                                    wcStatus[title.rawValue] = nil
                                }
                            }
                        }
                    }
                    Text(folder.isEmpty ? "Not set" : abbreviatePath(folder))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)

                    if let message = wcStatus[title.rawValue] {
                        HStack(spacing: 4) {
                            let busy = (wcExtracting == title.rawValue)
                            Image(systemName: busy ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(busy ? Color.secondary : Color.orange)
                            Text(message).font(.caption)
                                .foregroundStyle(busy ? Color.secondary : Color.orange)
                        }
                    } else if folder.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary)
                            Text(WarcraftGame.canExtract(title)
                                 ? "Pick your \(title.displayName) folder — the original game or data you already extracted. RetroMac works out which it is."
                                 : "Pick a folder holding your extracted \(title.displayName) data.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if dataOK {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                            Text("Game data ready").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // The engine can't load a shader itself (its GLSL layer is compiled out on
                    // Apple), so this picks what RetroMac lays over the window. One setting for
                    // both Warcraft titles — shown once, on the WC2 section.
                    if title == .warcraft2 {
                        Divider().padding(.vertical, 2)
                        HStack {
                            Text("CRT preset")
                            Spacer()
                            Picker("", selection: $settings.warcraftPresetID) {
                                Text("Follow current preset").tag("")
                                Text("Off").tag("off")
                                Divider()
                                ForEach(allPresets.filter { !$0.0.isEmpty }, id: \.0) { id, name in
                                    Text(name).tag(id)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).frame(width: 200)
                            .disabled(!settings.gamesCRTEnabled)
                        }
                        if !settings.gamesCRTEnabled {
                            Text("Turn “Apply CRT effect to games” on to use this.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    if WarcraftGame.isPlayable(title) {
                        Button("Play \(title.displayName)") { WarcraftGame.launch(title) }
                            .font(.caption)
                    }
                    Text("RetroMac ships the open-source engine and game logic only. The game itself must come from your own copy — it is never bundled.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func setWarcraftFolder(_ title: WarcraftGame.Title, _ path: String) {
        if title == .warcraft2 { settings.warcraft2DataFolder = path }
        else { settings.warcraft1DataFolder = path }
    }

    /// One picker for both cases: hand it either an original game installation — which is
    /// extracted automatically — or a folder someone already extracted. The user shouldn't
    /// have to know which of the two they have, or that an extraction step exists at all.
    private func chooseWarcraftFolder(_ title: WarcraftGame.Title) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your \(title.displayName) folder — the original game or already-extracted data"
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if WarcraftGame.hasExtractedData(at: url, title) {
            setWarcraftFolder(title, url.path)
            wcStatus[title.rawValue] = nil
        } else if WarcraftGame.looksLikeInstallation(at: url, title) {
            wcExtracting = title.rawValue
            wcStatus[title.rawValue] = "Extracting game data — this takes a moment…"
            WarcraftGame.extract(title, from: url) { result in
                wcExtracting = nil
                switch result {
                case .success(let dest):
                    setWarcraftFolder(title, dest.path)
                    wcStatus[title.rawValue] = nil
                case .failure(let error):
                    wcStatus[title.rawValue] = "Extraction failed: \(error.message)"
                }
            }
        } else {
            wcStatus[title.rawValue] = WarcraftGame.canExtract(title)
                ? "No Warcraft data there. Pick the game's own folder (the one with maindat.war) or an extracted data folder."
                : "That folder holds no extracted \(title.displayName) data. RetroMac can't extract this title itself yet — use the Wargus tools to extract it first."
        }
    }

    // MARK: - Doom

    private var doomSection: some View {
        Section {
            DisclosureGroup("Doom") {
            // GZDoom status
            HStack {
                Image(systemName: gzdoomInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(gzdoomInstalled ? .green : .red)
                Text("GZDoom")
                Spacer()
                Text(gzdoomInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(.secondary)
            }

            if !gzdoomInstalled {
                Text("Install GZDoom from zdoom.org to play Doom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // WAD Folder
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("WAD Folder")
                    Spacer()
                    Button("Choose...") {
                        chooseWadFolder()
                    }
                }

                Text(abbreviatePath(settings.doomWadFolder))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !wadFiles.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(wadFiles.count) WAD file\(wadFiles.count == 1 ? "" : "s") found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("No WAD files found in this folder")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Button("Open in Finder") {
                    let url = URL(fileURLWithPath: settings.doomWadFolder)
                    NSWorkspace.shared.open(url)
                }
                .font(.caption)
            }

            }
        }
    }

    // MARK: - Duke Nukem 3D (Raze)

    private var razeSection: some View {
        Section {
            DisclosureGroup("Duke Nukem 3D") {
            // Raze status
            HStack {
                Image(systemName: razeInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(razeInstalled ? .green : .red)
                Text("Raze")
                Spacer()
                Text(razeInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(.secondary)
            }

            if !razeInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Install Raze to play Duke Nukem 3D.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Download Raze") {
                        if let url = URL(string: "https://github.com/ZDoom/Raze/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
            }

            // GRP Folder
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("GRP Folder")
                    Spacer()
                    Button("Choose...") {
                        chooseGrpFolder()
                    }
                }

                Text(abbreviatePath(settings.razeGrpFolder))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !grpFiles.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(grpFiles.count) GRP file\(grpFiles.count == 1 ? "" : "s") found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("No GRP files found — Shareware will be downloaded on first play")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Button("Open in Finder") {
                    let url = URL(fileURLWithPath: settings.razeGrpFolder)
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
                .font(.caption)
            }

            }
        }
    }

    // MARK: - Heretic

    private var pacmanSection: some View {
        Section {
            DisclosureGroup("Pac-Man") {
                HStack {
                    Image(systemName: PacmanGame.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(PacmanGame.isAvailable ? .green : .red)
                    Text("Pac-Man (BeOS demo)")
                    Spacer()
                    Button("Play") { PacmanGame.launch() }
                        .disabled(!PacmanGame.isAvailable)
                }
                Text("Bundled SDL Pac-Man clone. The window frame matches the active theme (BeOS Lasche on the BeOS theme).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hereticSection: some View {
        Section {
            DisclosureGroup("Heretic") {
            // GZDoom status (reused from Doom)
            HStack {
                Image(systemName: gzdoomInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(gzdoomInstalled ? .green : .red)
                Text("GZDoom")
                Spacer()
                Text(gzdoomInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(.secondary)
            }

            Text("Uses GZDoom engine and WAD folder from Doom settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            }
        }
    }

    // MARK: - Shadow Warrior

    private var shadowWarriorSection: some View {
        Section {
            DisclosureGroup("Shadow Warrior") {
            // Raze status (reused from Duke3D)
            HStack {
                Image(systemName: razeInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(razeInstalled ? .green : .red)
                Text("Raze")
                Spacer()
                Text(razeInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(.secondary)
            }

            Text("Uses Raze engine and GRP folder from Duke Nukem 3D settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Freedoom

    private var freedoomSection: some View {
        Section {
            DisclosureGroup("Freedoom") {
            // GZDoom status (shared with Doom/Heretic)
            HStack {
                Image(systemName: gzdoomInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(gzdoomInstalled ? .green : .red)
                Text("GZDoom")
                Spacer()
                Text(gzdoomInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(.secondary)
            }

            Text("Freedoom is a free, open-source replacement for Doom. Auto-downloads on first launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Quake

    private var quakeSection: some View {
        Section {
            DisclosureGroup("Quake") {
            // vkQuake status
            HStack {
                Image(systemName: vkQuakeInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(vkQuakeInstalled ? .green : .red)
                Text("vkQuake")
                Spacer()
                if vkQuakeInstalled {
                    Text("Installed")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Get vkQuake") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/Novum/vkQuake/releases")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            // Lite shader picker
            HStack {
                Text("Overlay Shader")
                Spacer()
                LiteShaderPicker(selection: $settings.quakeLitePreset)
                    .frame(width: 160)
            }

            // Base path
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Base Path")
                    Spacer()
                    Button("Choose...") {
                        chooseQuakeBasePath()
                    }
                }

                Text(abbreviatePath(settings.quakeBasePath))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            }
        }
    }

    // MARK: - Quake II

    private var quake2Section: some View {
        Section {
            DisclosureGroup("Quake II") {
            // Yamagi Quake II status
            HStack {
                Image(systemName: yamagiQ2Installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(yamagiQ2Installed ? .green : .red)
                Text("Yamagi Quake II")
                Spacer()
                if yamagiQ2Installed {
                    Text("Installed")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Get Yamagi Q2") {
                        NSWorkspace.shared.open(URL(string: "https://www.yamagi.org/quake2/")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            // Lite shader picker
            HStack {
                Text("Overlay Shader")
                Spacer()
                LiteShaderPicker(selection: $settings.quake2LitePreset)
                    .frame(width: 160)
            }

            // Base path
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Base Path")
                    Spacer()
                    Button("Choose...") {
                        chooseQuake2BasePath()
                    }
                }

                Text(abbreviatePath(settings.quake2BasePath))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            }
        }
    }

    // MARK: - Helpers

    private func chooseQuakeBasePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.quakeBasePath)
        panel.message = "Select Quake base directory (should contain id1/PAK0.PAK)"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.quakeBasePath = url.path
    }

    private func chooseQuake2BasePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.quake2BasePath)
        panel.message = "Select Quake II base directory (should contain baseq2/pak0.pak)"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.quake2BasePath = url.path
    }

    private func chooseGrpFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.razeGrpFolder)
        panel.message = "Select folder containing Duke Nukem 3D GRP files"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.razeGrpFolder = url.path
        refreshGrpFiles()
    }

    private func refreshGrpFiles() {
        let fm = FileManager.default
        let folder = settings.razeGrpFolder
        guard let contents = try? fm.contentsOfDirectory(atPath: folder) else {
            grpFiles = []
            return
        }
        grpFiles = contents
            .filter { $0.lowercased().hasSuffix(".grp") }
            .sorted()
    }

    private func chooseWadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.doomWadFolder)
        panel.message = "Select folder containing Doom WAD files"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.doomWadFolder = url.path
        refreshWadFiles()
    }

    private func refreshWadFiles() {
        let fm = FileManager.default
        let folder = settings.doomWadFolder
        guard let contents = try? fm.contentsOfDirectory(atPath: folder) else {
            wadFiles = []
            return
        }
        wadFiles = contents
            .filter { $0.lowercased().hasSuffix(".wad") || $0.lowercased().hasSuffix(".pk3") }
            .sorted()
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

}
