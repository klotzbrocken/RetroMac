import AppKit

final class DockItemView: NSView {
    let bundleID: String
    private var iconImageView: NSImageView!
    private var reflectionLayer: CALayer?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var indicatorLayer: CALayer?

    var onLeftClick: ((String) -> Void)?
    var onRightClick: ((String, NSPoint) -> Void)?
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

    private func setupIcon() {
        iconImageView = NSImageView(frame: bounds.insetBy(dx: 2, dy: 2))
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.autoresizingMask = [.width, .height]
        addSubview(iconImageView)
    }

    func updateIcon(_ image: NSImage) {
        iconImageView.image = image
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

        guard theme.icon.reflectionEnabled,
              let image = iconImageView.image else { return }

        let iconRect = iconImageView.frame
        let reflectionHeight = iconRect.height * 0.45
        let opacity = theme.icon.reflectionOpacity

        // Create flipped + faded reflection image
        let reflectionImage = NSImage(size: NSSize(width: iconRect.width, height: reflectionHeight))
        reflectionImage.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        // Flip vertically
        ctx.translateBy(x: 0, y: reflectionHeight)
        ctx.scaleBy(x: 1, y: -1)
        // Draw the icon scaled into the reflection area (show the bottom portion flipped)
        image.draw(in: NSRect(x: 0, y: 0, width: iconRect.width, height: iconRect.height),
                   from: .zero, operation: .sourceOver, fraction: 1.0)
        reflectionImage.unlockFocus()

        let refLayer = CALayer()
        refLayer.contents = reflectionImage
        refLayer.frame = CGRect(
            x: iconRect.minX,
            y: iconRect.minY - reflectionHeight + 2,
            width: iconRect.width,
            height: reflectionHeight
        )
        refLayer.opacity = Float(opacity)

        // Gradient mask to fade reflection to transparent at the bottom
        let maskLayer = CAGradientLayer()
        maskLayer.frame = refLayer.bounds
        maskLayer.colors = [NSColor.white.cgColor, NSColor.clear.cgColor]
        maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
        maskLayer.endPoint = CGPoint(x: 0.5, y: 1)
        refLayer.mask = maskLayer

        layer?.insertSublayer(refLayer, at: 0)
        self.reflectionLayer = refLayer
    }

    func setRunningIndicator(visible: Bool, theme: DockThemeConfig) {
        indicatorLayer?.removeFromSuperlayer()
        indicatorLayer = nil

        guard visible else { return }

        let dot = CALayer()
        let sz = theme.indicator.size
        let off = theme.indicator.offset
        if theme.isVertical {
            dot.frame = CGRect(
                x: bounds.width + off - sz,
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

        let color = NSColor.fromHex(theme.indicator.color)
        if theme.indicator.style == "square" {
            dot.backgroundColor = color.cgColor
        } else {
            dot.backgroundColor = color.cgColor
            dot.cornerRadius = sz / 2
        }
        layer?.addSublayer(dot)
        indicatorLayer = dot
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            self.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }

        if let tooltip = tooltipText() {
            self.toolTip = tooltip
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        guard !magnificationEnabled else { return }
        let duration = ThemeManager.shared.activeTheme?.config.icon.hoverAnimationDuration ?? 0.15
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            self.layer?.setAffineTransform(.identity)
        }
    }

    func applyMagnification(scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        layer?.setAffineTransform(
            CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        )
    }

    func resetMagnification() {
        layer?.setAffineTransform(.identity)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onLeftClick?(bundleID)
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
        return bundleID
    }
}
