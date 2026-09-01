import AppKit

/// The windows a simulated crash puts on screen, and the input trap that is not one.
///
/// There is no event tap here and there never will be. Our window is key and RetroMac is the
/// active application, so keystrokes arrive here; that is the entire mechanism. It cannot lock
/// anyone out of their Mac, because the moment RetroMac stops being active the keys go back to
/// wherever the user sent them — which is also why `CrashDirector` tears the whole thing down on
/// `didResignActive` rather than trying to hold on.
final class CrashWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Fills a screen with one crash image, scaled up whole-number with nearest-neighbour so the
/// pixels stay square and honest. Swallows input; asks the director what a key means.
final class CrashView: NSView {

    var onKey: ((NSEvent) -> Void)?
    var onEscape: (() -> Void)?
    /// A dialog button was clicked. A dialog whose buttons do nothing is the detail that gives
    /// the whole illusion away.
    var onButton: ((String) -> Void)?
    /// Hint drawn outside the picture, in the letterbox, so the screen itself stays faithful.
    var showsEscapeHint = true

    private let imageLayer = CALayer()
    private var hintLabel: NSTextField?
    private var overlayView: NSView?
    private var badgeLabel: NSTextField?
    /// Kept so a re-layout after a new overlay can rebuild the badge with the same wording.
    private var badgeName: String?
    private let fakeCursorLayer = CALayer()
    /// Clickable rects of the dialog currently on screen, in view coordinates.
    private var hotspots: [(rect: NSRect, label: String)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .nearest
        imageLayer.contentsGravity = .resize
        imageLayer.isOpaque = true
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    // MARK: - The pointer that stops keeping up

    /// Show a drawn pointer at `point` (view coordinates) instead of the real one.
    ///
    /// The real cursor is hidden and this one is put in its place a few frames behind, which is
    /// what a machine that has stopped answering looks like. The real pointer is never moved —
    /// warping somebody's mouse would be a genuine loss of control rather than a joke.
    func showFakeCursor(at point: NSPoint) {
        if fakeCursorLayer.superlayer == nil {
            let cursor = NSCursor.arrow
            let image = cursor.image
            fakeCursorLayer.contents = image
            fakeCursorLayer.bounds = CGRect(origin: .zero, size: image.size)
            fakeCursorLayer.anchorPoint = CGPoint(x: cursor.hotSpot.x / max(1, image.size.width),
                                                  y: 1 - cursor.hotSpot.y / max(1, image.size.height))
            fakeCursorLayer.contentsScale = window?.backingScaleFactor ?? 2
            layer?.addSublayer(fakeCursorLayer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fakeCursorLayer.position = point
        CATransaction.commit()
    }

    func hideFakeCursor() {
        fakeCursorLayer.removeFromSuperlayer()
    }

    /// "simulated crash", bottom right, in red. The one piece of the screen that is not in
    /// period, on purpose: nobody should walk past this desk and believe the machine is broken.
    func showBadge(_ visible: Bool, name: String? = nil) {
        if !visible { badgeLabel?.removeFromSuperview(); badgeLabel = nil; return }
        if badgeLabel == nil {
            // The name is there so a demo can see WHICH failure came up — and so "it always
            // shows the same one" becomes a checkable statement instead of an impression.
            badgeName = name
            let text = name.map { "simulated crash · \($0)" } ?? "simulated crash"
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 12, weight: .semibold)
            l.textColor = NSColor(srgbRed: 1.0, green: 0.25, blue: 0.22, alpha: 1)
            l.sizeToFit()
            badgeLabel = l
        }
        guard let l = badgeLabel else { return }
        l.frame.origin = NSPoint(x: bounds.maxX - l.frame.width - 18, y: 16)
        addSubview(l)          // re-added so it stays on top of anything drawn later
    }

    // MARK: - Content

    /// A pixel-exact screen: scaled by a whole number so every source pixel becomes an identical
    /// block. The leftover border reads as the overscan of a CRT, which is the correct look.
    func show(pixelImage: CGImage, stretchToFill: Bool) {
        // A full-screen surface replaces whatever was on screen. Without this the dialog that
        // led to a blue screen stayed sitting on top of it, and the two were on screen at once —
        // which is not a thing that could happen on a real machine.
        clearOverlay()
        let scale = window?.backingScaleFactor ?? 2
        let pxW = bounds.width * scale, pxH = bounds.height * scale
        let srcW = CGFloat(pixelImage.width), srcH = CGFloat(pixelImage.height)

        var w: CGFloat, h: CGFloat
        if stretchToFill {
            // Period-correct in its own way: a 4:3 signal stretched across the whole panel.
            w = bounds.width; h = bounds.height
        } else {
            let k = max(1, floor(min(pxW / srcW, pxH / srcH)))
            w = srcW * k / scale
            h = srcH * k / scale
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contentsScale = scale
        imageLayer.contents = pixelImage
        imageLayer.frame = CGRect(x: ((bounds.width - w) / 2).rounded(),
                                  y: ((bounds.height - h) / 2).rounded(),
                                  width: w, height: h)
        CATransaction.commit()
        layoutHint()
    }

    /// A still of the desktop, or a black frame. Drawn edge to edge, smoothly — it is a photo of
    /// the real screen, not a text mode.
    func show(fullBleed image: CGImage?) {
        clearOverlay()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.magnificationFilter = .linear
        imageLayer.contents = image
        imageLayer.frame = bounds
        CATransaction.commit()
    }

    /// A dialog or a curtain on top of the frozen desktop rather than instead of it.
    ///
    /// `fill` covers the whole screen (the kernel panic). Otherwise the image is placed at its own
    /// logical size — it carries a representation at the display's resolution, so it draws crisp;
    /// the earlier version drew at 1x and scaled the view up by two, which is what made it soft.
    /// `buttons` are rects in the image's coordinates and come back through `onButton`.
    func showOverlay(_ overlay: NSImage, over still: CGImage?, fill: Bool,
                     buttons: [(rect: NSRect, label: String)] = []) {
        show(fullBleed: still)          // clears any previous overlay
        let frame = fill
            ? bounds
            : NSRect(x: ((bounds.width - overlay.size.width) / 2).rounded(),
                     y: ((bounds.height - overlay.size.height) / 2).rounded(),
                     width: overlay.size.width, height: overlay.size.height)
        let host = NSImageView(frame: frame)
        host.image = overlay
        host.imageScaling = fill ? .scaleAxesIndependently : .scaleNone
        addSubview(host)
        overlayView = host
        hotspots = buttons.map { (rect: $0.rect.offsetBy(dx: frame.minX, dy: frame.minY), label: $0.label) }
        layoutHint()
        if badgeLabel != nil { showBadge(true) }
    }

    /// Take down whatever dialog is on screen, and forget where its buttons were. Hotspots that
    /// outlive their picture are worse than none: they are invisible click targets.
    private func clearOverlay() {
        overlayView?.removeFromSuperview()
        overlayView = nil
        hotspots = []
    }

    private func layoutHint() {
        guard showsEscapeHint else { return }
        if hintLabel == nil {
            let l = NSTextField(labelWithString: "Esc")
            l.font = .systemFont(ofSize: 11, weight: .regular)
            l.textColor = NSColor.white.withAlphaComponent(0.28)
            l.sizeToFit()
            addSubview(l)
            hintLabel = l
        }
        hintLabel?.frame.origin = NSPoint(x: bounds.maxX - (hintLabel?.frame.width ?? 20) - 10, y: 8)
        if let l = hintLabel { addSubview(l) }   // keep it above anything added later
    }

    // MARK: - Input

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Every click in this view belongs to this view, whatever is layered on top of it — the same
    /// trick the boot screen uses (SplashController's BootDismissView).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // Swallowed on purpose. No `super`: that would pass them up the responder chain.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let hit = hotspots.first(where: { $0.rect.contains(p) }) { onButton?(hit.label) }
    }
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return }   // Esc, always
        onKey?(event)
        // Deliberately no `super.keyDown`, which would beep at every keystroke.
    }

