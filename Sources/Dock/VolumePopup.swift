import AppKit

/// The little panel the Windows tray speaker opened on a single click: a label, a vertical
/// slider and a Mute box.
///
/// The behaviour is the original's, which is not what people remember: a single click opened
/// THIS, a double click opened the full mixer, and muting was the checkbox in here. Single click
/// to mute is a modern habit, not a Windows one.
final class VolumePopup {

    static let shared = VolumePopup()
    private init() {}

    private var panel: NSPanel?
    private var monitor: Any?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(anchor: NSRect) { isOpen ? close() : show(anchor: anchor) }

    func show(anchor: NSRect) {
        close()
        let size = NSSize(width: 68, height: 152)
        // Sits directly above the tray icon, clamped so it never hangs off the screen edge.
        var x = anchor.midX - size.width / 2
        var y = anchor.maxY + 2
        if let vf = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame {
            x = min(max(x, vf.minX + 2), vf.maxX - size.width - 2)
            y = min(y, vf.maxY - size.height - 2)
        }
        let p = NSPanel(contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: 26)   // above the dock, which is 24
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = VolumePopupView(frame: NSRect(origin: .zero, size: size))
        p.orderFrontRegardless()
        panel = p

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.close()
        }
    }

    func close() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Drawn rather than assembled from AppKit controls: an NSSlider and an NSButton would bring
/// their own macOS look into a Windows 98 taskbar.
private final class VolumePopupView: NSView {

    private var muted = SystemVolume.isMuted
    private var level = CGFloat(SystemVolume.level ?? 0.5)
    private var dragging = false

    private let face = NSColor(srgbRed: 0.769, green: 0.769, blue: 0.769, alpha: 1)   // #C4C4C4
    private var trackRect: NSRect { NSRect(x: bounds.midX - 2, y: 40, width: 4, height: bounds.height - 66) }
    private var muteRect: NSRect { NSRect(x: 8, y: 12, width: 13, height: 13) }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        face.setFill()
        bounds.fill()
        Win98Bevel.raised(bounds)

        let label = "Volume" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Tahoma", size: 11) ?? NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black]
        let ls = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: bounds.midX - ls.width / 2, y: bounds.maxY - ls.height - 6),
                   withAttributes: attrs)

        // Slider track: a thin sunken channel.
        let t = trackRect
        Win98Bevel.sunken(t.insetBy(dx: -1, dy: -1))

        // Thumb: a raised block, low volume at the bottom.
        let thumbH: CGFloat = 11, thumbW: CGFloat = 20
        let ty = t.minY + (t.height - thumbH) * level
        let thumb = NSRect(x: bounds.midX - thumbW / 2, y: ty, width: thumbW, height: thumbH)
        face.setFill(); thumb.fill()
        Win98Bevel.raised(thumb)

        // Mute box + label.
        let m = muteRect
        NSColor.white.setFill(); m.fill()
        Win98Bevel.sunken(m)
        if muted {
            NSColor.black.setStroke()
            let tick = NSBezierPath()
            tick.lineWidth = 1.6
            tick.move(to: NSPoint(x: m.minX + 3, y: m.midY))
            tick.line(to: NSPoint(x: m.midX - 0.5, y: m.minY + 3))
            tick.line(to: NSPoint(x: m.maxX - 2.5, y: m.maxY - 3))
            tick.stroke()
        }
        ("Mute" as NSString).draw(at: NSPoint(x: m.maxX + 5, y: m.minY - 1), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if muteRect.insetBy(dx: -4, dy: -4).contains(p) {
            muted.toggle()
            SystemVolume.isMuted = muted
            level = CGFloat(SystemVolume.level ?? Float(level))
            needsDisplay = true
            return
        }
        dragging = true
        setLevel(at: p)
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        setLevel(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) { dragging = false }

    private func setLevel(at p: NSPoint) {
        let t = trackRect
        level = min(max((p.y - t.minY) / max(1, t.height), 0), 1)
        SystemVolume.level = Float(level)
        // Moving the slider off zero un-mutes, the way the original did.
        if muted && level > 0 { muted = false; SystemVolume.isMuted = false }
        needsDisplay = true
    }
}

/// The two 3D edges every Windows 9x control is built from.
enum Win98Bevel {
    static func raised(_ r: NSRect) { edges(r, tl: NSColor.white, br: NSColor(white: 0.25, alpha: 1)) }
    static func sunken(_ r: NSRect) { edges(r, tl: NSColor(white: 0.25, alpha: 1), br: NSColor.white) }

    private static func edges(_ r: NSRect, tl: NSColor, br: NSColor) {
        tl.setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        br.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }
}
