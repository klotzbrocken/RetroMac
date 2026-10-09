import AppKit

final class DockItemView: NSView {
    let bundleID: String
    private var iconImageView: NSImageView!
    private(set) var reflectionLayer: CALayer?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var indicatorLayer: CALayer?
    // Indicator layout params, kept so the dot can be re-centred whenever the item is
    // resized (magnification grows the frame; a one-shot position drifts off-centre).
    private var indicatorSize: CGFloat = 0
    private var indicatorOffset: CGFloat = 0
    private var indicatorVertical = false
    private var indicatorOnRight = false
    // Actual layer dimensions (differ from indicatorSize for the oval "glow" style), so
    // magnification re-centering keeps any indicator shape correct.
    private var indicatorW: CGFloat = 0
    private var indicatorH: CGFloat = 0
    private var indicatorYOrigin: CGFloat = 0
    private var previewTimer: Timer?
    private var holdTimer: Timer?
    private var didLongPress = false
    /// A press on a pinned item that may still become a drag along the dock: the click waits
    /// for the mouse-up, the way the Mac's Dock launches on release.
    private var pressPoint: NSPoint?
    private var clickPending = false
    /// Pinned items (apps and folders in the dock's list) can be dragged to another place.
    private var isPinned: Bool { AppManager.shared.apps.contains { $0.bundleID == bundleID } }

    var onLeftClick: ((String) -> Void)?
    var onRightClick: ((String, NSPoint) -> Void)?
    /// Holding this icon shows that app's windows, the way 10.6 did. Only armed while the theme
    /// that had the gesture is active — which is checked when the press happens, not when the
    /// tile is built, because the dock outlives a theme switch.
    var onLongPress: ((String) -> Void)?
    private var holdArmed: Bool { onLongPress != nil && RetroFrameTheme.key() == "snowleopard" }
    var magnificationEnabled = false

    init(bundleID: String, frame: NSRect) {
        self.bundleID = bundleID
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        setupIcon()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // VoiceOver: each item is a button named after its app (or folder, or the Trash).
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { tooltipText() }
    override func accessibilityPerformPress() -> Bool { onLeftClick?(bundleID); return true }
    override func accessibilityPerformShowMenu() -> Bool {
        guard let window else { return false }
        onRightClick?(bundleID, window.convertPoint(toScreen: convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)))
        return true
    }

    private func setupIcon() {
        iconImageView = NSImageView(frame: bounds.insetBy(dx: 2, dy: 2))
        iconImageView.setAccessibilityElement(false)   // the item speaks for it
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.autoresizingMask = [.width, .height]
        addSubview(iconImageView)
    }

    func updateIcon(_ image: NSImage) {
        iconImageView.image = image
        // A new picture (the Trash filling up) gets a new reflection too, not the old one's.
        reflectionLayer?.sublayers?.first?.contents = Self.mirrored(image, size: iconImageView.frame.size)
    }

    /// The whole icon upside down. It is drawn when the layer needs it, at the size and
    /// resolution the layer has then, so a magnified icon's reflection is as sharp as the icon.
    private static func mirrored(_ image: NSImage, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }


    func updateTheme(_ theme: DockThemeConfig) {
        if theme.isPixelated {
            iconImageView.layer?.magnificationFilter = .nearest
            iconImageView.layer?.minificationFilter = .nearest
        } else {
            iconImageView.layer?.magnificationFilter = .linear
            iconImageView.layer?.minificationFilter = .linear
        }
        updateReflection(theme: theme)
    }

    private func updateReflection(theme: DockThemeConfig) {
        reflectionLayer?.removeFromSuperlayer()
        reflectionLayer = nil

        // Vertical docks (left/right) drop the 3D floor entirely — no reflection.
        guard theme.icon.reflectionEnabled, !theme.isVertical,
              let image = iconImageView.image else { return }

        let mirror = CALayer()
        mirror.contents = Self.mirrored(image, size: iconImageView.frame.size)
        // Shows the strip of the mirror image that lies right under the icon, fading downwards.
        let strip = CALayer()
        strip.masksToBounds = true
        strip.opacity = Float(theme.icon.reflectionOpacity)
        strip.addSublayer(mirror)
        let fade = CAGradientLayer()
        // The unit space of a layer starts at the BOTTOM on the Mac: 1 is the edge under the icon.
        fade.colors = [NSColor.white.cgColor, NSColor.clear.cgColor]
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        strip.mask = fade

        layer?.insertSublayer(strip, at: 0)
        reflectionLayer = strip
        layoutReflection()
    }

