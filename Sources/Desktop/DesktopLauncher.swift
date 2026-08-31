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

        case "network":
            // Finder's Network has no path any more: /Network was an autofs trigger and is gone
            // from modern macOS, and opening file:///Network silently lands on the Desktop. The
            // Go menu still has the item, so drive it by its key equivalent (Shift-Cmd-K) rather
            // than by its title, which is localised. Falls back to the mounted volumes.
            let goNetwork = """
            tell application "Finder" to activate
            delay 0.3
            tell application "System Events" to keystroke "k" using {command down, shift down}
            """
            if AXIsProcessTrusted(), let script = NSAppleScript(source: goNetwork) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
                if err == nil { break }
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Volumes"))

        case "url":
            if let urlString = entry.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case "appfolder":
            AppFolderController.shared.show()

        case "tvfolder":
            AppFolderController.tv.show()

        case "defrag":
            // Disk Defragmenter simulation (Windows 95/98 nostalgia; touches no real files).
            DefragController.shared.show()

        case "funstuff":
            // Windows 95 CD-ROM "Fun Stuff" explorer (videos, wallpapers, Hover game).
            AppFolderController.funStuff.show()

        case "cpumonitor":
            CPUMonitorController.shared.show()

        case "clock":
            ClockWidgetController.shared.userShow()   // user opened it → clears the closed flag

        case "nyanochrome":
            NyanochromeController.shared.toggle()

        case "tictactoe":
            TicTacToeController.shared.toggle()

        case "notepad":
            NotepadController.shared.show()

        case "calculator":
            CalculatorController.shared.show()

        case "webapp":
            // Hosted 98.js app (Notepad/Paint/IE/games) in a theme-chromed window.
            if let urlString = entry.url {
                let a = entry.args ?? []
                let w = CGFloat(Int(a.count > 0 ? a[0] : "") ?? 800)
                let h = CGFloat(Int(a.count > 1 ? a[1] : "") ?? 600)
                WebAppController.open(name: entry.name, url: urlString, width: w, height: h, icon: entry.icon)
            }

        case "readme":
            ThemeReadmeController.shared.showForActiveTheme()

        case "screensaver":
            ScreensaverController.shared.start()

        case "dashboard":
            // The Dashboard layer (Mac OS X / Snow Leopard / Mountain Lion).
            DashboardController.shared.toggle()

        case "expose":
            // Exposé (Mac OS X 10.3 to 10.6). `args[0] == "app"` is the old F10, this app's
            // windows only; anything else is F9, everything on the desktop.
            ExposeController.shared.toggle((entry.args?.first == "app") ? .applicationWindows : .allWindows)

        case "sheep":
            // sheep.exe: (re)start the desktop sheep — also re-enables it after Quit Sheep.
            AppSettings.shared.desktopPetEnabled = true

        case "pacman":
            PacmanGame.launch()

        // Native PC games launched from a themed desktop shortcut (added by the Setup Assistant).
        // Doom/Duke3D/Quake go through the AppDelegate's @objc launchers; Warcraft is static.
        case "doom":       (NSApp.delegate as? AppDelegate)?.perform(Selector(("launchDoom1")))
        case "doom2":      (NSApp.delegate as? AppDelegate)?.perform(Selector(("launchDoom2")))
        case "duke3d":     (NSApp.delegate as? AppDelegate)?.perform(Selector(("launchDuke3D")))
        case "quake":      (NSApp.delegate as? AppDelegate)?.perform(Selector(("launchQuake")))
        case "quake2":     (NSApp.delegate as? AppDelegate)?.perform(Selector(("launchQuake2")))
        // Heretic already had an icon and a place in the icon list; only the launch was missing,
        // so a Heretic desktop icon drew correctly and did nothing when opened.
        case "heretic":    (NSApp.delegate as? AppDelegate)?.perform(Selector(("launchHeretic")))
        case "warcraft2":  WarcraftGame.launch(.warcraft2)
        case "warcraft1":  WarcraftGame.launch(.warcraft1)

        default:
            break
        }
    }
}
