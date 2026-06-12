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

        case "webapp":
            // Hosted 98.js app (Notepad/Paint/IE/games) in a theme-chromed window.
            if let urlString = entry.url {
                let a = entry.args ?? []
                let w = CGFloat(Int(a.count > 0 ? a[0] : "") ?? 800)
                let h = CGFloat(Int(a.count > 1 ? a[1] : "") ?? 600)
                WebAppController.open(name: entry.name, url: urlString, width: w, height: h)
            }

        case "screensaver":
            ScreensaverController.shared.start()

        case "sheep":
            // sheep.exe: (re)start the desktop sheep — also re-enables it after Quit Sheep.
            AppSettings.shared.desktopPetEnabled = true

        case "pacman":
            PacmanGame.launch()

        default:
            break
        }
    }
}
