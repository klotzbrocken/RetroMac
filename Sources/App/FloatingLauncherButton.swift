import AppKit

/// A small, semi-transparent, draggable button that floats above everything (bottom-right
/// corner by default). It shows RetroMac's menu-bar icon; a click opens the Dock-Mode
/// launcher popover, a drag repositions it (position is remembered). Independent of Dock Mode.
final class FloatingLauncherButton {
    static let shared = FloatingLauncherButton()

    private var window: NSWindow?
    private let posKey = "floatingLauncherOrigin"
    private let side: CGFloat = 52

    var isVisible: Bool { window?.isVisible == true }
    /// The button's window — exposed so the launcher's dismiss monitor can ignore clicks on it.
    var buttonWindow: NSWindow? { window }

    func setEnabled(_ on: Bool) { on ? show() : hide() }
    func toggle() { isVisible ? hide() : show() }

    func show() {
        if window == nil { build() }
        positionIfNeeded()
        window?.orderFrontRegardless()
    }

    func hide() { window?.orderOut(nil) }

    /// Redraw the icon (e.g. after the shader active-state changes the menu-bar glyph).
    func refreshIcon() { window?.contentView?.needsDisplay = true }

    private func build() {
        let view = FloatingButtonView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.onClick = { [weak self] in LauncherController.shared.toggle(anchorRect: self?.window?.frame) }
        view.onMoved = { [weak self] origin in self?.saveOrigin(origin) }

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.ignoresMouseEvents = false
        win.alphaValue = 0.5
        win.contentView = view
        view.hostWindow = win
        window = win
    }

    private func positionIfNeeded() {
        guard let win = window else { return }
        if let saved = UserDefaults.standard.string(forKey: posKey) {
            let p = NSPointFromString(saved)
            // Clamp to a visible screen so a button saved off a now-disconnected display returns.
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }) ?? NSScreen.main {
                let vf = screen.visibleFrame
                let x = min(max(p.x, vf.minX), vf.maxX - side)
                let y = min(max(p.y, vf.minY), vf.maxY - side)
                win.setFrameOrigin(NSPoint(x: x, y: y))
                return
            }
        }
        // Default: bottom-right corner of the main screen.
        if let vf = NSScreen.main?.visibleFrame {
            win.setFrameOrigin(NSPoint(x: vf.maxX - side - 20, y: vf.minY + 20))
        }
    }

    private func saveOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: posKey)
    }
}

/// The button's content view: a translucent disc with the menu-bar icon, draggable, and
/// click-vs-drag aware. Hover raises the window's opacity so it stays unobtrusive at rest.
private final class FloatingButtonView: NSView {
    var onClick: (() -> Void)?
    var onMoved: ((NSPoint) -> Void)?
    weak var hostWindow: NSWindow?

    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var didDrag = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); tracking = t
    }

    override func draw(_ dirtyRect: NSRect) {
        let disc = bounds.insetBy(dx: 4, dy: 4)
        let path = NSBezierPath(ovalIn: disc)
        NSColor(white: 0.08, alpha: 0.45).setFill(); path.fill()
        NSColor(white: 1, alpha: 0.18).setStroke(); path.lineWidth = 1; path.stroke()

        let iconSide: CGFloat = 24
        let iconRect = NSRect(x: bounds.midX - iconSide / 2, y: bounds.midY - iconSide / 2,
                              width: iconSide, height: iconSide)
        if let base = (NSApp.delegate as? AppDelegate)?.menuBarIconImage(size: NSSize(width: iconSide, height: iconSide)) {
            tinted(base, .white).draw(in: iconRect)
        }
    }

    /// Recolour a template glyph so it reads on the dark translucent disc.
    private func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let img = image.copy() as! NSImage
        img.lockFocus()
        color.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    override func mouseEntered(with event: NSEvent) {
        hostWindow?.animator().alphaValue = 0.95
    }
    override func mouseExited(with event: NSEvent) {
        hostWindow?.animator().alphaValue = 0.5
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = hostWindow?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        if abs(dx) > 3 || abs(dy) > 3 { didDrag = true }
        hostWindow?.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            if let origin = hostWindow?.frame.origin { onMoved?(origin) }
        } else {
            onClick?()
        }
    }
}
