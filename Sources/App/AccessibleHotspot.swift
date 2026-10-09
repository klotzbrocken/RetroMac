import AppKit

/// One control a custom-drawn view paints itself (a Start button, a clock, a panel slot), as
/// VoiceOver needs it: a name, where it is, and what pressing it does. A view returns these
/// from `accessibilityChildren()`, from `make`, kept up to date with its current layout.
final class AccessibleHotspot: NSAccessibilityElement {
    private var press: () -> Void

    /// The element for this control of `view`, the same object every time it is asked for.
    /// VoiceOver finds its place among a view's children by identity: built fresh at every
    /// question, it reached the second part of the Control Strip and went no further. Keyed by
    /// the label up to its first comma and the place, so "Clock, 16:52" stays one element as the
    /// time moves, and two entries of the same name in a list stay two.
    /// `rect` in `view`'s own coordinates.
    static func make(in view: NSView, label: String, rect: NSRect, role: NSAccessibility.Role = .button,
                     press: @escaping () -> Void) -> AccessibleHotspot {
        let name = label.split(separator: ",").first.map(String.init) ?? label
        let key = "\(role.rawValue)|\(name)|\(Int(rect.minX))|\(Int(rect.minY))" as NSString
        let parts = cache.object(forKey: view) ?? {
            let d = NSMutableDictionary(); cache.setObject(d, forKey: view); return d
        }()
        let part = (parts[key] as? AccessibleHotspot) ?? {
            let p = AccessibleHotspot(press: press); parts[key] = p; return p
        }()
        part.press = press
        part.setAccessibilityParent(view)
        part.setAccessibilityRole(role)
        part.setAccessibilityLabel(label)
        // Screen coordinates, worked out from the view so they follow it when it moves.
        if let window = view.window {
            part.setAccessibilityFrame(window.convertToScreen(view.convert(rect, to: nil)))
        }
        return part
    }
    private static let cache = NSMapTable<NSView, NSMutableDictionary>.weakToStrongObjects()

    private init(press: @escaping () -> Void) {
        self.press = press
        super.init()
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