    /// Esc can also arrive as a command rather than a key event.
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// Cmd-Q and friends must keep working. Returning false hands them on to the app.
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }
}

/// One window per screen, and the guarantee that they all disappear together.
final class CrashSession {

    private(set) var views: [CrashView] = []
    private var windows: [CrashWindow] = []
    /// The screen the failure is shown on; the others get the same treatment so a second monitor
    /// does not sit there cheerfully showing the desktop.
    private(set) var mainView: CrashView?

    init() {
        for screen in NSScreen.screens {
            let win = CrashWindow(contentRect: screen.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            win.level = .screenSaver
            win.isOpaque = true
            win.backgroundColor = .black
            win.hasShadow = false
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            win.ignoresMouseEvents = false
            win.acceptsMouseMovedEvents = true

            let view = CrashView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.showsEscapeHint = (screen == NSScreen.main)
            win.contentView = view
            windows.append(win)
            views.append(view)
            if screen == NSScreen.main { mainView = view }
        }
        if mainView == nil { mainView = views.first }
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        for win in windows { win.orderFrontRegardless() }
        if let main = windows.first(where: { $0.contentView === mainView }) ?? windows.first {
            main.makeKeyAndOrderFront(nil)
            if let v = main.contentView { main.makeFirstResponder(v) }
        }
    }

    var isKey: Bool { windows.contains { $0.isKeyWindow } }

    func close() {
        for win in windows { win.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        mainView = nil
    }

    /// The safety net under the safety net: if a session is ever dropped without `close()`, its
    /// windows still go away when it is deallocated.
    deinit { for win in windows { win.orderOut(nil) } }
}
