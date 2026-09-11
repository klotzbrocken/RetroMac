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

    var body: some View {
        ScrollView {
            VStack(spacing: RMSpacing.section) {
                libraryCard
                effectsCard
                dataFoldersCard
                romsCard
                pacmanCard
                emulatorsCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onAppear {
            refreshWadFiles()
            refreshGrpFiles()
        }
    }

    // MARK: - The Library

    private var libraryCard: some View {
        RMCard(title: "Game Library",
               subtitle: "Every game RetroMac can run: what is installed, what still has to be downloaded, its engine, and where to point it at your own files.",
               headerAction: AnyView(
                Button("Open\u{2026}") { GameLibraryWindowController.shared.show() }
                    .buttonStyle(RMPrimaryButtonStyle())),
               bodyPadding: 0) {
            Color.clear.frame(height: 0)
        }
    }

    // MARK: - Effects

    /// One switch for all bundled PC games, and the three that cannot load a shader into their
    /// own engine, so RetroMac lays one over the window instead.
    private var effectsCard: some View {
        RMCard(title: "Game effects",
               subtitle: "Doom, Duke Nukem 3D, Heretic, Shadow Warrior and Freedoom load a shader into the engine. Warcraft, Quake and console ROMs get RetroMac's own CRT over their window, which needs Screen Recording.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                RMRow(label: "CRT effect in games") {
                    Toggle("", isOn: $settings.gamesCRTEnabled)
                        .toggleStyle(.switch).tint(.rmAccent).labelsHidden()
                }
                RMRow(label: "Warcraft I + II") {
                    Picker("", selection: $settings.warcraftPresetID) {
                        Text("Follow current preset").tag("")
                        Text("Off").tag("off")
                        Divider()
                        ForEach(PresetRegistry.pickerList.filter { !$0.id.isEmpty }, id: \.id) { entry in
                            Text(entry.name).tag(entry.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 200)
                    .disabled(!settings.gamesCRTEnabled)
                }
                RMRow(label: "Quake") {
                    LiteShaderPicker(selection: $settings.quakeLitePreset)
                        .frame(width: 200)
                        .disabled(!settings.gamesCRTEnabled)
                }
                RMRow(label: "Quake II",
                      hint: "With a theme active the games open in a borderless window, so the CRT sits on the game and not on a title bar.",
                      isLast: true) {
                    LiteShaderPicker(selection: $settings.quake2LitePreset)
                        .frame(width: 200)
                        .disabled(!settings.gamesCRTEnabled)
                }
            }
        }
    }

    // MARK: - Where the game data lives

    /// The folders themselves, not the games in them: which game is installed is the Library's
    /// business, but "where does RetroMac put a download" belongs in settings.
    private var dataFoldersCard: some View {
        RMCard(title: "Game data folders",
               subtitle: "Point a game at files you already have with \u{201C}Use My Own Files\u{2026}\u{201D} in the Game Library.",
               bodyPadding: 0) {
            VStack(spacing: 0) {
                folderRow(title: "Doom WADs", path: settings.doomWadFolder,
                          detail: wadFiles.isEmpty ? "No WAD or PK3 files here"
                                                   : "\(wadFiles.count) file\(wadFiles.count == 1 ? "" : "s"), also used by Heretic and Freedoom",
                          choose: chooseWadFolder)
                folderRow(title: "Duke Nukem GRPs", path: settings.razeGrpFolder,
                          detail: grpFiles.isEmpty ? "No GRP files here"
                                                   : "\(grpFiles.count) file\(grpFiles.count == 1 ? "" : "s"), also used by Shadow Warrior",
                          choose: chooseGrpFolder)
                folderRow(title: "Quake", path: settings.quakeBasePath,
                          detail: "Base folder, holds id1/pak0.pak",
                          choose: chooseQuakeBasePath)
                folderRow(title: "Quake II", path: settings.quake2BasePath,
                          detail: "Base folder, holds baseq2/pak0.pak",
                          choose: chooseQuake2BasePath)
                // Warcraft is read-only here: its folder is either data the extractor produced or a
                // folder the user picked, and both of those routes run through the Library.
                warcraftFolderRow(.warcraft1, isLast: false)
                warcraftFolderRow(.warcraft2, isLast: true)
            }
        }
    }

    private func folderRow(title: String, path: String, detail: String,
                           choose: @escaping () -> Void) -> some View {
        RMRow(label: title,
              hint: (path.isEmpty ? "Not set" : abbreviatePath(path)) + " \u{2014} " + detail) {
            HStack(spacing: 6) {
                Button("Choose\u{2026}", action: choose)
                    .buttonStyle(RMDefaultButtonStyle())
                Button("Show") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
                .buttonStyle(RMGhostButtonStyle())
                .disabled(path.isEmpty || !FileManager.default.fileExists(atPath: path))
            }
        }
    }

    private func warcraftFolderRow(_ title: WarcraftGame.Title, isLast: Bool) -> some View {
        let folder = WarcraftGame.dataFolder(title)
        let engineOK = WarcraftGame.isEngineAvailable(title)
        let where_ = folder.isEmpty ? "Not set" : abbreviatePath(folder)
        // Build-level, not per-game: without the engine neither Warcraft can run at all.
        let hint = engineOK ? where_
            : where_ + " \u{2014} the Stratagus engine is not in this build (it needs cmake and pkg-config to compile)."
        return RMRow(label: title.displayName, hint: hint, isLast: isLast) {
            Button("Show") {
                NSWorkspace.shared.open(URL(fileURLWithPath: folder))
            }
            .buttonStyle(RMGhostButtonStyle())
            .disabled(folder.isEmpty || !FileManager.default.fileExists(atPath: folder))
        }
    }

    // MARK: - ROMs and emulators

    private var romsCard: some View {
        RMCard(title: "Retro games",
               subtitle: "Console ROMs, played through an emulator with the CRT over the window.",
               bodyPadding: RMSpacing.card) {
            VStack(alignment: .leading, spacing: 12) {
                ROMDropZone()
                ROMLibrarySection()
            }
        }
    }

    private var pacmanCard: some View {
        RMCard(title: "Pac-Man", bodyPadding: 0) {
            RMRow(label: "Pac-Man (BeOS demo)",
                  hint: PacmanGame.isAvailable
                    ? "Bundled SDL Pac-Man clone. The window frame follows the active theme."
                    : "Not in this build.",
                  isLast: true) {
                Button("Play") { PacmanGame.launch() }
                    .buttonStyle(RMDefaultButtonStyle())
                    .disabled(!PacmanGame.isAvailable)
            }
        }
    }

    private var emulatorsCard: some View {
        RMCard(title: "Emulators", bodyPadding: 0) {
            EmulatorStatusSection()
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
