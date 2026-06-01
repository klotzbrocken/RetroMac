import AppKit

/// Helper to launch or download+install Re:Amp (a Winamp clone for macOS).
/// Used by the Start Menu (Windows 98 / Windows XP themes) and the menu bar dropdown.
enum ReAmpHelper {
    static let bundleID = "ru.alexfreud.ReAmp"
    static let downloadURL = URL(string: "https://re-amp.ru/en")!

    /// Check common install locations for Re:Amp
    static var installedURL: URL? {
        let fm = FileManager.default
        // Check /Applications
        let appPaths = [
            "/Applications/Reamp.app",
            "/Applications/Reamp 2.app",
            "/Applications/Re-Amp.app",
        ]
        for path in appPaths {
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Check ~/Downloads (common for first-time users)
        let home = fm.homeDirectoryForCurrentUser
        let dlPaths = [
            home.appendingPathComponent("Downloads/Reamp.app"),
            home.appendingPathComponent("Downloads/Reamp 2.app"),
        ]
        for url in dlPaths {
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
        // Try NSWorkspace
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        return nil
    }

    /// Launch Re:Amp if installed, otherwise offer to download it.
    static func launchOrInstall() {
        if let url = installedURL {
            NSWorkspace.shared.open(url)
        } else {
            // Ask user to download
            let alert = NSAlert()
            alert.messageText = "Re:Amp not found"
            alert.informativeText = "Re:Amp is a free Winamp-style music player for macOS.\n\nWould you like to download it?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }
}
