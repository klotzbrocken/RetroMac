import AppKit

/// AmigaOS's RAM Disk: a private place for this session's scraps. Here it is a folder in the
/// user's own temporary directory (not the shared /tmp), made when first opened. It outlives a
/// theme switch and a RetroMac restart; macOS clears it when the Mac restarts, as RAM: was
/// gone after a reboot. RetroMac never empties it itself: that would lose someone's file.
enum AmigaRAMDisk {
    static let token = "RAM:"
    static var url: URL { FileManager.default.temporaryDirectory.appendingPathComponent("RetroMac RAM Disk", isDirectory: true) }

    /// A desktop entry's path as a real one: "RAM:" is the RAM Disk, "SYS:" (the Workbench's
    /// System drawer, see `AmigaDrawer`) the startup disk, "~" the home folder.
    static func resolve(_ path: String) -> String {
        if path == "SYS:" { return "/" }
        guard path == token else { return NSString(string: path).expandingTildeInPath }
        for d in standardDrawers {
            try? FileManager.default.createDirectory(at: url.appendingPathComponent(d, isDirectory: true), withIntermediateDirectories: true)
        }
        writeEnvironment()
        return url.path
    }

    /// ENV:'s variables as AmigaOS kept them, small text files, with what the Mac has for each:
    /// the language, the Workbench (RetroMac's version) and the Kickstart (the Mac's system).
    /// Written fresh each time the RAM Disk is opened; only these three, never anything else.
    static func environment(languageCode: String = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en",
                            appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                            os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> [String: String] {
        let language = Locale(identifier: languageCode).localizedString(forLanguageCode: languageCode)?.lowercased() ?? languageCode
        return ["Language": language,
                "Workbench": "RetroMac \(appVersion)",
                "Kickstart": "macOS \(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")]
    }

    private static func writeEnvironment() {
        let env = url.appendingPathComponent("ENV", isDirectory: true)
        // Each with a .info beside it, so the Workbench shows it under "Only icons" (the
        // project icon of the theme, when one is on).
        let icon = ThemeManager.shared.activeTheme?.iconResource("project.png").flatMap { try? Data(contentsOf: $0) }
        for (name, value) in environment() {
            try? Data((value + "\n").utf8).write(to: env.appendingPathComponent(name))
            if let icon { try? icon.write(to: env.appendingPathComponent(name + ".info")) }
        }
    }

    /// What AmigaOS puts in RAM: at every boot: the clipboard units, the live environment
    /// variables and the T: scratch drawer. Made when missing, never cleared.
    static let standardDrawers = ["Clipboards", "ENV", "T"]
}
