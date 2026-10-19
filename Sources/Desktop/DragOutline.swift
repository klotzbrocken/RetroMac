import AppKit

/// The rectangle that stood in for a window while it was dragged, before systems moved the
/// window itself: Windows inverted a 4-pixel band of halftone grey along the frame, classic
/// Mac OS a 1-pixel grey outline. Neither can invert what lies beneath on macOS; a black and
/// white checker reads the same on any backdrop.
final class DragOutline {
    static let shared = DragOutline()
    private init() {}

    private var panel: NSPanel?
    private let view = OutlineView()

    func show(_ frame: NSRect, windows: Bool) {
        let panel = self.panel ?? make()
        if view.thickness != (windows ? 4 : 1) { view.thickness = windows ? 4 : 1; view.needsDisplay = true }
        if panel.frame.size != frame.size {
            panel.setFrame(frame, display: true)
        } else {
            panel.setFrameOrigin(frame.origin)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() { panel?.orderOut(nil) }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.contentView = view
        panel = p
        return p
    }

    private final class OutlineView: NSView {
        var thickness: CGFloat = 1
        private static let checker: NSColor = {
            let img = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { _ in
                NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill()
                NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1, height: 1).fill(); NSRect(x: 1, y: 1, width: 1, height: 1).fill()
                return true
            }
            return NSColor(patternImage: img)
        }()

        override func draw(_ dirtyRect: NSRect) {
            Self.checker.setFill()
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: bounds.insetBy(dx: thickness, dy: thickness)))
            path.windingRule = .evenOdd
            path.fill()
        }
    }
}
