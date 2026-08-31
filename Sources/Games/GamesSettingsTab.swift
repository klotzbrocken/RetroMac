import SwiftUI

/// Settings that the Game Library window cannot show.
///
/// This tab used to carry a collapsible section per game — Doom, Duke Nukem 3D, Heretic, Shadow
/// Warrior, Freedoom, Quake, Quake II and both Warcrafts — each with an engine status line, a
/// folder picker and a Play button. The Library does all of that now, with cover art, download
/// sizes and a tick on what is installed, so those nine sections were a worse second copy of one
/// window. What is left here is what the Library has no place for: the CRT switches, where the
/// game data lives on disk, ROMs and emulators.
struct GamesSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var wadFiles: [String] = []
    @State private var grpFiles: [String] = []

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
            librarySection

            // One global CRT switch for all bundled PC games (replaces per-game toggles).
            Section("Game effects") {
                Toggle("Apply CRT effect to games", isOn: $settings.gamesCRTEnabled)
                    .toggleStyle(.switch)
                    .tint(.rmAccent)
                Text("Master switch. Doom, Duke Nukem 3D, Heretic, Shadow Warrior and Freedoom load a shader mod into the game engine itself. Warcraft, Quake and console ROMs can't do that, so RetroMac lays its own CRT over their window instead — which needs Screen Recording permission.")
                    .font(.caption).foregroundStyle(.secondary)

                overlayPickers
            }

            dataFoldersSection

            // Retro Console ROMs (drop zone + library)
            Section("Retro Games") {
                ROMDropZone()
            }
            ROMLibrarySection()

            // Bundled arcade demo
            pacmanSection

            // Emulators at bottom
            EmulatorStatusSection()
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear {
            refreshWadFiles()
            refreshGrpFiles()
        }
    }

    // MARK: - The Library

    private var librarySection: some View {
        Section("Games") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Game Library").font(.headline)
                    Text("Every game RetroMac can run: what is installed, what still has to be downloaded, its engine, and where to point it at your own files.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Open…") { GameLibraryWindowController.shared.show() }
            }
        }
    }

    // MARK: - Overlays

    /// Three games cannot load a shader into their own engine, so RetroMac lays one over the
    /// window instead. That choice has nowhere to live in the Library, so it stays here.
    @ViewBuilder
    private var overlayPickers: some View {
        HStack {
            Text("Warcraft I + II")
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
        HStack {
            Text("Quake")
            Spacer()
            LiteShaderPicker(selection: $settings.quakeLitePreset)
                .frame(width: 200)
                .disabled(!settings.gamesCRTEnabled)
        }
        HStack {
            Text("Quake II")
            Spacer()
            LiteShaderPicker(selection: $settings.quake2LitePreset)
                .frame(width: 200)
                .disabled(!settings.gamesCRTEnabled)
        }
        if !settings.gamesCRTEnabled {
            Text("Turn “Apply CRT effect to games” on to use these.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        Text("With a theme active the games open in a borderless window — just the picture, so the CRT sits on the game and not on a title bar. Fullscreen and quitting are in the game's own menu.")
            .font(.caption2).foregroundStyle(.secondary)
    }

    // MARK: - Where the game data lives

    /// The folders themselves, not the games in them: which game is installed is the Library's
    /// business, but "where does RetroMac put a download" belongs in settings.
    private var dataFoldersSection: some View {
        Section("Game data folders") {
            folderRow(title: "Doom WADs", path: settings.doomWadFolder,
                      detail: wadFiles.isEmpty ? "No WAD or PK3 files here"
                                               : "\(wadFiles.count) file\(wadFiles.count == 1 ? "" : "s") — also used by Heretic and Freedoom",
                      choose: chooseWadFolder)
            folderRow(title: "Duke Nukem GRPs", path: settings.razeGrpFolder,
                      detail: grpFiles.isEmpty ? "No GRP files here"
                                               : "\(grpFiles.count) file\(grpFiles.count == 1 ? "" : "s") — also used by Shadow Warrior",
                      choose: chooseGrpFolder)
            folderRow(title: "Quake", path: settings.quakeBasePath,
                      detail: "Base folder, holds id1/pak0.pak",
                      choose: chooseQuakeBasePath)
            folderRow(title: "Quake II", path: settings.quake2BasePath,
                      detail: "Base folder, holds baseq2/pak0.pak",
                      choose: chooseQuake2BasePath)

            // Warcraft is read-only here: its folder is either data the extractor produced or a
            // folder the user picked, and both of those routes run through the Library.
            warcraftFolderRow(.warcraft1)
            warcraftFolderRow(.warcraft2)

            Text("Point a game at files you already have with “Use My Own Files…” in the Game Library.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func folderRow(title: String, path: String, detail: String,
                           choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Button("Choose…", action: choose)
                Button("Open in Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
                .disabled(path.isEmpty || !FileManager.default.fileExists(atPath: path))
            }
            Text(path.isEmpty ? "Not set" : abbreviatePath(path))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func warcraftFolderRow(_ title: WarcraftGame.Title) -> some View {
        let folder = WarcraftGame.dataFolder(title)
        let engineOK = WarcraftGame.isEngineAvailable(title)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.displayName)
                Spacer()
                Button("Open in Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: folder))
                }
                .disabled(folder.isEmpty || !FileManager.default.fileExists(atPath: folder))
            }
            Text(folder.isEmpty ? "Not set" : abbreviatePath(folder))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            if !engineOK {
                // Build-level, not per-game: without the engine neither Warcraft can run at all.
                Text("The Stratagus engine is not in this build. It is compiled from the vendored submodules on first build and needs cmake and pkg-config.")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Bundled arcade demo

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

    // MARK: - Helpers

    private func chooseQuakeBasePath() {
        pickFolder(start: settings.quakeBasePath,
                   message: "Select Quake base directory (should contain id1/PAK0.PAK)") {
            settings.quakeBasePath = $0
        }
    }

    private func chooseQuake2BasePath() {
        pickFolder(start: settings.quake2BasePath,
                   message: "Select Quake II base directory (should contain baseq2/pak0.pak)") {
            settings.quake2BasePath = $0
        }
    }

    private func chooseGrpFolder() {
        pickFolder(start: settings.razeGrpFolder,
                   message: "Select folder containing Duke Nukem 3D GRP files") {
            settings.razeGrpFolder = $0
            refreshGrpFiles()
        }
    }

    private func chooseWadFolder() {
        pickFolder(start: settings.doomWadFolder,
                   message: "Select folder containing Doom WAD files") {
            settings.doomWadFolder = $0
            refreshWadFiles()
        }
    }

    private func pickFolder(start: String, message: String, apply: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: start)
        panel.message = message
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(url.path)
    }

    private func refreshGrpFiles() {
        grpFiles = files(in: settings.razeGrpFolder) { $0.hasSuffix(".grp") }
    }

    private func refreshWadFiles() {
        wadFiles = files(in: settings.doomWadFolder) { $0.hasSuffix(".wad") || $0.hasSuffix(".pk3") }
    }

    private func files(in folder: String, matching: (String) -> Bool) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        return contents.filter { matching($0.lowercased()) }.sorted()
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
