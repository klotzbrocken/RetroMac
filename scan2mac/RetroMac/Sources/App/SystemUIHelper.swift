import Foundation

enum SystemUIHelper {
    static func hideMenuBarAndDock() {
        runAppleScript("tell application \"System Events\" to tell dock preferences to set autohide menu bar to true")
        runAppleScript("tell application \"System Events\" to set the autohide of the dock preferences to true")
    }

    static func showMenuBarAndDock() {
        runAppleScript("tell application \"System Events\" to tell dock preferences to set autohide menu bar to false")
        runAppleScript("tell application \"System Events\" to set the autohide of the dock preferences to false")
    }

    static func testAutomation() -> Bool {
        runAppleScript("tell application \"System Events\" to return name of first process")
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
