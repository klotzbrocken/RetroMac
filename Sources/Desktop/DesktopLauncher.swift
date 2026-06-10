import AppKit

/// Shared launcher for desktop/program-manager items. Resolves a DesktopIconEntry's
/// action (app / folder / url / trash) and performs it via NSWorkspace.
enum DesktopLauncher {

    static func launch(_ entry: DockThemeConfig.DesktopIconEntry) {
        switch entry.type {
        case "trash":
            let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
            NSWorkspace.shared.open(trashURL)

        case "app":
            if let bid = entry.bundleID,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let config = NSWorkspace.OpenConfiguration()
                if let args = entry.args {
                    config.arguments = args.map { NSString(string: $0).expandingTildeInPath }
                }
                NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            } else {
                NSSound.beep()
            }

        case "folder":
            if let path = entry.path {
                let expanded = NSString(string: path).expandingTildeInPath
                NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
            }

        case "url":
            if let urlString = entry.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case "appfolder":
            AppFolderController.shared.show()

        case "tvfolder":
            AppFolderController.tv.show()

        case "cpumonitor":
            CPUMonitorController.shared.show()

        case "clock":
            ClockWidgetController.shared.show()

        case "notepad":
            NotepadController.shared.show()

        case "pacman":
            PacmanGame.launch()

        default:
            break
        }
    }
}
