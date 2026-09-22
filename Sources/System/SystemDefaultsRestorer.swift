import AppKit

/// The emergency exit, Settings ▸ General ▸ "macOS defaults": put back everything RetroMac
/// can have changed about the system, whether or not RetroMac remembers changing it. The
/// ordinary restore paths put each thing back from its snapshot; this one runs them all and
/// then takes the snapshots' word for nothing — the cursors are re-registered from the
/// factory capture, every cosmetic default a theme may write is deleted (macOS then uses its
/// own defaults), the Dock's own keys go back to stock, the menu bar and the desktop icons
/// come back, and the wallpaper, appearance and Terminal profile are restored.
enum SystemDefaultsRestorer {

    struct Report {
        var lines: [String] = []
        var text: String { lines.joined(separator: "\n") }
    }

    /// Runs on the main thread; the theme and shader have been turned off by the caller.
    /// Returns what was done, for the alert.
    @discardableResult
    static func restoreEverything() -> Report {
        var report = Report()
        let sb = SystemBridge.shared

        // 1. Cursors: the factory capture back in every slot, whatever the flags say.
        CursorThemeManager.shared.restore(force: true)
        report.lines.append("Cursors: the system set is back.")

        // 2. Every cosmetic default a theme or the title bars may write, tracked or not:
        //    first the snapshot's originals, then the keys themselves, so nothing of ours
        //    can be left behind. Deleting a key means macOS uses its own default.
        SystemTweaksAdapter.restore(sync: true)
        var refresh = Set<String>()
        for (domain, key) in SystemTweaksAdapter.allTweakKeys {
            if sb.readDefault(domain, key) != nil {
                _ = sb.runDefaults(["delete", domain, key])
                refresh.formUnion(SystemTweaksAdapter.refreshTargets(domain: domain, refresh: domain == "-g" ? "Finder" : nil))
            }
        }
        UserDefaults.standard.removeObject(forKey: "systemTweaksOriginals")
        UserDefaults.standard.removeObject(forKey: "systemTweaksSnapshotTaken")
        report.lines.append("Window corners, Finder and animation defaults: back to macOS.")

        // 3. The Dock: RetroMac's own recovery first, then the keys it may have written go
        //    back to stock (bottom, shown, genie, launch bounce).
        DockController.shared.restoreSystemDockIfNeeded()
        for key in ["autohide", "autohide-delay", "orientation", "minimize-to-application", "mineffect", "launchanim"] {
            _ = sb.runDefaults(["delete", "com.apple.dock", key])
        }
        refresh.insert("Dock")
        report.lines.append("Dock: shown at the bottom, macOS defaults.")

        // 4. Menu bar and desktop icons back, in case a theme or Retro Mode hid them.
        SystemUIHelper.showMenuBarAndDock()
        SystemUIHelper.setMenuBarAutoHide(false)
        SystemUIHelper.setDesktopIconsHidden(false)
        report.lines.append("Menu bar and desktop icons: shown.")

        // 5. Wallpaper, appearance and accent, the Terminal profile.
        ThemeManager.shared.restoreWallpapers()
        AppearanceAdapter.restore()
        TerminalThemer.restore()
        report.lines.append("Wallpaper, appearance and Terminal profile: restored where RetroMac had changed them.")

        for app in refresh { _ = sb.killall(app) }
        return report
    }
}
