import AppKit
import ApplicationServices

/// The small caution sign at the left of the task buttons while RetroMac runs without the
/// Accessibility permission: the buttons are programs, not windows. Drawn, not an asset, so it
/// takes the taskbar's own colours; one click asks the system for the permission.
final class TaskbarNoticeView: NSView {
    var onClick: (() -> Void)?
    private let style: TaskButtonView.Style
    private var pressed = false

    init(frame: NSRect, style: TaskButtonView.Style) {
        self.style = style
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Put up the system's own dialog (which adds RetroMac to the list) and open the pane, the
    /// same two steps Settings ▸ General takes.
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        // Face: the 9x bevel or the Luna/Aero rounded plate, sunken while pressed.
        switch style {
        case .win98:
            NSColor(white: 0.77, alpha: 1).setFill(); b.fill()
            let hi = pressed ? NSColor(white: 0.5, alpha: 1) : .white
            let lo = pressed ? NSColor.white : NSColor(white: 0.5, alpha: 1)
            hi.setFill(); NSRect(x: 0, y: b.height - 1, width: b.width, height: 1).fill(); NSRect(x: 0, y: 0, width: 1, height: b.height).fill()
            lo.setFill(); NSRect(x: 0, y: 0, width: b.width, height: 1).fill(); NSRect(x: b.width - 1, y: 0, width: 1, height: b.height).fill()
        case .winxp, .win7:
            let path = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            (pressed ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 1, alpha: 0.22)).setFill(); path.fill()
            NSColor(white: 0, alpha: 0.25).setStroke(); path.stroke()
        }
        // The caution triangle: yellow, black outline, an exclamation mark.
        let side = min(b.width, b.height) * 0.62
        let cx = b.midX, cy = b.midY
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx, y: cy + side * 0.5))
        tri.line(to: NSPoint(x: cx + side * 0.55, y: cy - side * 0.42))
        tri.line(to: NSPoint(x: cx - side * 0.55, y: cy - side * 0.42))
        tri.close()
        tri.lineJoinStyle = .round
        NSColor(red: 1.0, green: 0.82, blue: 0.1, alpha: 1).setFill(); tri.fill()
        NSColor.black.setStroke(); tri.lineWidth = 1; tri.stroke()
        NSColor.black.setFill()
        NSRect(x: cx - side * 0.07, y: cy - side * 0.12, width: side * 0.14, height: side * 0.36).fill()
        NSRect(x: cx - side * 0.07, y: cy - side * 0.32, width: side * 0.14, height: side * 0.13).fill()
    }

    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false; needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
