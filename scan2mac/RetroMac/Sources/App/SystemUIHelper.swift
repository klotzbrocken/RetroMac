import Foundation

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

        runAppleScript("tell application \"System Events\" to tell dock preferences to set autohide menu bar to true")
        runAppleScript("tell application \"System Events\" to set the autohide of the dock preferences to true")
    }

    static func showMenuBarAndDock() {
        // Restore original values (or fall back to false)
        let menuBarAutoHide = defaults.bool(forKey: savedMenuBarAutoHideKey)
        let dockAutoHide = defaults.bool(forKey: savedDockAutoHideKey)

        runAppleScript("tell application \"System Events\" to tell dock preferences to set autohide menu bar to \(menuBarAutoHide)")
        runAppleScript("tell application \"System Events\" to set the autohide of the dock preferences to \(dockAutoHide)")

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
