import AppKit

/// The Sound Volume module's slider as Mac OS 9 had it: press the module, a Platinum slider
/// stands up above it, drag to the level you want, let go and it is gone. No mute box, no
/// label — the strip's speaker shows the level afterwards.
final class PlatinumVolumeSlider {

    static let shared = PlatinumVolumeSlider()
    private init() {}

    private var panel: NSPanel?
    private var view: SliderView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    var onChange: (() -> Void)?

    static let size = NSSize(width: 26, height: 132)

    /// Stand the slider up above `anchor` (screen, AppKit) and follow the mouse until it is let go.
    func begin(above anchor: NSRect) {
        end()
        let size = Self.size
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 2)
        if let vf = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 2), vf.maxX - size.width - 2)
            if origin.y + size.height > vf.maxY { origin.y = anchor.minY - size.height - 2 }
        }
        let p = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let v = SliderView(frame: NSRect(origin: .zero, size: size))
        v.level = CGFloat(SystemVolume.isMuted ? 0 : (SystemVolume.level ?? 0.5))
        p.contentView = v
        p.orderFrontRegardless()
        panel = p
        view = v
        // The mouse is still down in the strip: the drag comes to us as events, not as
        // mouseDragged on the slider, so both monitors follow it and the release ends it.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] e in
            self?.track(e); return e
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] e in
            self?.track(e)
        }
    }

    private func track(_ e: NSEvent) {
        guard let view, let panel else { return }
        if e.type == .leftMouseUp { end(); return }
        let local = view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let track = view.trackRect
        let level = min(max((local.y - track.minY) / max(1, track.height), 0), 1)
        view.level = level
        SystemVolume.level = Float(level)
        if SystemVolume.isMuted && level > 0 { SystemVolume.isMuted = false }
        onChange?()
    }

    func end() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
        view = nil
        onChange?()
    }

    /// Platinum: a #DADADA plate in a black line with the bevel, a sunken track with seven
    /// tick marks beside it, and the round-shouldered knob of the era's sliders.
    final class SliderView: NSView {
        var level: CGFloat = 0.5 { didSet { needsDisplay = true } }
        var trackRect: NSRect { NSRect(x: bounds.midX - 3, y: 10, width: 6, height: bounds.height - 20) }

        override func draw(_ dirtyRect: NSRect) {
            let b = bounds
            PlatinumBar.bar.setFill(); b.fill()
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: b.width, height: 1).fill(); NSRect(x: 0, y: b.height - 1, width: b.width, height: 1).fill()
            NSRect(x: 0, y: 0, width: 1, height: b.height).fill(); NSRect(x: b.width - 1, y: 0, width: 1, height: b.height).fill()
            NSColor.white.setFill()
            NSRect(x: 1, y: b.height - 2, width: b.width - 2, height: 1).fill(); NSRect(x: 1, y: 1, width: 1, height: b.height - 2).fill()
            NSColor(white: 0.6, alpha: 1).setFill()
            NSRect(x: 1, y: 1, width: b.width - 2, height: 1).fill(); NSRect(x: b.width - 2, y: 1, width: 1, height: b.height - 2).fill()
            // The track: sunken, dark on the top-left, light on the bottom-right.
            let t = trackRect
            NSColor(white: 0.5, alpha: 1).setFill(); t.fill()
            NSColor(white: 0.85, alpha: 1).setFill(); t.insetBy(dx: 1, dy: 1).fill()
            NSColor.black.setFill()
            NSRect(x: t.minX, y: t.minY, width: 1, height: t.height).fill(); NSRect(x: t.minX, y: t.maxY - 1, width: t.width, height: 1).fill()
            NSColor.white.setFill()
            NSRect(x: t.maxX - 1, y: t.minY, width: 1, height: t.height).fill(); NSRect(x: t.minX, y: t.minY, width: t.width, height: 1).fill()
            // Ticks, the seven steps of the sound control panel.
            NSColor.black.setFill()
            for i in 0...7 {
                let y = (t.minY + t.height * CGFloat(i) / 7).rounded()
                NSRect(x: t.minX - 5, y: y, width: 3, height: 1).fill()
            }
            // The knob: a Platinum box with a pointer at the ticks.
            let ky = t.minY + (t.height - 10) * level
            let knob = NSRect(x: t.midX - 7, y: ky, width: 14, height: 10)
            let path = NSBezierPath(roundedRect: knob, xRadius: 2, yRadius: 2)
            NSGradient(starting: NSColor(white: 1, alpha: 1), ending: NSColor(white: 0.6, alpha: 1))?.draw(in: path, angle: -90)
            NSColor(white: 0.133, alpha: 1).setStroke(); path.lineWidth = 1; path.stroke()
            let pointer = NSBezierPath()
            pointer.move(to: NSPoint(x: knob.minX, y: knob.minY + 2)); pointer.line(to: NSPoint(x: knob.minX - 3, y: knob.midY)); pointer.line(to: NSPoint(x: knob.minX, y: knob.maxY - 2)); pointer.close()
            NSColor(white: 0.133, alpha: 1).setFill(); pointer.fill()
        }
    }
}
