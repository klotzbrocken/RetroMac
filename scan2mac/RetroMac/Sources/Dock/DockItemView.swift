import AppKit

final class DockItemView: NSView {
    let bundleID: String
    private var iconImageView: NSImageView!
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var indicatorLayer: CALayer?

    var onLeftClick: ((String) -> Void)?
    var onRightClick: ((String, NSPoint) -> Void)?

    init(bundleID: String, frame: NSRect) {
        self.bundleID = bundleID
        super.init(frame: frame)
        wantsLayer = true
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
        let duration = ThemeManager.shared.activeTheme?.config.icon.hoverAnimationDuration ?? 0.15
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            self.layer?.setAffineTransform(.identity)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onLeftClick?(bundleID)
    }

    override func rightMouseDown(with event: NSEvent) {
        let screenPoint = window?.convertPoint(toScreen: convert(event.locationInWindow, from: nil)) ?? .zero
        onRightClick?(bundleID, screenPoint)
    }

    private func tooltipText() -> String? {
        if let app = AppManager.shared.apps.first(where: { $0.bundleID == bundleID }) {
            return app.displayName
        }
        return bundleID
    }
}