    /// The reflection follows the icon: as wide as it, as far down as 45 % of its height, but
    /// never past the bottom of the dock, so the fade ends on the shelf instead of being cut
    /// off by the screen edge. Called again whenever magnification resizes the item.
    private func layoutReflection() {
        guard let strip = reflectionLayer, let mirror = strip.sublayers?.first else { return }
        let icon = iconImageView.frame
        let room = superview == nil ? icon.height : frame.minY + icon.minY   // down to the dock's bottom
        let height = max(0, min(icon.height * 0.45, room))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.frame = CGRect(x: icon.minX, y: icon.minY - height, width: icon.width, height: height)
        strip.mask?.frame = strip.bounds
        mirror.frame = CGRect(x: 0, y: height - icon.height, width: icon.width, height: icon.height)
        CATransaction.commit()
    }

    func setRunningIndicator(visible: Bool, theme: DockThemeConfig) {
        indicatorLayer?.removeFromSuperlayer()
        indicatorLayer = nil

        guard visible else { return }
        // `indicator.style: "none"` suppresses the running-app dot entirely (e.g. Windows 98/Me/XP,
        // where the taskbar shows running programs as buttons — a dot under the icon isn't authentic).
        guard theme.indicator.style != "none" else { return }

        let dot = CALayer()
        let sz = theme.indicator.size
        let off = theme.indicator.offset
        indicatorSize = sz
        indicatorOffset = off
        indicatorVertical = theme.isVertical
        indicatorOnRight = theme.effectiveDockPosition == "right"
        if theme.isVertical {
            // Indicator sits on the SCREEN-EDGE side of the icon (left dock → left,
            // right dock → right), matching the real Dock.
            let onRight = theme.effectiveDockPosition == "right"
            let x = onRight ? (bounds.width + off - sz) : (-off)
            dot.frame = CGRect(
                x: x,
                y: (bounds.height - sz) / 2,
                width: sz,
                height: sz
            )
        } else {
            dot.frame = CGRect(
                x: (bounds.width - sz) / 2,
                y: -off,
                width: sz,
                height: sz
            )
        }

        indicatorW = dot.frame.width; indicatorH = dot.frame.height; indicatorYOrigin = dot.frame.origin.y

        let color = NSColor.fromHex(theme.indicator.color)
        if theme.indicator.style == "glow" {
            // Snow Leopard running indicator: a soft, oval light-blue bloom at the icon's base
            // (radial gradient → transparent edge = washed-out glow).
            let glow = CAGradientLayer()
            glow.type = .radial
            glow.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
            glow.locations = [0, 1]
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            let gw = sz * 3.4, gh = sz * 1.7   // oval: wider than tall
            let frame: CGRect
            if theme.isVertical {
                let x = indicatorOnRight ? (bounds.width + off - gw) : (-off - gw + sz)
                frame = CGRect(x: x, y: (bounds.height - gh) / 2, width: gw, height: gh)
            } else {
                frame = CGRect(x: (bounds.width - gw) / 2, y: -off - gh * 0.25, width: gw, height: gh)
            }
            glow.frame = frame
            indicatorW = gw; indicatorH = gh; indicatorYOrigin = frame.origin.y
            layer?.addSublayer(glow)
            indicatorLayer = glow
            return
        }
        if theme.indicator.style == "triangle" {
            // Classic Mac OS X running indicator: a small solid triangle pointing toward the
            // icon (up for bottom docks, sideways for vertical docks) — `size` wide and a little
            // over half as tall, 9 × 5 in 10.0.
            let tri = CAShapeLayer()
            let depth = (sz * 0.56).rounded()
            var f = dot.frame
            if theme.isVertical {
                if indicatorOnRight { f.origin.x += sz - depth }
                f.size.width = depth
            } else {
                f.size.height = depth
            }
            tri.frame = f
            indicatorW = f.width; indicatorH = f.height; indicatorYOrigin = f.origin.y
            let p = CGMutablePath()
            if theme.isVertical {
                let pointRight = theme.effectiveDockPosition != "right"
                if pointRight { p.move(to: CGPoint(x: depth, y: sz/2)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: sz)) }
                else          { p.move(to: CGPoint(x: 0, y: sz/2)); p.addLine(to: CGPoint(x: depth, y: 0)); p.addLine(to: CGPoint(x: depth, y: sz)) }
            } else {
                p.move(to: CGPoint(x: sz/2, y: depth)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: sz, y: 0))
            }
            p.closeSubpath()
            tri.path = p
            tri.fillColor = color.cgColor
            layer?.addSublayer(tri)
            indicatorLayer = tri
            return
        }
        if theme.indicator.style == "square" {
            dot.backgroundColor = color.cgColor
        } else {
            dot.backgroundColor = color.cgColor
            dot.cornerRadius = sz / 2
        }
        layer?.addSublayer(dot)
        indicatorLayer = dot
    }

    /// Keep the running dot centred when the item is resized (magnification effect) —
    /// its frame was computed against the ORIGINAL bounds and would drift left otherwise.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutReflection()
        guard let ind = indicatorLayer, indicatorW > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if indicatorVertical {
            let x = indicatorOnRight ? (bounds.width + indicatorOffset - indicatorW) : (-indicatorOffset)
            ind.frame = CGRect(x: x, y: (bounds.height - indicatorH) / 2, width: indicatorW, height: indicatorH)
        } else {
            ind.frame = CGRect(x: (bounds.width - indicatorW) / 2, y: indicatorYOrigin, width: indicatorW, height: indicatorH)
        }
        CATransaction.commit()
    }

    // MARK: - Tracking & Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        // Skip individual hover when magnification handles scaling from DockView
        guard !magnificationEnabled else {
            if let tooltip = tooltipText() { self.toolTip = tooltip }
            return
        }
        let theme = ThemeManager.shared.activeTheme?.config
        let scale = theme?.icon.hoverScale ?? 1.15
        let duration = theme?.icon.hoverAnimationDuration ?? 0.15
        // The layer's anchor is the bottom-LEFT corner, so a plain scale grows up AND to
        // the right. Recenter horizontally (shift left by half the growth) so the icon
        // pops straight UP out of the dock, bottom edge anchored on the dock floor.
        let isVertical = theme?.isVertical ?? false
        let dx = isVertical ? 0 : -(scale - 1.0) * self.bounds.width / 2.0
        // Raise above neighbours so the growth isn't occluded on one side.
        self.layer?.zPosition = 10
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            self.layer?.setAffineTransform(CGAffineTransform(translationX: dx, y: 0).scaledBy(x: scale, y: scale))
        }

        if let tooltip = tooltipText() {
            self.toolTip = tooltip
        }

        // Pac-Man theme: hovering an icon releases a ghost that chases Pac-Man, and the
        // icon also becomes a barrier that reverses whoever runs into it.
        (self.superview as? DockView)?.spawnGhostNearItem(frame: self.frame)
        (self.superview as? DockView)?.setHoverBarrier(bundleID: bundleID, frame: self.frame, active: true)

        startWindowPreviewIfEligible()
    }

    /// After ~2s hovering a RUNNING app's icon (themes with windowPreview), show a small
    /// pixelated snapshot of its front window above the dock.
    private func startWindowPreviewIfEligible() {
        previewTimer?.invalidate(); previewTimer = nil
        let cfg = ThemeManager.shared.activeTheme?.config
        guard cfg?.hasWindowPreview == true,
              !bundleID.hasPrefix("__"),
              AppLauncher.isRunning(bundleID: bundleID) else { return }
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self, let win = self.window else { return }
            let screenRect = win.convertToScreen(self.convert(self.bounds, to: nil))
            DockPreviewController.shared.show(for: self.bundleID, anchorScreenRect: screenRect)
        }
    }

    private func cancelWindowPreview() {
        previewTimer?.invalidate(); previewTimer = nil
        DockPreviewController.shared.hide()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        cancelWindowPreview()
        // Always lift the Pac-Man barrier, regardless of magnification state.
        (self.superview as? DockView)?.setHoverBarrier(bundleID: bundleID, frame: self.frame, active: false)
        guard !magnificationEnabled else { return }
        let duration = ThemeManager.shared.activeTheme?.config.icon.hoverAnimationDuration ?? 0.15
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            self.layer?.setAffineTransform(.identity)
        } completionHandler: { [weak self] in
            self?.layer?.zPosition = 0
        }
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        layoutReflection()   // how far down it may reach depends on where the item sits
    }

    func applyMagnification(scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        // Larger icons must render ABOVE their neighbours and the bar, otherwise the
        // part that pops out of the dock is occluded and the icon looks like it stays in.
        layer?.zPosition = scale
        layer?.setAffineTransform(
            CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        )
    }

    func resetMagnification() {
        layer?.zPosition = 0
        layer?.setAffineTransform(.identity)
    }

    // MARK: - Launch bounce

    private(set) var isBouncing = false

    /// The Mac OS X Dock's launch feedback: the icon hops away from the dock's edge, over and
    /// over, until the application has finished launching. `offset` is the hop, in the
    /// direction away from the screen edge (y up for a bottom dock, x for a side dock).
    func startBouncing(offset: CGVector) {
        guard let layer, !isBouncing else { return }
        isBouncing = true
        let horizontal = offset.dx != 0
        let hop = CAKeyframeAnimation(keyPath: horizontal ? "transform.translation.x" : "transform.translation.y")
        hop.values = [0, horizontal ? offset.dx : offset.dy, 0]
        hop.keyTimes = [0, 0.5, 1]
        hop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        hop.duration = 0.62
        hop.repeatCount = .infinity
        hop.isAdditive = true   // on top of whatever the magnifier does with the frame
        layer.add(hop, forKey: "launchBounce")
    }

    /// Launched: finish the hop in the air and come down, no snap.
    func stopBouncing() {
        guard let layer, isBouncing else { return }
        isBouncing = false
        guard let hop = layer.animation(forKey: "launchBounce") as? CAKeyframeAnimation else { return }
        let keyPath = hop.keyPath ?? "transform.translation.y"
        let current = (layer.presentation()?.value(forKeyPath: keyPath) as? CGFloat) ?? 0
        layer.removeAnimation(forKey: "launchBounce")
        guard abs(current) > 0.5 else { return }
        let land = CABasicAnimation(keyPath: keyPath)
        land.fromValue = current
        land.toValue = 0
        land.duration = 0.18
        land.timingFunction = CAMediaTimingFunction(name: .easeIn)
        land.isAdditive = true
        layer.add(land, forKey: "launchLand")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        cancelWindowPreview()
        pressPoint = convert(event.locationInWindow, from: nil)
        clickPending = false
        // Themes without a long press fire on mouse-down — except for a pinned item, which
        // might be dragged: its click waits for the mouse-up.
        guard holdArmed else {
            if isPinned { clickPending = true } else { onLeftClick?(bundleID) }
            return
        }
        didLongPress = false
        holdTimer?.invalidate()
        let t = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.didLongPress = true
            self.onLongPress?(self.bundleID)
        }
        // .common, not the default mode scheduledTimer would give it: the moment the pointer
        // twitches under a held button AppKit runs in event-tracking mode, and a default-mode
        // timer simply stops existing for the duration of the hold.
        RunLoop.current.add(t, forMode: .common)
        holdTimer = t
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint, isPinned else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - start.x, p.y - start.y) > 5 else { return }
        // A drag: no click, no long press; the icon goes along with the pointer.
        pressPoint = nil
        clickPending = false
        holdTimer?.invalidate(); holdTimer = nil
        let item = NSPasteboardItem()
        item.setString(bundleID, forType: .retromacDockItem)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let image = iconImageView.image ?? NSImage(size: bounds.size)
        dragItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        pressPoint = nil
        holdTimer?.invalidate(); holdTimer = nil
        if clickPending { clickPending = false; onLeftClick?(bundleID); return }
        guard holdArmed else { return }
        if !didLongPress { onLeftClick?(bundleID) }
        didLongPress = false
    }

    override func rightMouseDown(with event: NSEvent) {
        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        onRightClick?(bundleID, screenPoint)
    }

    private func tooltipText() -> String? {
        if bundleID == "__trash__" { return "Trash" }
        if let app = AppManager.shared.apps.first(where: { $0.bundleID == bundleID }) {
            return app.displayName
        }
        if bundleID.hasPrefix("__folder__") {
            return (bundleID.replacingOccurrences(of: "__folder__", with: "") as NSString).lastPathComponent
        }
        // An app that is only running, not kept in the dock: its own name, not its bundle id
        // ("com.adguard.mac.vpn" was what the tooltip and VoiceOver said).
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName {
            return running
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        // The dock's own tiles: "__dashboard__" → "Dashboard".
        if bundleID.hasPrefix("__"), bundleID.hasSuffix("__") {
            return bundleID.trimmingCharacters(in: CharacterSet(charactersIn: "_")).capitalized
        }
        return bundleID
    }
}

extension DockItemView: NSDraggingSource {
    /// Along the dock only: dropped anywhere else, the icon simply goes back to its place.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
}
