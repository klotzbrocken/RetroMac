import AppKit

final class DockWindow: NSPanel {
    /// Above every application window, below the shader overlay at 25 and the start menu at 27.
    /// `DockController` lowers it under the application windows while Live Wallpaper Plus runs.
    static let defaultLevel = 24

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Self.defaultLevel)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        // The dock's own tracking areas report the pointer. Accepting mouse moves on the window
        // as well sent them, while RetroMac was the active app and the dock window key, to the
        // window's first responder instead: the dock heard the pointer enter and leave but
        // nothing in between, and did not magnify until another app's window was clicked. (And a
        // key window hears every move on the screen, not only its own.)
        acceptsMouseMovedEvents = false
        title = "Dock"   // what VoiceOver calls it; nothing shows it
    }

    override var canBecomeKey: Bool { true }
}
