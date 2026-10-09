import AppKit

/// One control a custom-drawn view paints itself (a Start button, a clock, a panel slot), as
/// VoiceOver needs it: a name, where it is, and what pressing it does. A view returns these
/// from `accessibilityChildren()`, built fresh from its current layout.
final class AccessibleHotspot: NSAccessibilityElement {
    private let press: () -> Void

    /// `rect` in `view`'s own coordinates.
    init(in view: NSView, label: String, rect: NSRect, role: NSAccessibility.Role = .button, press: @escaping () -> Void) {
        self.press = press
        super.init()
        setAccessibilityParent(view)
        setAccessibilityRole(role)
        setAccessibilityLabel(label)
        // Screen coordinates, worked out from the view so they follow it when it moves.
        if let window = view.window {
            setAccessibilityFrame(window.convertToScreen(view.convert(rect, to: nil)))
        }
    }

    override func accessibilityPerformPress() -> Bool { press(); return true }
}

extension NSView {
    /// A right click at the middle of the view, for "show menu" from VoiceOver: the context
    /// menus here are built from the mouse event.
    func syntheticRightClick() -> NSEvent? {
        guard let window else { return nil }
        let p = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        return NSEvent.mouseEvent(with: .rightMouseDown, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }
}
