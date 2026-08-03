import AppKit

/// An elongated Windows-style taskbar button: icon + (truncated) title, themed for Win98
/// (raised/sunken bevel) or XP Luna (glossy blue). The "active" window's button is drawn
/// pressed/sunken. Used only by the Win98/XP taskbar; click is handled by DockView.
final class TaskButtonView: NSView {

    enum Style { case win98, winxp, win7 }

    private let title: String
    private let icon: NSImage?
    private let style: Style
    private var isActive: Bool
    /// Upper bound for the tab icon — the Quick Launch icon size, so a tab icon is never LARGER
    /// than the pinned Quick Launch icons.
    private let maxIconSize: CGFloat
    /// True when `icon` is a real macOS app icon (theme has no art for this app). Such icons carry
    /// built-in transparent padding, so they are drawn slightly enlarged to visually match the
    /// edge-to-edge themed tabs.
    private let enlargeIcon: Bool
    var onClick: (() -> Void)?
    private var pressed = false
    private var hovered = false
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, title: String, icon: NSImage?, style: Style, isActive: Bool, maxIconSize: CGFloat, enlargeIcon: Bool = false) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isActive = isActive
        self.maxIconSize = maxIconSize
        self.enlargeIcon = enlargeIcon
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Optimistic active-state update on click (the tracker poll reconciles it later).
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active; needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        addTrackingArea(ta); trackingArea = ta
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        pressed = true; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        pressed = false; needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let sunken = isActive || pressed
        switch style {
        case .win98: drawWin98(ctx, sunken: sunken)
        case .winxp: drawXP(ctx, sunken: sunken, hovered: hovered && !sunken)
        case .win7:  drawWin7(ctx, sunken: sunken, hovered: hovered && !sunken)
        }
        drawContent(sunken: sunken)
    }

    // MARK: - Win98 raised/sunken bevel

    private func drawWin98(_ ctx: CGContext, sunken: Bool) {
        let b = bounds
        (Win98Scheme.activeFaceColor() ?? NSColor(srgbRed: 0.769, green: 0.769, blue: 0.769, alpha: 1)).setFill()   // scheme face / #C4C4C4
        ctx.fill(b)
        func line(_ r: NSRect, _ c: NSColor) { c.setFill(); ctx.fill(r) }
        let white = NSColor.white
        let light = NSColor(srgbRed: 0.859, green: 0.859, blue: 0.859, alpha: 1)  // #DBDBDB
        let shade = NSColor(srgbRed: 0.502, green: 0.502, blue: 0.502, alpha: 1)  // #808080
        let dark  = NSColor.black
        // top-left vs bottom-right depending on raised/sunken
        let tl1 = sunken ? shade : white
        let tl2 = sunken ? dark  : light
        let br1 = sunken ? light : shade
        let br2 = sunken ? white : dark
        line(NSRect(x: 0, y: b.maxY - 1, width: b.width, height: 1), tl1)            // top (flipped? no — y-up: top = maxY)
        line(NSRect(x: 0, y: 0, width: 1, height: b.height), tl1)                    // left
        line(NSRect(x: 0, y: b.maxY - 2, width: b.width - 1, height: 1), tl2)
        line(NSRect(x: 1, y: 1, width: 1, height: b.height - 2), tl2)
        line(NSRect(x: 0, y: 0, width: b.width, height: 1), br1)                     // bottom
        line(NSRect(x: b.width - 1, y: 0, width: 1, height: b.height), br1)          // right
        line(NSRect(x: 1, y: 1, width: b.width - 2, height: 1), br2)
        line(NSRect(x: b.width - 2, y: 1, width: 1, height: b.height - 2), br2)
    }

    // MARK: - XP Luna glossy blue

    private func drawXP(_ ctx: CGContext, sunken: Bool, hovered: Bool) {
        let b = bounds
        // XP program tab (UI-kit "Program tab"): gentle vertical gradient with a subtle 3D edge
        // (light top highlight + darker bottom shadow) and a 1px light border. Three states:
        // resting / hover (brighter) / active (dark navy, recessed).
        func c(_ r: CGFloat, _ g: CGFloat, _ bl: CGFloat) -> NSColor {
            NSColor(srgbRed: r, green: g, blue: bl, alpha: 1)
        }
        let top: NSColor, bot: NSColor, border: NSColor
        if sunken {                                   // active window — dark navy, inset
            top = c(0.16, 0.33, 0.69); bot = c(0.09, 0.22, 0.52); border = c(0.07, 0.16, 0.40)
        } else if hovered {                           // hover — brighter blue
            top = c(0.49, 0.69, 0.97); bot = c(0.24, 0.47, 0.89); border = c(0.62, 0.79, 0.99)
        } else {                                      // resting
            top = c(0.36, 0.57, 0.92); bot = c(0.16, 0.37, 0.80); border = c(0.55, 0.73, 0.97)
        }
        let path = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSGradient(starting: bot, ending: top)?.draw(in: path, angle: 90)
        // 3D edge: 1px light highlight along the top, 1px shadow along the bottom (clipped).
        NSGraphicsContext.current?.saveGraphicsState(); path.addClip()
        let hi = sunken ? NSColor.white.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.45)
        hi.setFill(); ctx.fill(NSRect(x: b.minX, y: b.maxY - 2, width: b.width, height: 1.5))
        NSColor.black.withAlphaComponent(0.22).setFill()
        ctx.fill(NSRect(x: b.minX, y: b.minY, width: b.width, height: 1.5))
        NSGraphicsContext.current?.restoreGraphicsState()
        border.setStroke(); path.lineWidth = 1; path.stroke()
    }

    // MARK: - Win7 Aero glass tab

    private func drawWin7(_ ctx: CGContext, sunken: Bool, hovered: Bool) {
        let b = bounds
        func c(_ r: CGFloat, _ g: CGFloat, _ bl: CGFloat, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: r, green: g, blue: bl, alpha: a)
        }
        // Translucent glass panel; brighter when the window is open (sunken) or hovered.
        let top: NSColor, bot: NSColor, border: NSColor
        if sunken {                       // open/active window — lit aqua glass
            top = c(0.92, 0.97, 1.0, 0.78); bot = c(0.66, 0.85, 0.96, 0.66); border = c(0.24, 0.50, 0.69, 0.9)
        } else if hovered {               // hover — soft aqua glow
            top = c(0.92, 0.96, 0.99, 0.55); bot = c(0.75, 0.90, 0.98, 0.42); border = c(0.24, 0.50, 0.69, 0.75)
        } else {                          // resting — faint glass
            top = c(1, 1, 1, 0.22); bot = c(1, 1, 1, 0.06); border = c(1, 1, 1, 0.42)
        }
        let path = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSGradient(starting: bot, ending: top)?.draw(in: path, angle: 90)
        NSGraphicsContext.current?.saveGraphicsState(); path.addClip()
        NSColor.white.withAlphaComponent(sunken ? 0.6 : 0.4).setFill()   // top inner highlight
        ctx.fill(NSRect(x: b.minX, y: b.maxY - 2, width: b.width, height: 1.5))
        NSGraphicsContext.current?.restoreGraphicsState()
        border.setStroke(); path.lineWidth = 1; path.stroke()
    }

    // MARK: - Icon + title

    private func drawContent(sunken: Bool) {
        let b = bounds
        let off: CGFloat = (sunken ? 1 : 0)
        // Win98 icon sits inside the button with a little margin (not edge-to-edge); XP = larger
        // icon per the UI-kit tab. Capped at the Quick Launch icon size so a tab icon is never
        // larger than those. Real macOS app icons (enlargeIcon) get a ~15% bump to offset their
        // built-in transparent padding so they read the same size as the themed tabs.
        let base: CGFloat = (style == .win98) ? (b.height - 6) : min(26, b.height - 2)
        var iconSz = min(base, maxIconSize)
        if enlargeIcon { iconSz = min(b.height - 2, iconSz * 1.15) }
        let iconX = (style == .win98 ? 6 : 6) + off
        let iconY = (b.height - iconSz) / 2 - off
        var textX = iconX
        if let icon = icon {
            icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSz, height: iconSz),
                      from: .zero, operation: .sourceOver, fraction: 1.0)
            textX = iconX + iconSz + 5
        }
        let isWin98 = (style == .win98)
        let darkText = (style == .win98 || style == .win7)   // Win7 Superbar is light glass → dark text
        let color: NSColor = darkText ? .black : .white
        let fsize: CGFloat = isWin98 ? 13 : 12
        let fontName = (style == .win7) ? "Segoe UI" : "Tahoma"   // Win7 uses Segoe UI
        let font = NSFont(name: fontName, size: fsize)
            ?? NSFont.systemFont(ofSize: fsize, weight: isWin98 ? .regular : .semibold)
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        if style == .winxp {   // white XP text needs a dark shadow; dark glass/98 text does not
            let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.5)
            sh.shadowOffset = NSSize(width: 0, height: -1); attrs[.shadow] = sh
        }
        let th = font.ascender - font.descender
        let textRect = NSRect(x: textX, y: (b.height - th) / 2 - off,
                              width: max(0, b.width - textX - 5 - off), height: th + 2)
        (title as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
