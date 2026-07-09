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
}
