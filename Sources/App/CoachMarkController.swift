import AppKit

/// One-time onboarding coach marks shown after the first setup: a blinking arrow points at the
/// floating launcher button ("Start here"), then Next moves the arrow to the menu-bar icon
/// ("Or start here"), then a note that updates and source live on GitHub. Shown once (gated by
/// AppSettings.hasSeenCoachMarks); Esc or "Got it" dismisses.
final class CoachMarkController {

    static let shared = CoachMarkController()
    private var window: NSWindow?
    private var deferTries = 0
    private init() {}

    struct Step {
        let title: String
        let body: String
        let target: () -> NSRect?     // screen-coordinate rect the arrow points at (nil = centred card)
        var showGitHub = false
    }

    private func steps() -> [Step] {
        [
            Step(title: "Start here",
                 body: "Click this floating button any time to open RetroMac — themes, shaders, TV and games.",
                 target: { FloatingLauncherButton.shared.buttonWindow?.frame }),
            Step(title: "Or start here",
                 body: "The menu-bar icon opens the very same menu. Drag the floating button aside if it's in your way.",
                 target: { AppDelegate.shared?.statusButtonScreenRect }),
            Step(title: "Updates & source",
                 body: "RetroMac updates itself automatically. The full source, release notes and issues live on GitHub.",
                 target: { AppDelegate.shared?.statusButtonScreenRect }, showGitHub: true),
        ]
    }

    /// Show once, after onboarding — but wait until any setup / welcome window is closed.
    func showIfNeeded() {
        let s = AppSettings.shared
        guard s.onboardingComplete, !s.hasSeenCoachMarks, s.floatingLauncherEnabled else { return }
        guard window == nil else { return }
        // Defer while an onboarding/settings window is still frontmost (up to ~24s).
        if NSApp.keyWindow != nil, deferTries < 30 {
            deferTries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showIfNeeded() }
            return
        }
        present()
    }

    /// QA hook: show the overlay regardless of the one-time / key-window gates.
    func forceShow() {
        print("[Coach] forceShow buttonWindow=\(FloatingLauncherButton.shared.buttonWindow != nil ? "yes" : "NIL") statusRect=\(String(describing: AppDelegate.shared?.statusButtonScreenRect))")
        guard window == nil else { return }
        present()
    }

    private func present() {
        guard let screen = NSScreen.main else { return }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false   // stay up even when another app is frontmost
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        let view = CoachMarkView(steps: steps(), onFinish: { [weak self] in self?.finish() })
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }

    private func finish() {
        AppSettings.shared.hasSeenCoachMarks = true
        window?.orderOut(nil)
        window = nil
    }
}

// MARK: - Overlay view

private final class CoachMarkView: NSView {
    private let steps: [CoachMarkController.Step]
    private let onFinish: () -> Void
    private var index = 0
    private var arrowOn = true
    private var blink: Timer?

    private var nextRect: NSRect = .zero
    private var skipRect: NSRect = .zero
    private var githubRect: NSRect = .zero

    init(steps: [CoachMarkController.Step], onFinish: @escaping () -> Void) {
        self.steps = steps; self.onFinish = onFinish
        super.init(frame: .zero)
        wantsLayer = true
        blink = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            self?.arrowOn.toggle(); self?.needsDisplay = true
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    deinit { blink?.invalidate() }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    /// A target rect (screen coords) mapped into this view's coordinate space.
    private func targetInView() -> NSRect? {
        guard let scr = steps[index].target(), let win = window else { return nil }
        return NSRect(x: scr.minX - win.frame.minX, y: scr.minY - win.frame.minY, width: scr.width, height: scr.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        let target = targetInView()

        // Dim everything, punch a rounded hole around the target.
        NSColor.black.withAlphaComponent(0.55).setFill()
        let dim = NSBezierPath(rect: b)
        if let t = target {
            let hole = NSBezierPath(roundedRect: t.insetBy(dx: -10, dy: -10), xRadius: 12, yRadius: 12)
            dim.append(hole.reversed)
        }
        dim.fill()
        if let t = target {   // bright ring around the target
            let ring = NSBezierPath(roundedRect: t.insetBy(dx: -10, dy: -10), xRadius: 12, yRadius: 12)
            NSColor.white.withAlphaComponent(arrowOn ? 0.95 : 0.45).setStroke()
            ring.lineWidth = 3; ring.stroke()
        }

        // Card, positioned toward screen centre from the target.
        let card = cardRect(for: target, in: b)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 0.98).setFill(); cardPath.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); cardPath.lineWidth = 1; cardPath.stroke()

        // Blinking arrow from the card to the target.
        if let t = target { drawArrow(from: card, to: t, ctx: ctx) }

        drawCardContent(in: card)
    }

