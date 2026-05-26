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
    @State private var retroArchInstalled = false

    var body: some View {
        Form {
            doomSection
            razeSection
            hereticSection
            shadowWarriorSection
            freedoomSection
            quakeSection
            quake2Section
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear {
            gzdoomInstalled = FileManager.default.fileExists(atPath: "/Applications/GZDoom.app")
            razeInstalled = FileManager.default.fileExists(atPath: "/Applications/Raze.app")
            retroArchInstalled = FileManager.default.fileExists(atPath: "/Applications/RetroArch.app")
            refreshWadFiles()
            refreshGrpFiles()
        }
    }

    // MARK: - Doom

    private var doomSection: some View {
        Section {
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

            Divider()

            // Window Size
            Picker("Window Size", selection: Binding(
                get: { DoomWindowSize(width: settings.doomWindowWidth, height: settings.doomWindowHeight) },
                set: { size in
                    settings.doomWindowWidth = size.width
                    settings.doomWindowHeight = size.height
                }
            )) {
                ForEach(DoomWindowSize.allCases) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.menu)

            Divider()

            // Shader settings
            Text("Shaders")
                .font(.headline)

            Toggle("CRT Effect", isOn: $settings.doomCRTShaderEnabled)
            Text("Classic CRT scanline and curvature effect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Screen Warp", isOn: $settings.doomWarpEnabled)
            Text("Subtle screen distortion for retro feel.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("VHS Noise", isOn: $settings.doomVHSEnabled)
            Text("Adds VHS tape noise and tracking lines.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !hasCRTPK3() {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Shader PK3 not found in app bundle. Shaders won't be applied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Doom", systemImage: "flame")
        }
    }

    // MARK: - Duke Nukem 3D (Raze)

    private var razeSection: some View {
        Section {
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

            Divider()

            // Window Size
            Picker("Window Size", selection: Binding(
                get: { DoomWindowSize(width: settings.razeWindowWidth, height: settings.razeWindowHeight) },
                set: { size in
                    settings.razeWindowWidth = size.width
                    settings.razeWindowHeight = size.height
                }
            )) {
                ForEach(DoomWindowSize.allCases) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.menu)

            Divider()

            // CRT Overlay (uses RetroMac screen overlay, not PK3)
            Toggle("CRT Overlay", isOn: $settings.razeCRTShaderEnabled)
            Text("Apply RetroMac CRT shader overlay to the game window on launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Duke Nukem 3D", systemImage: "bolt.fill")
        }
    }

    // MARK: - Heretic

    private var hereticSection: some View {
        Section {
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

            Divider()

            Toggle("CRT Effect", isOn: $settings.hereticCRTShaderEnabled)
            Text("Classic CRT scanline and curvature effect via PK3 shader.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Heretic", systemImage: "wand.and.stars")
        }
    }

    // MARK: - Shadow Warrior

    private var shadowWarriorSection: some View {
        Section {
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

            Divider()

            Toggle("CRT Overlay", isOn: $settings.shadowWarriorCRTEnabled)
            Text("Apply RetroMac CRT shader overlay to the game window on launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Shadow Warrior", systemImage: "figure.martial.arts")
        }
    }

    // MARK: - Freedoom

    private var freedoomSection: some View {
        Section {
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

            Divider()

            Toggle("CRT Shader", isOn: $settings.freedoomCRTShaderEnabled)
            Text("Native GZDoom CRT shader (no input lag).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Freedoom", systemImage: "shield.fill")
        }
    }

    // MARK: - Quake

    private var quakeSection: some View {
        Section {
            // RetroArch status
            HStack {
                Image(systemName: retroArchInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(retroArchInstalled ? .green : .red)
                Text("RetroArch")
                Spacer()
                Text(retroArchInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(.secondary)
            }

            if !retroArchInstalled {
                Text("RetroArch will be installed automatically on first launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Runs Quake shareware via RetroArch TyrQuake core with native CRT shader.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        } header: {
            Label("Quake", systemImage: "bolt.horizontal.fill")
        }
    }

    // MARK: - Quake II

    private var quake2Section: some View {
        Section {
            // RetroArch status (shared)
            HStack {
                Image(systemName: retroArchInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(retroArchInstalled ? .green : .red)
                Text("RetroArch")
                Spacer()
                Text(retroArchInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(.secondary)
            }

            Text("Runs Quake II demo via RetroArch Vitaquake2 core with native CRT shader.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        } header: {
            Label("Quake II", systemImage: "bolt.horizontal.fill")
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

    private func hasCRTPK3() -> Bool {
        Bundle.main.path(forResource: "RetroMac-CRT", ofType: "pk3") != nil
    }
}
