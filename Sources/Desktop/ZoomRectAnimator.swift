import AppKit

/// Reproduces the classic Windows "animated rectangles" minimize/restore effect:
/// a wireframe rectangle that steps (not smoothly tweens) between the window frame
/// and the target icon over a handful of discrete frames. The stepped, slightly
/// jerky motion is what reads as authentically retro (DrawAnimatedRects).
final class ZoomRectAnimator {

    private weak var host: NSView?
    private var overlay: WireOverlay?
    private var timer: Timer?
    private var step = 0
    private let steps = 14
    private var from: NSRect = .zero
    private var to: NSRect = .zero
    private var completion: (() -> Void)?

    /// speedMultiplier > 1 makes the animation faster (shorter per-step interval).
    func animate(in host: NSView, from: NSRect, to: NSRect,
                 speedMultiplier: CGFloat = 1.0, completion: @escaping () -> Void) {
        self.host = host
        self.from = from
        self.to = to
        self.completion = completion
        self.step = 0

        let ov = WireOverlay(frame: host.bounds)
        ov.autoresizingMask = [.width, .height]
        ov.useFlipped = host.isFlipped
        ov.rect = from
        host.addSubview(ov)
        overlay = ov

        // ~45ms per step → ~630ms total, deliberately slow and stepped (retro).
        let interval = 0.045 / Double(max(0.25, speedMultiplier))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = timer { RunLoop.current.add(t, forMode: .eventTracking) }
    }

    private func tick() {
        step += 1
        let t = CGFloat(step) / CGFloat(steps)
        if step >= steps {
            timer?.invalidate(); timer = nil
            overlay?.removeFromSuperview(); overlay = nil
            completion?(); completion = nil
            return
        }
        let r = NSRect(
            x: from.minX + (to.minX - from.minX) * t,
            y: from.minY + (to.minY - from.minY) * t,
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t
        )
        overlay?.rect = r
        overlay?.needsDisplay = true
    }
}

private final class WireOverlay: NSView {
    var rect: NSRect = .zero
    var useFlipped = false
    override var isFlipped: Bool { useFlipped }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // pass clicks through

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        Win31Chrome.darkGray.setStroke()
        path.stroke()
    }
}