    private func cardRect(for target: NSRect?, in b: NSRect) -> NSRect {
        let w: CGFloat = 320, h: CGFloat = steps[index].showGitHub ? 176 : 150
        guard let t = target else { return NSRect(x: b.midX - w/2, y: b.midY - h/2, width: w, height: h) }
        // Place the card on the side of the target that has more room, offset by a gap.
        var x = t.midX - w/2
        x = max(24, min(b.maxX - w - 24, x))
        // Below the target if there's room, else above.
        var y = t.minY - h - 46
        if y < 24 { y = t.maxY + 46 }
        y = max(24, min(b.maxY - h - 24, y))
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func drawArrow(from card: NSRect, to target: NSRect, ctx: CGContext) {
        let start = NSPoint(x: card.midX, y: card.maxY <= target.minY ? card.maxY : card.minY)
        let end = NSPoint(x: target.midX, y: card.maxY <= target.minY ? target.minY - 8 : target.maxY + 8)
        let col = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.2, alpha: arrowOn ? 1.0 : 0.25)
        col.setStroke(); col.setFill()
        let shaft = NSBezierPath()
        shaft.move(to: start); shaft.line(to: end); shaft.lineWidth = 4
        shaft.lineCapStyle = .round; shaft.stroke()
        // Arrow head pointing at the target.
        let dir = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let len = max(1, hypot(dir.dx, dir.dy)); let ux = dir.dx/len, uy = dir.dy/len
        let hb = NSPoint(x: end.x - ux*14, y: end.y - uy*14)
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: NSPoint(x: hb.x - uy*8, y: hb.y + ux*8))
        head.line(to: NSPoint(x: hb.x + uy*8, y: hb.y - ux*8))
        head.close(); head.fill()
    }

    private func drawCardContent(in card: NSRect) {
        let step = steps[index]
        let pad: CGFloat = 18
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: NSColor.white]
        (step.title as NSString).draw(at: NSPoint(x: card.minX + pad, y: card.maxY - 30), withAttributes: titleAttr)

        let bodyStyle = NSMutableParagraphStyle(); bodyStyle.lineSpacing = 2
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor(white: 0.85, alpha: 1),
            .paragraphStyle: bodyStyle]
        let bodyRect = NSRect(x: card.minX + pad, y: card.minY + 46, width: card.width - pad*2, height: card.height - 84)
        (step.body as NSString).draw(in: bodyRect, withAttributes: bodyAttr)

        // Step dots.
        let dotY = card.minY + 22
        for i in 0..<steps.count {
            let on = i == index
            (on ? NSColor.white : NSColor(white: 1, alpha: 0.3)).setFill()
            NSBezierPath(ovalIn: NSRect(x: card.minX + pad + CGFloat(i)*14, y: dotY, width: 7, height: 7)).fill()
        }

        // Buttons (bottom-right): [Skip] [View on GitHub?] [Next / Got it]
        let isLast = index == steps.count - 1
        let nextLabel = isLast ? "Got it" : "Next \u{2192}"
        nextRect = button(label: nextLabel, rightEdge: card.maxX - pad, y: card.minY + 14, filled: true)
        var nextLeft = nextRect.minX - 10
        if step.showGitHub {
            githubRect = button(label: "View on GitHub", rightEdge: nextLeft, y: card.minY + 14, filled: false)
            nextLeft = githubRect.minX - 10
        } else { githubRect = .zero }
        skipRect = button(label: "Skip", rightEdge: nextLeft, y: card.minY + 14, filled: false, subtle: true)
    }

    @discardableResult
    private func button(label: String, rightEdge: CGFloat, y: CGFloat, filled: Bool, subtle: Bool = false) -> NSRect {
        let font = NSFont.systemFont(ofSize: 12, weight: filled ? .semibold : .regular)
        let sz = (label as NSString).size(withAttributes: [.font: font])
        let w = sz.width + 22, h: CGFloat = 26
        let r = NSRect(x: rightEdge - w, y: y, width: w, height: h)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        if filled { NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.2, alpha: 1).setFill(); path.fill() }
        else { NSColor(white: 1, alpha: subtle ? 0.06 : 0.12).setFill(); path.fill() }
        let color = filled ? NSColor.black : NSColor(white: 1, alpha: subtle ? 0.6 : 0.92)
        (label as NSString).draw(at: NSPoint(x: r.minX + 11, y: r.midY - sz.height/2),
                                 withAttributes: [.font: font, .foregroundColor: color])
        return r
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if nextRect.contains(p) { advance(); return }
        if skipRect.contains(p) { onFinish(); return }
        if !githubRect.isEmpty && githubRect.contains(p) { AppDelegate.shared?.openGitHubRepo(); onFinish(); return }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish() }        // Esc
        else if event.keyCode == 36 || event.keyCode == 49 { advance() }   // Return / Space
        else { super.keyDown(with: event) }
    }

    private func advance() {
        if index < steps.count - 1 { index += 1; needsDisplay = true } else { onFinish() }
    }
}
