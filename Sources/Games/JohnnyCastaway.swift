import AppKit

/// Johnny Castaway (Screen Antics, Sierra/Dynamix 1992), the Windows 3.1 screen saver, through
/// Open Scrantic: a reimplementation of its engine that reads the original files.
///
/// It is a bare program, not an app, and it reads `SCRANTIC.SCR`, `RESOURCE.MAP` and
/// `RESOURCE.001` from its own folder, so it lives in a folder of RetroMac's, not in
/// /Applications. RetroMac fetches only the program; the three files are Sierra's and come from
/// the user's own copy, asked for the first time it is opened and checked against the hashes
/// Open Scrantic publishes (it rejects any other build).
enum JohnnyCastaway {
    static let repo = "glauberlima/open-scrantic"
    static let asset = "open-scrantic-macos"

    static let folder = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/RetroMac/Johnny Castaway")
    static var program: URL { folder.appendingPathComponent(asset) }

    static let originals: [String: String] = [
        "SCRANTIC.SCR": "7811b526b36bba2f08326d7a680f2f063190b4278e5a36393fde5a02080b0262",
        "RESOURCE.MAP": "3d9ec330aab96bbe5a44ce34f5945703862e82b195088590b7adfef5d7345da7",
        "RESOURCE.001": "df9c2213f7c0abacf4e302cb53a476f9f220579c07ba350b167e351eed548eae",
    ]

    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: program.path) }
    static var hasOriginals: Bool {
        originals.keys.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// The desktop gets him only in the systems he ran on: Windows 3.x, and the 9x line, where
    /// the Windows 3.1 saver still ran.
    static func belongs(onThemeID id: String?) -> Bool {
        guard let id else { return false }
        return ["windows31", "windows95", "windows98", "windowsme"].contains { id.hasSuffix(".\($0)") }
            || id.hasPrefix("com.retromac.microsoft.windows98")
    }

    // MARK: - On the desktop

    /// The icon on the desktop and in Program Manager: Open Scrantic's own logo, fetched with
    /// the program (Sierra's art is not RetroMac's to hand out), a beach umbrella without it.
    static var icon: NSImage? {
        NSImage(contentsOf: folder.appendingPathComponent("icon.png"))
            ?? NSImage(systemSymbolName: "beach.umbrella", accessibilityDescription: "Johnny Castaway")
    }

    /// His icon, for a desktop or a Program Manager group that should show it; nil when he is
    /// not installed or the theme is not one of his systems.
    static func desktopEntry(themeID: String?) -> DockThemeConfig.DesktopIconEntry? {
        guard isInstalled, belongs(onThemeID: themeID) else { return nil }
        return DockThemeConfig.DesktopIconEntry(name: "Johnny Castaway", icon: "", type: "johnnycastaway")
    }

    /// Just installed: the desktop and Program Manager take him in now, not at the next theme switch.
    static func didInstall() {
        DesktopIconsController.shared.update()
        ProgramManagerController.shared.update()
    }

    // MARK: - Install

    /// The latest release's macOS program, checked against the release's own checksums.txt.
    /// Synchronous, off the main thread; nil on success, else what went wrong.
    static func install(from url: URL) -> String? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("castaway_\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let sums = tmp.appendingPathComponent("checksums.txt")
        guard TrustedDownloadInstaller.download(url.deletingLastPathComponent().appendingPathComponent("checksums.txt"), to: sums),
              let text = try? String(contentsOf: sums, encoding: .utf8),
              let sha = checksum(for: asset, in: text) else {
            return "the release lists no checksum for its Mac program"
        }
        let file = tmp.appendingPathComponent(asset)
        guard TrustedDownloadInstaller.download(url, to: file, minBytes: 100_000, sha256: sha) else {
            return "the download did not finish or did not match its checksum"
        }
        // Not signed with a Developer ID: the same question as for any unsigned app.
        guard InstallProgressWindow.confirmUnverified(name: "Johnny Castaway") else {
            return "cancelled"
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fm.removeItem(at: program)
            try fm.moveItem(at: file, to: program)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
            if let logo = URL(string: "https://raw.githubusercontent.com/\(repo)/main/docs/images/open-scrantic-logo.png") {
                TrustedDownloadInstaller.download(logo, to: folder.appendingPathComponent("icon.png"), minBytes: 1_000)
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    /// `<sha256>  <name>` lines, as `shasum -a 256` writes them.
    static func checksum(for name: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name {
                return parts[0].lowercased()
            }
        }
        return nil
    }

    // MARK: - Launch

    /// Full screen, the way the saver ran; Esc ends it. The original files are asked for first
    /// if they are not there yet.
    static func launch() {
        guard isInstalled else {
            alert("Johnny Castaway is not installed", "Install it from RetroHub \u{25B8} Apps.")
            return
        }
        guard hasOriginals || askForOriginals() else { return }
        let p = Process()
        p.executableURL = program
        p.arguments = ["--fullscreen"]
        p.currentDirectoryURL = folder
        do { try p.run() } catch { alert("Johnny Castaway did not start", error.localizedDescription) }
    }

    /// Ask for the folder of the original screen saver; copy its three files in, checked.
    @discardableResult
    static func askForOriginals() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the folder with the original Johnny Castaway files: SCRANTIC.SCR, RESOURCE.MAP and RESOURCE.001."
        panel.prompt = "Use Folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let dir = panel.url else { return false }
        if let problem = copyOriginals(from: dir) {
            alert("These are not the files Johnny Castaway needs", problem)
            return false
        }
        return true
    }

    /// Nil when all three were found (any capitalisation, as a DOS disk may have them), matched
    /// their hashes and were copied; else which one did not.
    static func copyOriginals(from dir: URL) -> String? {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        var found: [String: URL] = [:]
        for (name, sha) in originals {
            guard let match = names.first(where: { $0.uppercased() == name }) else { return "\(name) is not in that folder." }
            let url = dir.appendingPathComponent(match)
            guard TrustedDownloadInstaller.sha256Hex(of: url) == sha else {
                return "\(name) is a different version than the one Open Scrantic reads."
            }
            found[name] = url
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, url) in found {
                let dest = folder.appendingPathComponent(name)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: url, to: dest)
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
