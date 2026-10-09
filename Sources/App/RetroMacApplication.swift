import AppKit

/// RetroMac's application object. Its one job: what VoiceOver and the other assistive tools
/// see as RetroMac's windows.
///
/// RetroMac draws over other apps with windows of its own: the shader, the title bars and their
/// lights over every app window, the minimise and roll-up animations. To VoiceOver each was an
/// untitled window with nothing in it, a dozen of them in the Window Chooser at once. They are
/// left out of the application's accessible windows here, in one place, so new ones are too.
/// The windows people work with (dock, desktop, panels, widgets, settings) stay in.
final class RetroMacApplication: NSApplication {
    override func accessibilityChildren() -> [Any]? {
        super.accessibilityChildren()?.filter { !Self.isDecorative($0) }
    }

    override func accessibilityWindows() -> [Any]? {
        super.accessibilityWindows()?.filter { !Self.isDecorative($0) }
    }

    /// Only drawing, nothing to read or press: a window the mouse goes straight through (the
    /// shader, the animations), or a title bar or its lights, which stand over another app's
    /// window whose own controls VoiceOver already reaches.
    static func isDecorative(_ element: Any) -> Bool {
        guard let w = element as? NSWindow else { return false }
        if w.ignoresMouseEvents { return true }
        guard let content = w.contentView else { return false }
        func isBar(_ v: NSView) -> Bool { v is TitleBarOverlayView || v is LightsPatchView }
        return isBar(content) || content.subviews.contains(where: isBar)   // Aero puts its bar on a glass view
    }
}
