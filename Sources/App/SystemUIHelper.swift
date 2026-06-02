import AppKit

enum SystemUIHelper {
    private static let defaults = UserDefaults.standard
    private static let savedMenuBarAutoHideKey = "systemUI_originalMenuBarAutoHide"
    private static let savedDockAutoHideKey = "systemUI_originalDockAutoHide"
    private static let hasSavedStateKey = "systemUI_hasSavedState"

    static func hideMenuBarAndDock() {
        // Save original state if not already saved
        if !defaults.bool(forKey: hasSavedStateKey) {
            let menuBarAutoHide = readAppleScriptBool(
                "tell application \"System Events\" to tell dock preferences to return autohide menu bar"
            )
            let dockAutoHide = readAppleScriptBool(
                "tell application \"System Events\" to return the autohide of the dock preferences"
            )
            defaults.set(menuBarAutoHide, forKey: savedMenuBarAutoHideKey)
            defaults.set(dockAutoHide, forKey: savedDockAutoHideKey)
            defaults.set(true, forKey: hasSavedStateKey)
            print("[SystemUI] Saved original state: menuBarAutoHide=\(menuBarAutoHide), dockAutoHide=\(dockAutoHide)")
        }

        let ok1 = runAppleScript("tell application \"System Events\" to tell dock preferences to set autohide menu bar to true")
        let ok2 = runAppleScript("tell application \"System Events\" to set the autohide of the dock preferences to true")
        if !ok1 { setMenuBarAutoHideViaDefaults(true) }
        if !ok2 {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            task.arguments = ["write", "com.apple.dock", "autohide", "-bool", "true"]
            try? task.run()
            task.waitUntilExit()
            let killDock = Process()
            killDock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killDock.arguments = ["Dock"]
            try? killDock.run()
            killDock.waitUntilExit()
        }
    }

    static func showMenuBarAndDock() {
        // Restore original values (or fall back to false)
        let menuBarAutoHide = defaults.bool(forKey: savedMenuBarAutoHideKey)
        let dockAutoHide = defaults.bool(forKey: savedDockAutoHideKey)

        let ok1 = runAppleScript("tell application \"System Events\" to tell dock preferences to set autohide menu bar to \(menuBarAutoHide)")
        let ok2 = runAppleScript("tell application \"System Events\" to set the autohide of the dock preferences to \(dockAutoHide)")
        if !ok1 { setMenuBarAutoHideViaDefaults(menuBarAutoHide) }
        if !ok2 {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            task.arguments = ["write", "com.apple.dock", "autohide", "-bool", dockAutoHide ? "true" : "false"]
            try? task.run()
            task.waitUntilExit()
            let killDock = Process()
            killDock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killDock.arguments = ["Dock"]
            try? killDock.run()
            killDock.waitUntilExit()
        }

        // Clear saved state
        defaults.removeObject(forKey: savedMenuBarAutoHideKey)
        defaults.removeObject(forKey: savedDockAutoHideKey)
        defaults.set(false, forKey: hasSavedStateKey)
        print("[SystemUI] Restored original state: menuBarAutoHide=\(menuBarAutoHide), dockAutoHide=\(dockAutoHide)")
    }

    /// Restore system UI on launch if app crashed while UI was hidden
    static func restoreIfNeeded() {
        if defaults.bool(forKey: hasSavedStateKey) {
            print("[SystemUI] Found unsaved state from previous session — restoring")
            showMenuBarAndDock()
        }
    }

    static func testAutomation() -> Bool {
        runAppleScript("tell application \"System Events\" to return name of first process")
    }

    // MARK: - Menu Bar Auto-Hide

    static func setMenuBarAutoHide(_ hide: Bool) {
        // Primary: AppleScript via System Events (updates both preference and live state)
        let success = runAppleScript(
            "tell application \"System Events\" to tell dock preferences to set autohide menu bar to \(hide)"
        )

        if !success {
            // Fallback when Automation permission is denied (TCC error -1743):
            // Write the defaults key directly + notify the Dock via DistributedNotification
            setMenuBarAutoHideViaDefaults(hide)
        }

        print("[SystemUI] Menu bar auto-hide: \(hide) (AppleScript: \(success ? "ok" : "fallback"))")
    }

    private static func setMenuBarAutoHideViaDefaults(_ hide: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "NSGlobalDomain", "_HIHideMenuBar", "-bool", hide ? "true" : "false"]
        try? task.run()
        task.waitUntilExit()

        // Post the notification that the Dock listens to for menu bar state changes
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    // MARK: - Dock Auto-Hide

    static func setDockAutoHide(_ hide: Bool) {
        let ok = runAppleScript("tell application \"System Events\" to set the autohide of the dock preferences to \(hide)")
        if !ok {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            task.arguments = ["write", "com.apple.dock", "autohide", "-bool", hide ? "true" : "false"]
            try? task.run()
            task.waitUntilExit()
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            kill.arguments = ["Dock"]
            try? kill.run()
            kill.waitUntilExit()
        }
        print("[SystemUI] Dock auto-hide: \(hide) (AppleScript: \(ok ? "ok" : "fallback"))")
    }

    // MARK: - Desktop Icons

    static func setDesktopIconsHidden(_ hidden: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"]
        try? task.run()
        task.waitUntilExit()

        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Finder"]
        try? killall.run()
        killall.waitUntilExit()
        print("[SystemUI] Desktop icons hidden: \(hidden)")
    }

    private static func readAppleScriptBool(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return false }
        return result.booleanValue
    }

    @discardableResult
    static func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("[SystemUI] AppleScript error: \(error)")
            return false
        }
        return true
    }
}
