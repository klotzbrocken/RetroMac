import SwiftUI

/// Window size preset for Doom
enum DoomWindowSize: String, CaseIterable, Identifiable {
    case small = "640x480"
    case medium = "800x600"
    case large = "1024x768"
    case hd = "1280x720"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "640 x 480 (VGA)"
        case .medium: return "800 x 600 (SVGA)"
        case .large: return "1024 x 768 (XGA)"
        case .hd: return "1280 x 720 (HD)"
        }
    }

    var width: Int {
        switch self {
        case .small: return 640
        case .medium: return 800
        case .large: return 1024
        case .hd: return 1280
        }
    }

    var height: Int {
        switch self {
        case .small: return 480
        case .medium: return 600
        case .large: return 768
        case .hd: return 720
        }
    }

    init(width: Int, height: Int) {
        switch (width, height) {
        case (800, 600): self = .medium
        case (1024, 768): self = .large
        case (1280, 720): self = .hd
        default: self = .small
        }
    }
}

struct GamesSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var wadFiles: [String] = []
    @State private var gzdoomInstalled = false
    @State private var grpFiles: [String] = []
    @State private var razeInstalled = false
    @State private var vkQuakeInstalled = false
    @State private var yamagiQ2Installed = false

    var body: some View {
        Form {
            // One global CRT switch for all bundled PC games (replaces per-game toggles).
            Section("Game effects") {
                Toggle("Apply CRT effect to games", isOn: $settings.gamesCRTEnabled)
                Text("Adds the bundled CRT shader to Doom, Raze, Heretic, Shadow Warrior and Freedoom.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Retro Console ROMs (drop zone + library)
            Section("Retro Games") {
                ROMDropZone()
            }
            ROMLibrarySection()

            // Bundled arcade demo
            pacmanSection

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
