import AppKit

extension NSScreen {
    /// The hardware **primary** display — the screen whose frame origin is (0,0).
    ///
    /// Unlike `NSScreen.main`, this is stable: `NSScreen.main` returns the screen that
    /// currently holds the *key window*, so it flips to an external display the moment a
    /// window (e.g. TV Tube) becomes key there. UI that must stay put across monitors
    /// (the dock, "which screen is the external one" checks) should pivot on this instead.
    static var primaryDisplay: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
    }

    /// A **stable** identity for this display, surviving reboots and reconnects.
    ///
    /// `CGDirectDisplayID` is NOT stable — macOS hands the same number to a different physical
    /// monitor after a reboot or a cable swap, which is how a pinned dock silently ends up on
    /// the wrong screen. The display's UUID does not move, so persist that instead.
    var displayUUID: String? {
        let id = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let id, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// The attached screen carrying this UUID, if it is currently connected.
    static func screen(withUUID uuid: String) -> NSScreen? {
        screens.first { $0.displayUUID == uuid }
    }
}
